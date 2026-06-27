import SwiftUI

/// A world-clock widget: several time zones rendered as aligned columns, each
/// a dim label above a bold time.
///
/// Config (inline in `displayed`):
/// ```toml
/// { "default.clock-group" = { format = "H:mm", zones = [
///     { time-zone = "America/Guatemala", label = "HN" },
///     { time-zone = "GMT",               label = "GMT" },
///     { date-format = "d MMM" },  // local time, with the live date as caption
/// ] } }
/// ```
struct ClockGroupWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var format: String { config["format"]?.stringValue ?? "H:mm" }

    private struct Zone: Identifiable {
        let id: Int
        let timeZone: TimeZone
        /// Omitted/empty in config → the column is just the time, no label.
        let label: String?
        /// When set, the caption shows the live date in this pattern (in the
        /// zone's time zone) instead of the static `label`.
        let dateFormat: String?
    }

    private var zones: [Zone] {
        (config["zones"]?.arrayValue ?? []).enumerated().compactMap {
            index, entry in
            guard let dict = entry.dictionaryValue else { return nil }
            // Missing or unknown time-zone falls back to the local zone.
            let tz =
                dict["time-zone"]?.stringValue
                .flatMap(TimeZone.init(identifier:)) ?? .current
            let label = dict["label"]?.stringValue
            let dateFormat = dict["date-format"]?.stringValue
            return Zone(
                id: index, timeZone: tz, label: label, dateFormat: dateFormat)
        }
    }

    @ObservedObject private var ticker = ClockTicker.shared
    private var now: Date { ticker.now }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(zones) { zone in
                VStack(spacing: -1) {
                    if let caption = caption(for: zone) {
                        Text(caption)
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.55)
                    }
                    Text(time(in: zone.timeZone))
                        .fontWeight(.semibold)
                        .font(.headline)
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
    }

    private func time(in timeZone: TimeZone) -> String {
        TimeFormatterCache.formatter(pattern: format, timeZone: timeZone)
            .string(from: now)
    }

    /// The dim caption above the time: a live date if `date-format` is set,
    /// else the static label, else nothing.
    private func caption(for zone: Zone) -> String? {
        if let dateFormat = zone.dateFormat {
            return TimeFormatterCache.formatter(
                pattern: dateFormat, timeZone: zone.timeZone
            ).string(from: now)
        }
        if let label = zone.label, !label.isEmpty { return label }
        return nil
    }
}
