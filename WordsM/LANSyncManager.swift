import Foundation
import Network
import SwiftUI
import Combine

// MARK: - LANSyncManager

@MainActor
final class LANSyncManager: ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var syncStates: [UUID: SyncUIState] = [:]
    @Published private(set) var toastMessage: String?
    @Published private(set) var toastResult: SyncMergeResult?

    private let service = LANSyncService()
    private let browser = LANSyncBrowser()
    private let manager: WordsManager

    /// The persistent local device UUID.
    private var localDeviceID: UUID {
        let key = LANSyncConstants.deviceIDKey
        if let raw = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        let newID = UUID()
        UserDefaults.standard.set(newID.uuidString, forKey: key)
        return newID
    }

    /// Display name derived from the system.
    private var localDeviceName: String {
#if os(iOS)
        return UIDevice.current.name
#else
        return ProcessInfo.processInfo.hostName
#endif
    }

    init(manager: WordsManager) {
        self.manager = manager
        setupService()
    }

    // MARK: - Discovery

    func startDiscovery() {
        browser.localDeviceID = localDeviceID
        browser.onDeviceAdded = { [weak self] device in
            guard let self = self else { return }
            // Skip self
            guard device.id != self.localDeviceID else { return }
            if self.devices.contains(where: { $0.id == device.id }) {
                if let idx = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[idx] = device
                }
            } else {
                self.devices.append(device)
            }
        }
        browser.onDeviceRemoved = { [weak self] id in
            self?.devices.removeAll { $0.id == id }
        }
        browser.start()
    }

    func stopDiscovery() {
        browser.stop()
        devices.removeAll()
    }

    // MARK: - Sync

    func sync(with deviceID: UUID) {
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }
        syncStates[deviceID] = .syncing

        // Create session on background and run async sync
        print("[LANSyncManager] Starting sync with \(device.name)")
        print("[LANSyncManager] Using discovered endpoint: \(device.endpoint)")
        let session = LANSyncSession(
            connection: NWConnection(to: device.endpoint, using: .tcp),
            localDeviceID: localDeviceID,
            localDeviceName: localDeviceName,
            manager: manager
        )
        Task {
            await performSync(session: session, deviceID: deviceID)
        }
    }

    private func performSync(session: LANSyncSession, deviceID: UUID) async {
        await session.start()

        let result = await session.result
        let error = await session.errorMessage

        if let err = error {
            print("[LANSyncManager] Sync failed: \(err)")
            syncStates[deviceID] = .failed(err)
        } else if let res = result {
            print("[LANSyncManager] Sync succeeded, addedLearned=\(res.addedLearnedCount), addedMistakes=\(res.addedMistakeCount)")
            syncStates[deviceID] = .success
            toastResult = res
            toastMessage = "✓ 同步完成\n新增已学 \(res.addedLearnedCount) 个 · 新增错题 \(res.addedMistakeCount) 个"
            DispatchQueue.main.asyncAfter(deadline: .now() + LANSyncConstants.resultToastDuration) { [weak self] in
                self?.toastMessage = nil
                self?.toastResult = nil
            }
        } else {
            syncStates[deviceID] = .failed("同步未知错误")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.syncStates[deviceID] = .idle
        }
    }

    // MARK: - Service Setup

    private func setupService() {
        service.incomingConnectionHandler = { [weak self] conn in
            print("[LANSyncService] Incoming connection received: \(conn)")
            guard let self = self else { return }
            print("[LANSyncManager] Accepted incoming sync connection")
            let session = LANSyncSession(
                connection: conn,
                localDeviceID: self.localDeviceID,
                localDeviceName: self.localDeviceName,
                manager: self.manager
            )
            Task {
                await session.start()
            }
        }
        service.start()
    }
}
