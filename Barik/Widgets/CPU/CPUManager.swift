import Combine
import Darwin
import Foundation

/// Samples per-core CPU load from the Mach host. Each `sample()` returns one
/// busy fraction (0...1) per logical core, measured since the previous call by
/// diffing per-core tick counters.
private struct CPUSampler {
    private var previous: [(busy: Double, total: Double)]?

    /// Per-core busy fractions since the last call, or nil on the first call /
    /// on error (no delta to compute yet).
    mutating func sample() -> [Double]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info,
            &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)  // user, system, idle, nice
        let snapshot: [(busy: Double, total: Double)] = (0..<Int(cpuCount)).map {
            core in
            let base = core * states
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            return (user + system + nice, user + system + nice + idle)
        }

        defer { previous = snapshot }
        guard let prev = previous, prev.count == snapshot.count else {
            return nil
        }
        return zip(snapshot, prev).map { now, was in
            let totalDelta = now.total - was.total
            guard totalDelta > 0 else { return 0 }
            return min(max((now.busy - was.busy) / totalDelta, 0), 1)
        }
    }
}

/// Publishes current per-core CPU usage. Refreshes on a slow cadence by default
/// (a batched, non-distracting update) and a fast one while hovered, for a
/// closer-to-realtime read.
@MainActor
final class CPUManager: ObservableObject {
    /// Current busy fraction (0...1) per logical core.
    @Published private(set) var perCore: [Double] = []

    private let idleInterval: TimeInterval
    private let liveInterval: TimeInterval
    private var sampler = CPUSampler()
    private var timer: AnyCancellable?
    private var gate: AnyCancellable?
    private var isLive = false
    private var gateActive = true

    private static let coreCount = ProcessInfo.processInfo.activeProcessorCount

    init(idleInterval: TimeInterval = 10, liveInterval: TimeInterval = 1) {
        self.idleInterval = idleInterval
        self.liveInterval = liveInterval
        // Drives start/stop; @Published replays the current value immediately,
        // so this also kicks off the initial timer.
        gate = SamplingGate.shared.$isActive.sink { [weak self] active in
            self?.gateActive = active
            self?.restart()
        }
        // Populate immediately so the chart isn't empty until the first tick.
        // Random mode can fill at once; the real sampler needs a brief window
        // to produce a meaningful first delta.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (widgetDebugRandom ? 0 : 0.4)
        ) {
            [weak self] in self?.tick()
        }
    }

    /// Switch between the slow (idle) and fast (live, e.g. on hover) cadence.
    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        restart()
    }

    private func restart() {
        timer = nil
        guard gateActive else { return }
        // Re-prime the counters so the next sample's delta spans exactly the
        // new window, not a leftover one from the previous cadence / sleep gap.
        _ = sampler.sample()
        timer = Timer.publish(
            every: isLive ? liveInterval : idleInterval, on: .main, in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if widgetDebugRandom {
            perCore = (0..<Self.coreCount).map { _ in Double.random(in: 0...1) }
            return
        }
        guard let cores = sampler.sample() else { return }
        perCore = cores
    }
}
