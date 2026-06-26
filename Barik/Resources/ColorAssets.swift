import AppKit
import SwiftUI

/// Hand-written replacement for the color symbols Xcode auto-generates from
/// `Assets.xcassets`. The asset catalog can only be compiled by `actool`
/// (full Xcode), so when building with the SwiftPM/Command-Line-Tools flow we
/// define the same `ColorResource` + `ShapeStyle` API here. Call sites such as
/// `Color(.foreground)` and `.fill(.shadow)` keep working unchanged.
///
/// Values mirror `Barik/Resources/Assets.xcassets/Colors/*.colorset` (sRGB,
/// light = universal appearance, dark = "luminosity dark" appearance).
struct ColorResource {
    fileprivate let light: (r: Double, g: Double, b: Double, a: Double)
    fileprivate let dark: (r: Double, g: Double, b: Double, a: Double)

    fileprivate var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark =
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        }
    }
}

extension ColorResource {
    static let active = ColorResource(
        light: (1, 1, 1, 0.8), dark: (1, 1, 1, 0.4))
    static let noActive = ColorResource(
        light: (1, 1, 1, 0.4), dark: (1, 1, 1, 0.1))
    static let selected = ColorResource(
        light: (0, 0, 0, 0.1), dark: (1, 1, 1, 0.4))
    static let foreground = ColorResource(
        light: (0, 0, 0, 0.9), dark: (1, 1, 1, 0.9))
    static let foregroundShadow = ColorResource(
        light: (0, 0, 0, 0.0), dark: (0, 0, 0, 0.5))
    static let foregroundOutside = ColorResource(
        light: (1, 1, 1, 0.9), dark: (1, 1, 1, 0.9))
    static let foregroundOutsideInvert = ColorResource(
        light: (0, 0, 0, 0.8), dark: (0, 0, 0, 0.8))
    static let foregroundShadowOutside = ColorResource(
        light: (0, 0, 0, 0.3), dark: (0, 0, 0, 0.5))
    static let shadow = ColorResource(
        light: (0, 0, 0, 0.1), dark: (0, 0, 0, 0.5))
    static let icon = ColorResource(
        light: (1, 1, 1, 0.9), dark: (1, 1, 1, 0.9))
    static let iconShadow = ColorResource(
        light: (0, 0, 0, 0.1), dark: (0, 0, 0, 0.1))
}

extension Color {
    init(_ resource: ColorResource) {
        self = Color(nsColor: resource.nsColor)
    }
}

extension ShapeStyle where Self == Color {
    static var active: Color { Color(.active) }
    static var noActive: Color { Color(.noActive) }
    static var selected: Color { Color(.selected) }
    static var foreground: Color { Color(.foreground) }
    static var foregroundShadow: Color { Color(.foregroundShadow) }
    static var foregroundOutside: Color { Color(.foregroundOutside) }
    static var foregroundOutsideInvert: Color { Color(.foregroundOutsideInvert) }
    static var foregroundShadowOutside: Color { Color(.foregroundShadowOutside) }
    static var shadow: Color { Color(.shadow) }
    static var icon: Color { Color(.icon) }
    static var iconShadow: Color { Color(.iconShadow) }
}
