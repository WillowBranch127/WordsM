import Foundation
import Network

// MARK: - LANSyncService

/// Manages the inbound Bonjour service so this device is always discoverable
/// as long as the app runs.
final class LANSyncService {
    private var listener: NWListener?
    private let serviceType = LANSyncConstants.serviceType

    /// Closure called when a new inbound connection arrives.
    /// This is called on an arbitrary background queue; callers should dispatch to main.
    var incomingConnectionHandler: ((NWConnection) -> Void)?

    init() {}

    func start() {
        // Build TXT record with our device ID and name
        var txt = NWTXTRecord()
        txt.setEntry(.string(localDeviceID.uuidString), for: "deviceID")
        txt.setEntry(.string(localDeviceName), for: "name")

        let service = NWListener.Service(
            name: nil,
            type: serviceType,
            domain: nil,  // nil = use default domain, works across platforms
            txtRecord: txt
        )

        do {
            listener = try NWListener(service: service, using: NWParameters.tcp)
        } catch {
            print("[LANSyncService] Fail/Volumes/SSD/home/shuzhongliu/Projects/WordsM/WordsMed to create listener: \(error)")
            return
        }
        guard let listener = listener else { return }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    print("[LANSyncService] Listener ready on \(self.serviceType)")
                case .failed:
                    print("[LANSyncService] Listener failed")
                    self.listener?.cancel()
                    self.listener = nil
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in
                self?.incomingConnectionHandler?(conn)
            }
        }

        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Local Identity

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

    private var localDeviceName: String {
        return ProcessInfo.processInfo.hostName
    }
}
