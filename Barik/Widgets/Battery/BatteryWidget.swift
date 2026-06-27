import SwiftUI

/// Battery as a grid of little squares that fill along a spiral (a circular
/// motion). Lit squares are near-white; the frontier square is a very subtle
/// green while charging / red while discharging, so the direction reads at a
/// glance without an eye-catching color. Click → battery popup.
struct BatteryWidget: View {
    @StateObject private var batteryManager = BatteryManager()
    @State private var rect = CGRect()

    private let cols = 10
    private let rows = 5
    private let cell: CGFloat = 2.2
    private let gap: CGFloat = 0.8

    private var total: Int { cols * rows }
    private var level: Int { batteryManager.batteryLevel }
    private var litCount: Int {
        Int((Double(level) / 100 * Double(total)).rounded())
    }
    /// Spiral rank (fill order) for each flat grid index, outer ring inward.
    private var rank: [Int] { Self.spiralRank(cols: cols, rows: rows) }

    private let softGreen = Color(red: 0.5, green: 0.85, blue: 0.55)
    private let softRed = Color(red: 0.92, green: 0.55, blue: 0.55)

    var body: some View {
        HStack(spacing: gap) {
            grid
            // Battery terminal nub.
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.foregroundOutside.opacity(0.5))
                .frame(width: 1.6, height: cell * 2)
        }
        .animation(.smooth(duration: 0.5), value: level)
        .animation(.smooth(duration: 0.5), value: batteryManager.isCharging)
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

    private var grid: some View {
        VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(color(forRank: rank[r * cols + c]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    private func color(forRank rank: Int) -> Color {
        guard rank < litCount else {
            return .foregroundOutside.opacity(0.15)
        }
        // Frontier (last-lit) square hints the direction, subtly.
        if rank == litCount - 1 {
            if batteryManager.isCharging { return softGreen }
            if !batteryManager.isPluggedIn { return softRed }
        }
        return .foregroundOutside
    }

    /// Maps each flat grid index to its position in a clockwise spiral that
    /// starts at the outer edge and works inward.
    private static func spiralRank(cols: Int, rows: Int) -> [Int] {
        var rank = [Int](repeating: 0, count: cols * rows)
        var top = 0, bottom = rows - 1, left = 0, right = cols - 1
        var order = 0
        func set(_ r: Int, _ c: Int) {
            rank[r * cols + c] = order
            order += 1
        }
        while top <= bottom, left <= right {
            for c in left...right { set(top, c) }
            top += 1
            if top <= bottom {
                for r in top...bottom { set(r, right) }
            }
            right -= 1
            if top <= bottom, left <= right {
                for c in stride(from: right, through: left, by: -1) {
                    set(bottom, c)
                }
                bottom -= 1
            }
            if left <= right, top <= bottom {
                for r in stride(from: bottom, through: top, by: -1) {
                    set(r, left)
                }
                left += 1
            }
        }
        return rank
    }
}
