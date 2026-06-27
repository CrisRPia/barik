import Charts
import SwiftUI

/// Unified resource dashboard shown when any widget in the resource group is
/// clicked: CPU, memory, network and battery, each with labelled axes, scales,
/// and a hover read-out so the numbers are explicit.
struct ResourceDashboardPopup: View {
    @StateObject private var cpu = CPUManager(idleInterval: 1, liveInterval: 1)
    @StateObject private var ram = RAMManager(idleInterval: 1, liveInterval: 1)
    @ObservedObject private var net = NetworkManager.shared
    @StateObject private var battery = BatteryManager()

    @State private var cpuHover: Int?
    @State private var netHover: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            cpuSection
            Divider()
            ramSection
            Divider()
            networkSection
            Divider()
            batterySection
        }
        .frame(width: 340)
        .padding(24)
    }

    // MARK: CPU

    private var cpuSection: some View {
        let cores = cpu.perCore
        let avg = cores.isEmpty ? 0 : cores.reduce(0, +) / Double(cores.count)
        return VStack(alignment: .leading, spacing: 8) {
            header(
                "CPU", icon: "cpu",
                trailing: cpuHover.flatMap { h in
                    h < cores.count ? "core \(h) · \(Self.pct(cores[h]))" : nil
                } ?? "avg \(Self.pct(avg))")

            Chart {
                ForEach(Array(cores.enumerated()), id: \.offset) { idx, v in
                    BarMark(
                        x: .value("Core", idx), y: .value("Usage", v * 100))
                    .foregroundStyle(
                        .white.opacity(cpuHover == idx ? 1 : 0.7))
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Int.self) { Text("\(d)%") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: Array(0..<max(cores.count, 1))) { value in
                    AxisValueLabel {
                        if let d = value.as(Int.self) { Text("\(d)") }
                    }
                }
            }
            .frame(height: 90)
            .chartOverlay { proxy in
                hoverCatcher(proxy) { x in
                    cpuHover = proxy.value(atX: x, as: Int.self).map {
                        min(max($0, 0), cores.count - 1)
                    }
                } onEnd: { cpuHover = nil }
            }
        }
    }

    // MARK: Memory

    private var ramSection: some View {
        let s = ram.snapshot
        let segs: [(String, Double, Color)] = [
            ("Wired", s.wired, .blue),
            ("Active", s.active, .green),
            ("Compressed", s.compressed, .orange),
            ("Available", s.available, .gray),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            header(
                "Memory", icon: "memorychip",
                trailing: "\(Self.bytes(s.wired + s.active + s.compressed)) / "
                    + Self.bytes(s.total))

            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segs, id: \.0) { seg in
                        seg.2.frame(
                            width: s.total > 0
                                ? geo.size.width * (seg.1 / s.total) : 0)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .animation(.smooth(duration: 0.4), value: s)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(segs, id: \.0) { seg in
                    legendRow(seg.2, seg.0, seg.1)
                }
                if s.swapUsed > 0 {
                    legendRow(.red.opacity(0.7), "Swap", s.swapUsed)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
        }
    }

    // MARK: Network

    private var networkSection: some View {
        let history = net.history
        let count = history.count
        return VStack(alignment: .leading, spacing: 8) {
            header(
                "Network", icon: "network",
                trailing: netReadout(history: history, count: count))

            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { i, s in
                    AreaMark(
                        x: .value("t", i),
                        yStart: .value("z", 0),
                        yEnd: .value("down", s.down)
                    )
                    .foregroundStyle(.green.opacity(0.7))
                    AreaMark(
                        x: .value("t", i),
                        yStart: .value("z", 0),
                        yEnd: .value("up", -s.up)
                    )
                    .foregroundStyle(.blue.opacity(0.7))
                }
                if let h = netHover, h < count {
                    RuleMark(x: .value("t", h))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(Self.rate(abs(d)))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, count / 2, count - 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let i = value.as(Int.self) {
                            Text(i == count - 1 ? "now" : "\(count - 1 - i)s")
                        }
                    }
                }
            }
            .frame(height: 90)
            .chartOverlay { proxy in
                hoverCatcher(proxy) { x in
                    netHover = proxy.value(atX: x, as: Int.self).map {
                        min(max($0, 0), count - 1)
                    }
                } onEnd: { netHover = nil }
            }

            HStack(spacing: 16) {
                Label("download", systemImage: "square.fill")
                    .foregroundStyle(.green)
                Label("upload", systemImage: "square.fill")
                    .foregroundStyle(.blue)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    private func netReadout(history: [NetSample], count: Int) -> String {
        let sample: NetSample
        let prefix: String
        if let h = netHover, h < count {
            sample = history[h]
            prefix = "\(count - 1 - h)s · "
        } else {
            sample = net.current
            prefix = ""
        }
        return prefix + "↓ \(Self.rate(sample.down))  ↑ \(Self.rate(sample.up))"
    }

    // MARK: Battery

    private var batterySection: some View {
        let level = battery.batteryLevel
        let watts = battery.powerWatts
        return VStack(alignment: .leading, spacing: 8) {
            header("Battery", icon: "battery.100", trailing: "\(level)%")
            ProgressView(value: Double(level), total: 100)
                .tint(.white)
            HStack {
                Text(batteryState)
                if abs(watts) >= 0.05 {
                    Text("· \(Self.power(watts))")
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var batteryState: String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return "Plugged in" }
        return "On battery"
    }

    private static func power(_ watts: Double) -> String {
        let arrow = watts >= 0 ? "↑" : "↓"
        return String(format: "%@ %.1f W", arrow, abs(watts))
    }

    // MARK: Helpers

    private func header(_ title: String, icon: String, trailing: String)
        -> some View
    {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(trailing).foregroundStyle(.secondary)
        }
        .font(.headline)
        .monospacedDigit()
    }

    private func legendRow(_ color: Color, _ label: String, _ bytes: Double)
        -> some View
    {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
            Spacer(minLength: 24)
            Text(Self.bytes(bytes)).foregroundStyle(.secondary)
        }
    }

    /// A transparent catcher over the chart's plot area that maps a hover
    /// location to a chart x-position.
    @ViewBuilder
    private func hoverCatcher(
        _ proxy: ChartProxy,
        onMove: @escaping (CGFloat) -> Void,
        onEnd: @escaping () -> Void
    ) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if let frame = proxy.plotFrame {
                            onMove(point.x - geo[frame].origin.x)
                        }
                    case .ended:
                        onEnd()
                    }
                }
        }
    }

    // MARK: Formatters

    private static func pct(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        return f
    }()

    private static let rateFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .memory
        return f
    }()

    static func bytes(_ value: Double) -> String {
        byteFormatter.string(fromByteCount: Int64(value))
    }

    static func rate(_ bytesPerSec: Double) -> String {
        rateFormatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}
