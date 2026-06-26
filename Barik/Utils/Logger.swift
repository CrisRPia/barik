import Foundation
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.barik"
    static let pipe = Logger(subsystem: subsystem, category: "Pipe")
    static let spaces = Logger(subsystem: subsystem, category: "Spaces")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
