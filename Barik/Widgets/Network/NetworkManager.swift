import Combine
import Darwin
import Foundation

/// Download/upload throughput at one instant, in bytes/sec.
struct NetSample: Equatable {
    var down: Double = 0
    var up: Double = 0
}

/// Publishes a rolling window of network throughput. Sampled at a fixed cadence
/// (even spacing matters for a time sparkline) by diffing interface byte
/// counters across all active non-loopback interfaces.
@MainActor
final class NetworkManager: ObservableObject {
    /// Shared, always-running instance so history accumulates continuously —
    /// the popup can show samples gathered before it opened.
    static let shared = NetworkManager(capacity: 60, interval: 1)

    /// Recent throughput samples, oldest first, capped at `capacity`.
    @Published private(set) var history: [NetSample]

    let capacity: Int
    private let interval: TimeInterval
    private var previous: (rx: UInt64, tx: UInt64)?
    private var timer: AnyCancellable?

    init(capacity: Int = 30, interval: TimeInterval = 1) {
        self.capacity = capacity
        self.interval = interval
        // Seed with a flat baseline so the sparkline draws immediately.
        history = Array(repeating: NetSample(), count: capacity)
        previous = Self.readCounters()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    var current: NetSample { history.last ?? NetSample() }

    /// Largest throughput in the window (either direction), for auto-scaling.
    var peak: Double {
        history.reduce(0) { max($0, max($1.down, $1.up)) }
    }

    private func tick() {
        guard let now = Self.readCounters() else { return }
        defer { previous = now }
        guard let prev = previous else { return }
        // Counters are cumulative; clamp on wrap/reset.
        let down = now.rx >= prev.rx ? Double(now.rx - prev.rx) : 0
        let up = now.tx >= prev.tx ? Double(now.tx - prev.tx) : 0
        history.append(NetSample(down: down / interval, up: up / interval))
        if history.count > capacity {
            history.removeFirst(history.count - capacity)
        }
    }

    private static func readCounters() -> (rx: UInt64, tx: UInt64)? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let ifa = cur.pointee
            let flags = Int32(ifa.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                let raw = ifa.ifa_data
            {
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(data.ifi_ibytes)
                tx += UInt64(data.ifi_obytes)
            }
            ptr = ifa.ifa_next
        }
        return (rx, tx)
    }
}
