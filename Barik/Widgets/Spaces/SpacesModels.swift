import AppKit

/// A window as the UI consumes it (icon resolved, value-typed for SwiftUI
/// diffing). Built from the aerospace decode model.
struct AnyWindow: Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String?
    let isFocused: Bool
    let appIcon: NSImage?

    init(_ window: AeroWindow) {
        self.id = window.id
        self.title = window.title
        self.appName = window.appName
        self.isFocused = window.isFocused
        self.appIcon = window.appIcon
    }

    static func == (lhs: AnyWindow, rhs: AnyWindow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.isFocused == rhs.isFocused
    }
}

/// A space as the UI consumes it. Built from the aerospace decode model.
struct AnySpace: Identifiable, Equatable {
    let id: String
    let isFocused: Bool
    let windows: [AnyWindow]
    /// The window focusing this space would land on: its most-recently-used
    /// window (tracked over the session), or the top of the stack as a guess.
    /// Populated by `SpacesViewModel`, not the provider.
    var emphasizedWindowID: Int?

    init(_ space: AeroSpace) {
        self.id = space.workspace
        self.isFocused = space.isFocused
        self.windows = space.windows.map { AnyWindow($0) }
    }

    static func == (lhs: AnySpace, rhs: AnySpace) -> Bool {
        return lhs.id == rhs.id && lhs.isFocused == rhs.isFocused
            && lhs.windows == rhs.windows
            && lhs.emphasizedWindowID == rhs.emphasizedWindowID
    }
}
