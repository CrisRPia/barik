import SwiftUI

/// A filled sparkline of normalized (0...1) values, anchored to one edge.
/// Plain (non-morphing) shape — motion comes from translating it, not from
/// interpolating point heights in place (which reads as bumpy).
struct Sparkline: Shape {
    /// Oldest first, each 0...1.
    var values: [Double]
    /// The edge that represents zero; the area grows toward the opposite edge.
    var baseline: VerticalEdge

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let stepX = rect.width / CGFloat(values.count - 1)
        let base = baseline == .bottom ? rect.maxY : rect.minY
        func y(_ v: Double) -> CGFloat {
            let clamped = CGFloat(min(max(v, 0), 1))
            return baseline == .bottom
                ? rect.maxY - clamped * rect.height
                : rect.minY + clamped * rect.height
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: base))
        for (i, v) in values.enumerated() {
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(i) * stepX, y: y(v)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: base))
        path.closeSubpath()
        return path
    }
}

/// Mirrored throughput chart: download grows up from the centre line, upload
/// down. New samples enter at the right and the whole waveform slides left by
/// exactly one sample-step each tick (a true scroll, not a height morph).
struct MirroredThroughputChart: View {
    /// Normalized (0...1), oldest first.
    let down: [Double]
    let up: [Double]
    let width: CGFloat
    let halfHeight: CGFloat
    let downColor: Color
    let upColor: Color
    let interval: TimeInterval

    @State private var slide: CGFloat = 0

    private var stepX: CGFloat {
        down.count > 1 ? width / CGFloat(down.count - 1) : 0
    }

    var body: some View {
        VStack(spacing: 1) {
            Sparkline(values: down, baseline: .bottom)
                .fill(downColor)
                .frame(height: halfHeight)
            Sparkline(values: up, baseline: .top)
                .fill(upColor)
                .frame(height: halfHeight)
        }
        .frame(width: width)
        // Slide trick: when a new sample lands, jump right by one step (which
        // reproduces the previous frame's look) then animate back to 0 — so the
        // line scrolls left continuously and the new point eases in from the
        // right, instead of every point jumping a notch.
        .offset(x: slide)
        .frame(width: width, alignment: .leading)
        .clipped()
        .overlay(
            Rectangle()
                .fill(.foregroundOutside.opacity(0.3))
                .frame(height: 1)
        )
        .onChange(of: down) { _, _ in
            slide = stepX
            withAnimation(.linear(duration: interval)) { slide = 0 }
        }
    }
}

/// Network throughput widget: a compact mirrored sparkline. Auto-scaled to the
/// window's peak. Click → popup (shares the same continuous history).
struct NetworkWidget: View {
    @ObservedObject private var manager = NetworkManager.shared
    @State private var rect = CGRect()

    private let chartWidth: CGFloat = 42
    private let halfHeight: CGFloat = 8
    /// How many recent seconds the menu-bar chart shows (the popup shows more).
    private let window = 30

    /// Floor so an idle network reads as a flat line, not amplified noise.
    private var scale: Double { max(manager.peak, 64 * 1024) }

    var body: some View {
        MirroredThroughputChart(
            down: normalized(\.down),
            up: normalized(\.up),
            width: chartWidth,
            halfHeight: halfHeight,
            downColor: .foregroundOutside,
            upColor: .foregroundOutside.opacity(0.5),
            interval: 1
        )
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

    private func normalized(_ key: KeyPath<NetSample, Double>) -> [Double] {
        manager.history.suffix(window).map { $0[keyPath: key] / scale }
    }
}
