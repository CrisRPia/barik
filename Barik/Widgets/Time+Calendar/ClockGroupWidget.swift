import SwiftUI

/// A world-clock widget: several time zones rendered as aligned columns, each
/// a dim label above a bold time.
///
/// Config (inline in `displayed`):
/// ```toml
/// { "default.clock-group" = { format = "H:mm", zones = [
///     { time-zone = "America/Guatemala", label = "HN" },
///     { time-zone = "GMT",               label = "GMT" },
/// ] } }
/// ```
struct ClockGroupWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var format: String { config["format"]?.stringValue ?? "H:mm" }

    private struct Zone: Identifiable {
        let id: Int
        let timeZone: TimeZone
        let label: String
    }

    private var zones: [Zone] {
        (config["zones"]?.arrayValue ?? []).enumerated().compactMap {
            index, entry in
            guard let dict = entry.dictionaryValue else { return nil }
            // Missing or unknown time-zone falls back to the local zone.
            let tz =
                dict["time-zone"]?.stringValue
                .flatMap(TimeZone.init(identifier:)) ?? .current
            let label = dict["label"]?.stringValue ?? tz.identifier
            return Zone(id: index, timeZone: tz, label: label)
        }
    }

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            ForEach(zones) { zone in
                VStack(spacing: -1) {
                    Text(zone.label)
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.55)
                    Text(time(in: zone.timeZone))
                        .fontWeight(.semibold)
                        .font(.headline)
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .onReceive(timer) { now = $0 }
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
    }

    private func time(in timeZone: TimeZone) -> String {
        TimeFormatterCache.formatter(pattern: format, timeZone: timeZone)
            .string(from: now)
    }
}
