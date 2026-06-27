import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let items = configManager.config.rootToml.widgets.displayed

        HStack(spacing: 0) {
            HStack(spacing: configManager.config.experimental.foreground.spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    let item = items[index]
                    buildEntry(for: item)
                }
            }

            if !items.contains(where: { $0.id == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, configManager.config.experimental.foreground.horizontalPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
    }

    /// Renders a top-level entry, which is either a single widget or a group
    /// (a nested array). A group draws one shared background pill and lays its
    /// members out tightly; members skip their own pill via the environment.
    ///
    /// `AnyView` erases the recursive call so this function's opaque return
    /// type isn't self-referential.
    @ViewBuilder
    private func buildEntry(for item: TomlWidgetItem) -> some View {
        if let children = item.children {
            HStack(spacing: 8) {
                ForEach(0..<children.count, id: \.self) { index in
                    AnyView(
                        buildEntry(for: children[index])
                            .environment(\.insideWidgetGroup, true)
                    )
                }
            }
            .experimentalConfiguration(cornerRadius: 15)
        } else {
            buildWidget(for: item)
        }
    }

    @ViewBuilder
    private func buildWidget(for item: TomlWidgetItem) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.spaces":
            SpacesWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.cpu":
            CPUWidget().environmentObject(config)

        case "default.ram":
            RAMWidget().environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.time":
            TimeWidget().environmentObject(config)

        case "default.clock-group":
            ClockGroupWidget().environmentObject(config)

        case "spacer":
            Spacer().frame(minWidth: 50, maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color.active)
                .frame(width: 2, height: 15)
                .clipShape(Capsule())

        case "system-banner":
            SystemBannerWidget()

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }
}
