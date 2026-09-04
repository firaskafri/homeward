import Foundation
import OSLog

enum HomewardLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Homeward"

    static let lifecycle = Logger(
        subsystem: subsystem,
        category: "lifecycle"
    )
    static let persistence = Logger(
        subsystem: subsystem,
        category: "persistence"
    )
}
