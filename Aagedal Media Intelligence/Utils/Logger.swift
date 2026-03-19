import Foundation
import os

enum Logger {
    static let general = "general"
    static let processing = "processing"
    static let audio = "audio"
    static let ui = "ui"

    private static let osLogger = os.Logger(subsystem: "aagedal.Aagedal-Media-Intelligence", category: "app")

    nonisolated static func info(_ message: String, category: String = general) {
        osLogger.info("[\(category)] \(message)")
    }

    nonisolated static func debug(_ message: String, category: String = general) {
        osLogger.debug("[\(category)] \(message)")
    }

    nonisolated static func warning(_ message: String, category: String = general) {
        osLogger.warning("[\(category)] \(message)")
    }

    nonisolated static func error(_ message: String, error: Error? = nil, category: String = general) {
        if let error {
            osLogger.error("[\(category)] \(message): \(error.localizedDescription)")
        } else {
            osLogger.error("[\(category)] \(message)")
        }
    }
}
