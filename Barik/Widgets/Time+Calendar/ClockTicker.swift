import Combine
import Foundation

/// Shared clock source for the time widgets. Ticks once per wall-clock minute
/// (the clocks only show `H:mm` / dates, so a per-second timer was 60× more
/// wakeups than needed) and pauses with `SamplingGate`, so a hidden or asleep
/// menu bar costs nothing.
///
/// Note: minute resolution means a `ss`-seconds format would not update live —
/// the widgets here don't use one.
@MainActor
final class ClockTicker: ObservableObject {
    static let shared = ClockTicker()

    @Published private(set) var now = Date()

    private var timer: Timer?
    private var gate: AnyCancellable?

    private init() {
        gate = SamplingGate.shared.$isActive.sink { [weak self] active in
            active ? self?.resume() : self?.suspend()
        }
    }

    private func resume() {
        now = Date()  // catch up on whatever time passed while paused
        scheduleNextMinute()
    }

    private func suspend() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNextMinute() {
        timer?.invalidate()
        let next =
            Calendar.current.nextDate(
                after: Date(), matching: DateComponents(second: 0),
                matchingPolicy: .nextTime) ?? Date().addingTimeInterval(60)
        let t = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        t.tolerance = 2  // let the OS coalesce the wakeup
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
