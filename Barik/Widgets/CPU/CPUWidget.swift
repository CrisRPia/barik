import SwiftUI

/// System CPU usage: one little bar per logical core, height = that core's
/// current usage. Bars refresh as a batch every ~10s and animate to the new
/// values (calm, not a constantly-shifting sparkline); hovering switches to a
/// faster, closer-to-realtime cadence. Click opens a larger graph.
struct CPUWidget: View {
    @StateObject private var manager = CPUManager()
    @State private var rect = CGRect()

    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 1.5
    private let chartHeight: CGFloat = 14

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(Array(manager.perCore.enumerated()), id: \.offset) {
                _, value in
                Capsule()
                    .frame(
                        width: barWidth,
                        height: max(2, CGFloat(value) * chartHeight))
            }
        }
        .frame(height: chartHeight)
        .animation(.smooth(duration: 0.6), value: manager.perCore)
        .foregroundStyle(.foregroundOutside)
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
        .onHover { manager.setLive($0) }
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "resources") {
                ResourceDashboardPopup()
            }
        }
    }
}

struct CPUWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack { CPUWidget() }
            .frame(width: 200, height: 100)
            .background(.blue)
            .environmentObject(ConfigProvider(config: [:]))
    }
}
