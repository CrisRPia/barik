import SwiftUI

/// True for widgets rendered inside a widget group. Grouped widgets skip their
/// own background pill so the group can draw a single shared one.
private struct InsideWidgetGroupKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var insideWidgetGroup: Bool {
        get { self[InsideWidgetGroupKey.self] }
        set { self[InsideWidgetGroupKey.self] = newValue }
    }
}

private struct ExperimentalConfigurationModifier: ViewModifier {
    @ObservedObject var configManager = ConfigManager.shared
    @Environment(\.insideWidgetGroup) private var insideWidgetGroup
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if insideWidgetGroup {
            // The enclosing group draws the shared pill; stay bare.
            content
        } else {
            Group {
                if !configManager.config.experimental.foreground.widgetsBackground.displayed {
                    content
                } else {
                    content
                        .frame(height: foregroundHeight < 45 ? 30 : 38)
                        .padding(.horizontal, foregroundHeight < 45 && horizontalPadding != 15 ? 0 :
                                    foregroundHeight < 30 ? 0 : horizontalPadding
                        )
                        // Real Liquid Glass replaces the old blur + stroke pill.
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(
                                cornerRadius: foregroundHeight < 30 ? 0 : cornerRadius,
                                style: .continuous
                            )
                        )
                }
            }.scaleEffect(foregroundHeight < 25 ? 0.9 : 1, anchor: .leading)
        }
    }
}

extension View {
    func experimentalConfiguration(
        horizontalPadding: CGFloat = 15,
        cornerRadius: CGFloat
    ) -> some View {
        self.modifier(ExperimentalConfigurationModifier(
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius
        ))
    }
}
