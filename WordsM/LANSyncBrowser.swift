import Foundation
import Network

// MARK: - LANSyncBrowser

/// Discovers remote WordsM devices using NWBrowser.
/// Discovery runs only while the browser is active (SettingsView lifetime).
final class LANSyncBrowser {
    private var browser: NWBrowser?
    var localDeviceID: UUID?

    var onDeviceAdded: ((DiscoveredDevice) -> Void)?
    var onDeviceRemoved: ((UUID) -> Void)?

    func start() {
        guard browser == nil else { return }

        do {
            browser = try NWBrowser(
                for: .bonjourWithTXTRecord(type: LANSyncConstants.serviceType, domain: nil),
                using: NWParameters()
            )
        } catch {
            print("[LANSyncBrowser] Failed to create browser: \(error)")
            return
        }

        browser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("[LANSyncBrowser] Browser ready")
            case .failed:
                print("[LANSyncBrowser] Browser failed")
            case .cancelled:
                break
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] newResults, changes in
            guard let self = self else { return }
            for change in changes {
                switch change {
                case .added(let result):
                    Task { @MainActor [weak self] in
                        self?.handleDeviceAdded(result: result)
                    }
                case .removed(let result):
                    Task { @MainActor [weak self] in
                        self?.handleDeviceRemoved(result: result)
                    }
                default:
                    break
                }
            }
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Device Parsing

    private func parseDevice(from result: NWBrowser.Result) -> DiscoveredDevice? {
        let deviceIDStr: String?
        let name: String

        if case .bonjour(let txtRecord) = result.metadata {
            deviceIDStr = txtRecord.dictionary["deviceID"]
            name = txtRecord.dictionary["name"] ?? endpointHostString(result.endpoint)
        } else {
            deviceIDStr = nil
            name = endpointHostString(result.endpoint)
        }

        guard let idStr = deviceIDStr, let id = UUID(uuidString: idStr) else { return nil }
        // Skip self
        if let myID = localDeviceID, id == myID { return nil }
        return DiscoveredDevice(id: id, name: name, endpoint: result.endpoint)
    }

    private func endpointHostString(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .name(let name, _): return name
            case .ipv4(let addr): return addr.debugDescription
            case .ipv6(let addr): return addr.debugDescription
            @unknown default: return "unknown"
            }
        case .service(let name, _, _, _): return name
        case .unix(let path): return path
        case .url(let url): return url.host ?? url.absoluteString
        @unknown default: return "unknown"
        }
    }

    private func handleDeviceAdded(result: NWBrowser.Result) {
        guard let device = parseDevice(from: result) else { return }
        onDeviceAdded?(device)
    }

    private func handleDeviceRemoved(result: NWBrowser.Result) {
        guard let device = parseDevice(from: result) else { return }
        onDeviceRemoved?(device.id)
    }
}
