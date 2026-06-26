import SwiftUI

struct TimeWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var format: String { config["format"]?.stringValue ?? "E d, J:mm" }
    var timeZone: String? { config["time-zone"]?.stringValue }

    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        Text(formattedTime(pattern: format, from: currentTime))
            .fontWeight(.semibold)
            .font(.headline)
            .foregroundStyle(.foregroundOutside)
            .shadow(color: .foregroundShadowOutside, radius: 3)
            .onReceive(timer) { date in
                currentTime = date
            }
            .experimentalConfiguration(cornerRadius: 15)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .monospacedDigit()
    }

    // Format the current time. Formatters are cached by pattern + time zone:
    // the clock re-renders every second and `DateFormatter` is expensive to
    // allocate.
    private func formattedTime(pattern: String, from time: Date) -> String {
        let tz = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return TimeFormatterCache.formatter(pattern: pattern, timeZone: tz)
            .string(from: time)
    }
}

/// Main-thread-only cache of `DateFormatter`s keyed by pattern + time zone.
enum TimeFormatterCache {
    static var formatters: [String: DateFormatter] = [:]

    static func formatter(pattern: String, timeZone: TimeZone) -> DateFormatter {
        let key = "\(pattern)|\(timeZone.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        formatter.timeZone = timeZone
        formatters[key] = formatter
        return formatter
    }
}

struct TimeWidget_Previews: PreviewProvider {
    static var previews: some View {
        let provider = ConfigProvider(config: ConfigData())

        ZStack {
            TimeWidget()
                .environmentObject(provider)
        }.frame(width: 500, height: 100)
    }
}
