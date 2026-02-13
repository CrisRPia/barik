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
            Spacer().frame(width: 10)
            if showKey {
                Text(space.id)
                    .font(.headline)
                    .frame(minWidth: 15)
                    .fixedSize(horizontal: true, vertical: false)
                if hasWindows {
                    Spacer().frame(width: 5)
                }
            }
            HStack(spacing: 2) {
                ForEach(space.windows) { window in
                    WindowView(
                        window: window,
                        space: space,
                        windowNamespace: windowNamespace
                    )
                }
            }
            Spacer().frame(width: 10)
        }
        .frame(height: 30)
        .background(
            ZStack {
                if isFocused {
                    RoundedRectangle(cornerRadius: 100, style: .continuous)
                        .fill(.white)
                        .opacity(0.2)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 100, style: .continuous)
                        .fill(.white)
                        .opacity(0.1)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(isFocused ? 0.3 : 0),
                            .white.opacity(isFocused ? 0.1 : 0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )  // This ensures the first and last spaces align perfectly with the widget's edges.
        .clipShape(
            RoundedRectangle(
                cornerRadius: foregroundHeight < 30 ? 0 : 100,
                style: .continuous
            )
        )
        .shadow(color: .shadow, radius: foregroundHeight < 30 ? 0 : 2)
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
        let spaceIsFocused = space.windows.contains { $0.isFocused }
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
                            color: .black.opacity(0.2),
                            radius: 3,
                            x: 0,
                            y: 1
                        )
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            .opacity(spaceIsFocused && !window.isFocused ? 0.5 : 1)
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
