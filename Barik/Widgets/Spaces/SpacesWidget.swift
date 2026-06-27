import SwiftUI

struct SpacesWidget: View {
    @StateObject var viewModel = SpacesViewModel()
    @Namespace private var windowNamespace
    @Namespace private var highlightNamespace

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat {
        configManager.config.experimental.foreground.resolveHeight()
    }

    /// Matched-geometry id for the focused-space frame, shared by the glass
    /// capsule and the frost cutout so both track the focused space as one.
    private let focusID = "space-focus"

    private var hasFocus: Bool {
        viewModel.spaces.contains {
            $0.windows.contains { $0.isFocused } || $0.isFocused
        }
    }

    var body: some View {
        HStack(spacing: foregroundHeight < 30 ? 0 : 8) {
            ForEach(viewModel.spaces) { space in
                SpaceView(
                    space: space,
                    windowNamespace: windowNamespace,
                    highlightNamespace: highlightNamespace,
                    focusID: focusID
                )
            }
        }
        .environmentObject(viewModel)
        // Backdrop, back-to-front: a frosted rail with a hole punched where the
        // focused space is, then a raised Liquid Glass pill sitting ON TOP at
        // that space. The hole keeps the glass CLEAR-backed (it samples the
        // wallpaper, not the frost), and the pill is taller than the rail so its
        // top/bottom poke past the frost too. Being a top glass layer it carries
        // its own adaptive shadow → it reads as raised. Only this one small
        // glass pill is animated, so it stays fluid.
        .background {
            ZStack {
                // The frosted rail, hole punched under the pill.
                Capsule()
                    .fill(.regularMaterial)
                    .mask { frostMask }
                // The raised, clear-backed glass pill on the focused space.
                if hasFocus {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        // Negative padding BEFORE matchedGeometry grows the pill
                        // a fixed amount past the source (the effect pins the
                        // padded frame). Taller than the rail (vertical poke) and
                        // wider (proud of the space). Consistent, unlike a % scale.
                        .padding(.horizontal, -6)
                        .padding(.vertical, -3)
                        .matchedGeometryEffect(
                            id: focusID, in: highlightNamespace, isSource: false)
                }
            }
        }
        // The original content animation; it also drives the glass pill + hole
        // to the new focused space. Glass is decoupled in the background, so it
        // can't shift the numbers/icons like inline glass did.
        .animation(.smooth(duration: 0.3), value: viewModel.spaces)
        // Breathing room for the focused pill, which pokes ~6pt past the
        // content on each side; keeps it off the neighbouring widgets.
        .padding(.horizontal, 8)
    }

    /// Frosted rail minus the focused-space capsule: destinationOut punches the
    /// hole so the wallpaper (not the frost) is behind the glass pill.
    @ViewBuilder
    private var frostMask: some View {
        if hasFocus {
            Capsule()
                .fill(.white)
                .overlay {
                    Capsule()
                        // Same enlargement as the glass pill so the hole tracks
                        // it exactly — no frost peeking behind the pill's rim.
                        .padding(.horizontal, -6)
                        .padding(.vertical, -3)
                        .matchedGeometryEffect(
                            id: focusID, in: highlightNamespace, isSource: false)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        } else {
            Capsule()
        }
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
    var highlightNamespace: Namespace.ID
    let focusID: String

    var body: some View {
        let isFocused =
            space.windows.contains { $0.isFocused } || space.isFocused
        let hasWindows = !space.windows.isEmpty
        HStack(spacing: 0) {
            Spacer().frame(width: 8)
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
            Spacer().frame(width: 8)
        }
        .frame(height: 30)
        // Publishes this space's frame (when focused) so the background glass
        // capsule and frost cutout match it. Clear → no visual, no layout cost.
        .background {
            if isFocused {
                // Source frame for the glass cut = this space's content frame.
                // The followers add a fixed enlargement (taller + wider) on top,
                // so the pill is a consistent amount bigger than every space.
                Color.clear
                    .matchedGeometryEffect(
                        id: focusID, in: highlightNamespace, isSource: true)
            }
        }
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
            viewModel.switchToSpace(space, thenFocus: window)
        }
        .onHover { value in
            isHovered = value
        }
    }
}
