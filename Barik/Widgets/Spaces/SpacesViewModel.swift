import AppKit
import Combine
import Foundation
import OSLog

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    
    // Combine Pipeline
    private let refreshSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    private var provider: AerospaceSpacesProvider?
    /// space id -> most-recently-focused window id, accumulated as the user
    /// moves around. Lets inactive spaces show the window they'd focus into.
    private var lastFocusedByID: [String: Int] = [:]
    private let pipePath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("barik.fifo")
    private let pipeQueue = DispatchQueue(
        label: "com.app.pipeQueue",
        qos: .userInitiated
    )
    private var pipeSource: DispatchSourceRead?

    /// Mirrors SamplingGate so the fallback poll can pause when hidden/asleep.
    private var gateActive = true

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        provider =
            runningApps.contains("aerospace")
            ? AerospaceSpacesProvider() : nil

        setupNamedPipe()
        setupPipeline()

        // SamplingGate is main-actor isolated; init runs on the main thread, so
        // bridge the isolation explicitly. The pipe (event-driven) keeps
        // working; only the 15s fallback poll is gated.
        MainActor.assumeIsolated {
            SamplingGate.shared.$isActive
                .sink { [weak self] in self?.gateActive = $0 }
                .store(in: &cancellables)
        }

        // Initial load
        refreshSubject.send()
    }

    deinit {
        cleanupPipe()
    }

    private func setupPipeline() {
        let timerPublisher = Timer.publish(every: 15.0, on: .main, in: .common)
            .autoconnect()
            .filter { [weak self] _ in self?.gateActive ?? false }
            .map { _ in "Timer" }

        refreshSubject
            .map { "Pipe" }
            .receive(on: DispatchQueue.main)
            .merge(with: timerPublisher)
            .handleEvents(receiveOutput: { source in
                Logger.pipe.debug("🔵 PIPELINE: Received raw signal from \(source)")
            })
            .buffer(size: 1, prefetch: .keepFull, whenFull: .dropOldest)
            .flatMap(maxPublishers: .max(1)) {
                [weak self] _ -> AnyPublisher<[AnySpace], Never> in
                return self?.fetchSpacesFuture()
                    ?? Empty().eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$spaces)
    }

    private func fetchSpacesFuture() -> AnyPublisher<[AnySpace], Never> {
        return Future { [weak self] promise in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let self = self, let provider = self.provider else {
                    promise(.success([]))
                    return
                }

                Logger.spaces.debug("🚀 LOAD: Starting spaces fetch...")
                let start = Date()

                // This is the blocking work
                let spaces = (provider.getSpacesWithWindows() ?? [])
                    .map { AnySpace($0) }
                let sorted = spaces.sorted { $0.id < $1.id }

                // Remember the focused window as its space's MRU window.
                if let focusedSpace = sorted.first(where: { space in
                    space.windows.contains { $0.isFocused }
                }),
                    let focusedWindow = focusedSpace.windows.first(where: {
                        $0.isFocused
                    })
                {
                    self.lastFocusedByID[focusedSpace.id] = focusedWindow.id
                }

                // Annotate each space with the window focusing it would land
                // on: the remembered MRU window if still open, else the top of
                // the stack as a fallback.
                let annotated = sorted.map { space -> AnySpace in
                    var space = space
                    if let mru = self.lastFocusedByID[space.id],
                        space.windows.contains(where: { $0.id == mru })
                    {
                        space.emphasizedWindowID = mru
                    } else {
                        space.emphasizedWindowID = space.windows.first?.id
                    }
                    return space
                }

                let duration = Date().timeIntervalSince(start)
                Logger.spaces.debug("🐢 DONE: Took \(String(format: "%.2f", duration))s")

                promise(.success(annotated))
            }
        }
        .eraseToAnyPublisher()
    }

    private func setupNamedPipe() {
        cleanupPipe()

        mkfifo(pipePath, 0o666)

        let fd = open(pipePath, O_RDWR | O_NONBLOCK)
        guard fd != -1 else { return }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: pipeQueue
        )
        pipeSource = source

        source.setEventHandler { [weak self] in
            Logger.pipe.trace("⚡️ EVENT HANDLER: Woke up")

            var buffer = [UInt8](repeating: 0, count: 1024)
            var totalBytesRead = 0
            var loops = 0

            while true {
                let bytesRead = read(fd, &buffer, 1024)
                if bytesRead <= 0 { break }
                totalBytesRead += bytesRead
                loops += 1
            }

            Logger.pipe.trace("🧹 DRAINED: \(totalBytesRead) bytes in \(loops) loops")

            if totalBytesRead > 0 {
                Logger.pipe.trace("➡️ SIGNAL: Sending to Combine pipeline")
                self?.refreshSubject.send()
            } else {
                Logger.pipe.trace(
                    "⚠️ WARNING: Woke up but read 0 bytes (Spurious Wakeup)"
                )
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
    }

    private func cleanupPipe() {
        pipeSource?.cancel()
        pipeSource = nil
        unlink(pipePath)
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id,
                needWindowFocus: needWindowFocus
            )
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }

    /// Switch to a space, then focus a specific window in it. The brief settle
    /// delay lets the WM apply the workspace switch first; it runs on a
    /// background queue (never the main thread, which would freeze the UI).
    func switchToSpace(_ space: AnySpace, thenFocus window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(spaceId: space.id, needWindowFocus: false)
            usleep(100_000)
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
