import Foundation

// MARK: - LANSyncConstants

enum LANSyncConstants {
    /// Bonjour service type published and discovered across the LAN.
    static let serviceType = "_wordsm-sync._tcp"
    static let serviceDomain = "local."

    /// UserDefaults key for the persistent local device UUID.
    static let deviceIDKey = "wordsM_deviceID"

    /// Timeout for a complete sync session (connect → hello → payload → ack).
    static let sessionTimeout: TimeInterval = 10

    /// Maximum allowed message body size (1 MB).
    static let maximumMessageSize = 1_048_576

    /// Duration the success Snackbar is shown before auto-hiding.
    static let resultToastDuration: TimeInterval = 3
}
