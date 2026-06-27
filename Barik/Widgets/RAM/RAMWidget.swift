import SwiftUI

/// Memory usage as concentric rings (compact, glanceable, all near-white):
/// - outer ring = working-set fraction of physical RAM, with a small notch cut
///   at the high-usage threshold (fill crossing the notch = getting tight)
/// - inner ring = compressed fraction (rises as the system is squeezed)
/// Hover → live cadence, click → breakdown popup.
struct RAMWidget: View {
    @StateObject private var manager = RAMManager()
    @State private var rect = CGRect()

    private let size: CGFloat = 18
    private let lineWidth: CGFloat = 3
    /// Used-fraction the notch marks (no color change — just a reference cut).
    private let threshold: Double = 0.8

    var body: some View {
        ZStack {
            outerRing
            ring(
                fraction: compressedFraction,
                color: .foregroundOutside.opacity(0.6)
            )
            .padding(lineWidth + 1.5)
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.6), value: manager.snapshot)
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

    /// Outer ring with a notch punched at the threshold angle.
    private var outerRing: some View {
        ring(fraction: manager.snapshot.usedFraction, color: .foregroundOutside)
            .overlay(
                Rectangle()
                    .frame(width: 1.6, height: lineWidth + 3)
                    .offset(y: -(size - lineWidth) / 2)
                    .rotationEffect(.degrees(threshold * 360))
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
    }

    private func ring(fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(.foregroundOutside.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var compressedFraction: Double {
        guard manager.snapshot.total > 0 else { return 0 }
        return min(manager.snapshot.compressed / manager.snapshot.total, 1)
    }
}
