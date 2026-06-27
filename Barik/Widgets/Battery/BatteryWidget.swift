import SwiftUI

/// Battery drawn like a classic icon: a rounded body that fills left→right with
/// the charge level (near-white over a dimmer empty track), tick notches along
/// the top and bottom edges (small every 10%, larger every 30%), and a small
/// terminal nub on the right.
///
/// The nub doubles as a coarse charge/discharge-*rate* gauge: it fills on a log
/// wattage scale, top→bottom while charging and bottom→top while discharging,
/// and goes solid once topped up on AC. Click → the resource dashboard.
struct BatteryWidget: View {
    @StateObject private var batteryManager = BatteryManager()
    @State private var rect = CGRect()

    private let bodyWidth: CGFloat = 34
    private let bodyHeight: CGFloat = 13
    private let bodyRadius: CGFloat = 3

    private let nubWidth: CGFloat = 2.8
    private let nubHeight: CGFloat = 6

    /// Full-height reference gridlines, as fractions of capacity.
    private let markerFractions: [CGFloat] = [1.0 / 3, 2.0 / 3]
    private let markerWidth: CGFloat = 1
    private let markerColor = Color(red: 0.52, green: 0.58, blue: 0.72)

    /// Charge level (inclusive) below which the fill turns red.
    private let lowLevel = 10
    private let lowColor = Color(red: 0.92, green: 0.36, blue: 0.36)
    private let saverColor = Color(red: 0.95, green: 0.8, blue: 0.35)

    /// Opacity of the empty body track / empty nub — "how empty" is useful info.
    private let emptyOpacity: Double = 0.3
    /// Wattage range the nub gauge spans (log scale).
    private let wattMin = 0.5
    private let wattMax = 80.0

    private var level: Int { batteryManager.batteryLevel }

    var body: some View {
        HStack(spacing: 1.5) {
            body_
            nub
        }
        .animation(.smooth(duration: 0.5), value: level)
        .animation(.smooth(duration: 0.5), value: batteryManager.isCharging)
        .animation(.smooth(duration: 0.5), value: batteryManager.powerWatts)
        .animation(.smooth(duration: 0.5), value: batteryManager.isLowPowerMode)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, new in
                        rect = new
                    }
            }
        )
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "resources") {
                ResourceDashboardPopup()
            }
        }
    }

    private var body_: some View {
        RoundedRectangle(cornerRadius: bodyRadius)
            .fill(.foregroundOutside.opacity(emptyOpacity))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(fillColor)
                    .frame(width: bodyWidth * levelFraction)
            }
            .overlay { markers }
            .clipShape(RoundedRectangle(cornerRadius: bodyRadius))
            .frame(width: bodyWidth, height: bodyHeight)
    }

    /// Subtle full-height reference lines at 1/10, 1/3 and 2/3.
    private var markers: some View {
        ForEach(markerFractions, id: \.self) { f in
            Rectangle()
                .fill(markerColor)
                .frame(width: markerWidth)
                .position(x: bodyWidth * f, y: bodyHeight / 2)
        }
    }

    /// Short terminal nub that fills by charge/discharge rate.
    private var nub: some View {
        let charging = batteryManager.isCharging
        return ZStack(alignment: charging ? .top : .bottom) {
            RoundedRectangle(cornerRadius: 0.8)
                .fill(.foregroundOutside.opacity(emptyOpacity))
            RoundedRectangle(cornerRadius: 0.8)
                .fill(.foregroundOutside)
                .frame(height: nubHeight * capFraction)
        }
        .frame(width: nubWidth, height: nubHeight)
    }

    private var levelFraction: CGFloat {
        min(max(CGFloat(level) / 100, 0), 1)
    }

    /// Red when critically low, yellow in Low Power Mode, else near-white.
    private var fillColor: Color {
        if level <= lowLevel { return lowColor }
        if batteryManager.isLowPowerMode { return saverColor }
        return .foregroundOutside
    }

    /// Power magnitude mapped onto a log scale so small draws are still visible.
    /// Solid only when topped up on AC (full + plugged); a full battery that's
    /// discharging still shows its rate.
    private var capFraction: CGFloat {
        if level >= 100 && batteryManager.isPluggedIn { return 1 }
        let w = abs(batteryManager.powerWatts)
        guard w > wattMin else { return 0 }
        let lo = log10(wattMin)
        let f = (log10(min(w, wattMax)) - lo) / (log10(wattMax) - lo)
        return CGFloat(min(max(f, 0), 1))
    }
}
