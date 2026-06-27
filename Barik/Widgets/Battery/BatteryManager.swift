import Combine
import Foundation
import IOKit
import IOKit.ps

private let powerPollInterval: TimeInterval = 30

class BatteryManager: ObservableObject {
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    /// Instantaneous power flow in watts: positive = charging, negative =
    /// discharging. Read from AppleSmartBattery; polled (level changes are
    /// event-driven, but power varies continuously with load).
    @Published var powerWatts: Double = 0
    /// Low Power Mode ("battery saver") state.
    @Published var isLowPowerMode = ProcessInfo.processInfo
        .isLowPowerModeEnabled

    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?

    private var randomTimer: Timer?
    private var powerTimer: Timer?
    private var gate: AnyCancellable?

    init() {
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode =
                ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        if widgetDebugRandom {
            startRandom()
        } else {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
        randomTimer?.invalidate()
        powerTimer?.invalidate()
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
    }

    private func startRandom() {
        randomize()
        randomTimer = Timer.scheduledTimer(
            withTimeInterval: 1.5, repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.randomize() }
        }
    }

    private func randomize() {
        batteryLevel = Int.random(in: 0...100)
        isCharging = Bool.random()
        isPluggedIn = isCharging || Bool.random()
        // A signed, roughly log-distributed wattage for visual testing.
        let magnitude = pow(10, Double.random(in: -0.3...1.8))  // ~0.5W–60W
        powerWatts = isCharging ? magnitude : -magnitude
        isLowPowerMode = Bool.random()
    }

    private func startMonitoring() {
        updateBatteryStatus()

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
            manager.updateBatteryStatus()
        }

        // Refresh the rate gauge on a slow cadence for steady-state drift (the
        // IOPS callback already covers plug/unplug instantly). Gated, so it
        // stops when the menu bar is hidden or the machine is asleep.
        // SamplingGate is main-actor isolated and this runs from init on the
        // main thread, so bridge the isolation explicitly.
        MainActor.assumeIsolated {
            gate = SamplingGate.shared.$isActive.sink { [weak self] active in
                self?.setPowerPolling(active)
            }
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue()
        {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }

    func updateBatteryStatus() {
        // Fired by the IOPS notification on any power-source change (incl.
        // plug/unplug) — refresh the rate too so the cap responds at once.
        updatePower()
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(
                snapshot, source)?.takeUnretainedValue() as? [String: Any],
                let currentCapacity = description[
                    kIOPSCurrentCapacityKey as String] as? Int,
                let maxCapacity = description[kIOPSMaxCapacityKey as String]
                    as? Int,
                let charging = description[kIOPSIsChargingKey as String]
                    as? Bool,
                let powerSourceState = description[
                    kIOPSPowerSourceStateKey as String] as? String
            {
                let isAC = (powerSourceState == kIOPSACPowerValue)

                DispatchQueue.main.async {
                    self.batteryLevel = (currentCapacity * 100) / maxCapacity
                    self.isCharging = charging
                    self.isPluggedIn = isAC
                }
            }
        }
    }

    private func setPowerPolling(_ active: Bool) {
        powerTimer?.invalidate()
        powerTimer = nil
        guard active else { return }
        updatePower()  // refresh immediately on resume
        powerTimer = Timer.scheduledTimer(
            withTimeInterval: powerPollInterval, repeats: true
        ) { [weak self] _ in
            self?.updatePower()
        }
    }

    private func updatePower() {
        let watts = Self.readPowerWatts()
        DispatchQueue.main.async { self.powerWatts = watts }
    }

    /// Reads instantaneous power from AppleSmartBattery: amperage (mA, signed)
    /// × voltage (mV) → watts. Returns 0 if the service/keys are unavailable.
    private static func readPowerWatts() -> Double {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }

        func intProp(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
        }
        guard let rawAmperage = intProp("Amperage"),
            let voltage = intProp("Voltage")
        else { return 0 }

        // Amperage is signed but reported as an unsigned 64-bit value; fold
        // the high half back to negative (discharging).
        var amperage = rawAmperage
        if amperage > Int(Int32.max) { amperage -= 1 << 32 }

        return Double(amperage) * Double(voltage) / 1_000_000
    }
}
