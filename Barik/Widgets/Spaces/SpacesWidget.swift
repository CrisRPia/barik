import SwiftUI

struct SpacesWidget: View {
    @StateObject var viewModel = SpacesViewModel()
    @Namespace private var windowNamespace

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat {
        configManager.config.experimental.foreground.resolveHeight()
    }

    var body: some View {
        HStack(spacing: foregroundHeight < 30 ? 0 : 8) {
            ForEach(viewModel.spaces) { space in
                SpaceView(space: space, windowNamespace: windowNamespace)
            }
        }
        // .experimentalConfiguration(horizontalPadding: 5, cornerRadius: 100)
        .animation(.smooth(duration: 0.3), value: viewModel.spaces)
        .environmentObject(viewModel)
        .background(.ultraThinMaterial)  // The "Frosted Glass"
        .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)  // The "Glass Edge"
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

/// This view shows a space with its windows.
private struct SpaceView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var spaceConfig: ConfigData { config["space"]?.dictionaryValue ?? [:] }

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat {
        configManager.config.experimental.foreground.resolveHeight()
    }

    var showKey: Bool { spaceConfig["show-key"]?.boolValue ?? true }

    let space: AnySpace

    @State var isHovered = false
    var windowNamespace: Namespace.ID

    var body: some View {
        let isFocused =
            space.windows.contains { $0.isFocused } || space.isFocused
        let hasWindows = !space.windows.isEmpty
        HStack(spacing: 0) {
            // Vertical highlight marks the focused (or hovered) space —
            // replaces the old rounded pill so spaces pack tighter.
            Capsule()
                .fill(.white)
                .opacity(isFocused ? 0.8 : (isHovered ? 0.3 : 0))
                .frame(width: 2.5, height: 16)
            Spacer().frame(width: 6)
            if showKey {
                Text(space.id)
                    .font(.headline)
                    .frame(minWidth: 15)
                    .fixedSize(horizontal: true, vertical: false)
                if hasWindows {
                    Spacer().frame(width: 5)
                }
            }
            // Windows overlap into a compact stack; the focused space fans
            // them out to full spacing so each is visible and clickable.
            HStack(spacing: isFocused ? 2 : -13) {
                ForEach(Array(space.windows.enumerated()), id: \.element.id) {
                    offset, window in
                    WindowView(
                        window: window,
                        space: space,
                        windowNamespace: windowNamespace,
                        isStacked: !isFocused
                    )
                    .zIndex(Double(space.windows.count - offset))
                }
            }
            Spacer().frame(width: 6)
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .transition(.blurReplace)
        .onTapGesture {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        .animation(.smooth, value: isHovered)
        .onHover { value in
            isHovered = value
        }
    }
}

/// This view shows a window and its icon.
private struct WindowView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var windowConfig: ConfigData { config["window"]?.dictionaryValue ?? [:] }
    var titleConfig: ConfigData {
        windowConfig["title"]?.dictionaryValue ?? [:]
    }

    var showTitle: Bool { windowConfig["show-title"]?.boolValue ?? true }
    var maxLength: Int { titleConfig["max-length"]?.intValue ?? 50 }
    var alwaysDisplayAppTitleFor: [String] {
        titleConfig["always-display-app-name-for"]?.arrayValue?.filter({
            $0.stringValue != nil
        }).map { $0.stringValue! } ?? []
    }

    let window: AnyWindow
    let space: AnySpace
    var windowNamespace: Namespace.ID
    /// True when this window is part of an overlapping (non-focused) stack.
    /// Drives a directional shadow so the stack reads as layered cards.
    var isStacked: Bool = false

    @State var isHovered = false

    var body: some View {
        let titleMaxLength = maxLength
        let size: CGFloat = 21
        let sameAppCount = space.windows.filter { $0.appName == window.appName }
            .count
        let title =
            sameAppCount > 1
                && !alwaysDisplayAppTitleFor.contains { $0 == window.appName }
            ? window.title : (window.appName ?? "")
        // The window this space would focus into (actually-focused for the
        // active space, MRU for inactive ones). It stays full-opacity while
        // the rest of the stack dims back.
        let isPrimary =
            space.emphasizedWindowID == nil
            || window.id == space.emphasizedWindowID
        HStack {
            ZStack {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .matchedGeometryEffect(
                            id: window.id,
                            in: windowNamespace
                        )
                        .frame(width: size, height: size)
                        .shadow(
                            color: .black.opacity(isStacked ? 0.5 : 0.2),
                            radius: isStacked ? 2.5 : 3,
                            x: isStacked ? 3 : 0,
                            y: isStacked ? 1 : 1
                        )
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            // Dim non-primary windows by darkening (not opacity) so stacked
            // icons stay solid and don't bleed through one another.
            .colorMultiply(isPrimary ? .white : Color(white: 0.6))
            .transition(.blurReplace)

            if window.isFocused, !title.isEmpty, showTitle {
                HStack {
                    Text(
                        title.count > titleMaxLength
                            ? String(title.prefix(titleMaxLength)) + "..."
                            : title
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .shadow(color: .foregroundShadow, radius: 3)
                    .fontWeight(.semibold)
                    Spacer().frame(width: 5)
                }
                .transition(.blurReplace)
            }
        }
        .padding(.all, 2)
        .background(
            isHovered || (!showTitle && window.isFocused) ? .selected : .clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.smooth, value: isHovered)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.switchToSpace(space)
            usleep(100_000)
            viewModel.switchToWindow(window)
        }
        .onHover { value in
            isHovered = value
        }
    }
}
