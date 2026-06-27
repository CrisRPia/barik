import AppKit
import Combine

/// Single source of truth for "should the resource widgets be sampling right
/// now?". Resource managers subscribe to `isActive` and suspend their timers
/// when the menu bar isn't visible (occluded by a fullscreen app, or the
/// screen/system is asleep), then re-prime and resume when it comes back.
///
/// System sleep already suspends the whole process, so timers can't fire then;
/// the value still matters on *wake* so managers know to re-prime their delta
/// counters instead of emitting one giant sample spanning the gap.
@MainActor
final class SamplingGate: ObservableObject {
    static let shared = SamplingGate()

    @Published private(set) var isActive = true

    private var asleep = false

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self, selector: #selector(recompute),
            name: NSApplication.didChangeOcclusionStateNotification,
            object: nil)

        let ws = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ] {
            ws.addObserver(
                self, selector: #selector(didSleep), name: name, object: nil)
        }
        for name: NSNotification.Name in [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
        ] {
            ws.addObserver(
                self, selector: #selector(didWake), name: name, object: nil)
        }
        recompute()
    }

    @objc private func didSleep() {
        asleep = true
        recompute()
    }

    @objc private func didWake() {
        asleep = false
        recompute()
    }

    @objc private func recompute() {
        // Before the app finishes launching `occlusionState` may not be
        // meaningful; default to visible so sampling starts.
        let visible = NSApp?.occlusionState.contains(.visible) ?? true
        let active = visible && !asleep
        if active != isActive { isActive = active }
    }
}
