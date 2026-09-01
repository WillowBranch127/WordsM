import Foundation
import Network

// MARK: - DiscoveredDevice

/// Represents a remote WordsM device discovered via Bonjour.
/// Uses a class so NWEndpoint does not need to conform to Sendable/Hashable.
final class DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let endpoint: NWEndpoint

    init(id: UUID, name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SyncUIState

/// Lightweight UI state for a single sync session with a device.
enum SyncUIState: Equatable {
    case idle
    case syncing
    case success
    case failed(String)
}

// MARK: - SyncMergeResult

struct SyncMergeResult {
    let addedLearnedCount: Int
    let addedMistakeCount: Int
}

// MARK: - LANSyncMessageTypes

enum SyncMessageType: String, Codable {
    case hello
    case payload
    case payloadAck
    case complete
    case error
}

struct SyncHello: Codable {
    let protocolVersion: Int
    let deviceID: UUID
    let deviceName: String
}

struct SyncPayloadEnvelope: Codable {
    let protocolVersion: Int
    let deviceID: UUID
    let learnedIDs: [Int]
    let mistakeIDs: [Int]
}

// Helper envelope that wraps type + payload data
struct SyncMessageEnvelope: Codable {
    let type: SyncMessageType
    let data: Data?
}
