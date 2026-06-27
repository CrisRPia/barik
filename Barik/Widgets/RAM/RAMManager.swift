import Combine
import Darwin
import Foundation

/// A point-in-time memory reading.
struct MemorySnapshot: Equatable {
    var total: Double = 0
    var wired: Double = 0
    var active: Double = 0
    var compressed: Double = 0
    /// Reclaimable (free + inactive + speculative + purgeable).
    var available: Double = 0
    var swapUsed: Double = 0
    /// macOS VM pressure level: 1 normal, 2 warning, 4 critical.
    var pressureLevel: Int = 1

    /// Working-set fraction of physical RAM (wired + active + compressed).
    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max((wired + active + compressed) / total, 0), 1)
    }
}

/// Publishes memory usage + pressure. Slow cadence by default, fast on hover —
/// memory is stateless to read, so each sample is independent (no priming).
@MainActor
final class RAMManager: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot()

    private let idleInterval: TimeInterval
    private let liveInterval: TimeInterval
    private var timer: AnyCancellable?
    private var gate: AnyCancellable?
    private var isLive = false
    private var gateActive = true

    init(idleInterval: TimeInterval = 10, liveInterval: TimeInterval = 1) {
        self.idleInterval = idleInterval
        self.liveInterval = liveInterval
        tick()  // immediate first draw
        // @Published replays the current value, so this also starts the timer.
        gate = SamplingGate.shared.$isActive.sink { [weak self] active in
            self?.gateActive = active
            self?.restart()
        }
    }

    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        restart()
    }

    private func restart() {
        timer = nil
        guard gateActive else { return }
        // Memory is stateless to read, so no priming needed; debug refreshes
        // fast enough to watch without hovering.
        let interval =
            widgetDebugRandom ? 2 : (isLive ? liveInterval : idleInterval)
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if widgetDebugRandom {
            snapshot = Self.randomSnapshot()
            return
        }
        guard let s = Self.read() else { return }
        snapshot = s
    }

    private static func randomSnapshot() -> MemorySnapshot {
        let total = 8.0 * 1024 * 1024 * 1024
        let used = Double.random(in: 0.2...0.97)
        var s = MemorySnapshot()
        s.total = total
        s.wired = total * used * 0.35
        s.active = total * used * 0.5
        s.compressed = total * used * 0.15
        s.available = total * (1 - used)
        s.swapUsed = Double.random(in: 0...2) * 1024 * 1024 * 1024
        s.pressureLevel = [1, 1, 2, 4].randomElement()!
        return s
    }

    private static func read() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride
                / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = Double(vm_kernel_page_size)
        var s = MemorySnapshot()
        s.total = Double(ProcessInfo.processInfo.physicalMemory)
        s.wired = Double(stats.wire_count) * page
        s.active = Double(stats.active_count) * page
        s.compressed = Double(stats.compressor_page_count) * page
        s.available =
            Double(
                stats.free_count + stats.inactive_count
                    + stats.speculative_count + stats.purgeable_count) * page
        s.swapUsed = swapUsed()
        s.pressureLevel = pressureLevel()
        return s
    }

    private static func pressureLevel() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname(
            "kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return Int(level)
    }

    private static func swapUsed() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return 0
        }
        return Double(usage.xsu_used)
    }
}
