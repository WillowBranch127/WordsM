import Foundation
import Network

// MARK: - LANSyncSession

/// Handles a single sync TCP session with a remote device.
/// Implements length-prefix framing (4-byte big-endian body length + complete envelope),
/// hello handshake, payload exchange, union merge, and ack.
final class LANSyncSession {
    private let connection: NWConnection
    private let localDeviceID: UUID
    private let localDeviceName: String
    private let manager: WordsManager
    private let timeout: TimeInterval

    @MainActor var result: SyncMergeResult? = nil
    @MainActor var errorMessage: String? = nil

    init(
        connection: NWConnection,
        localDeviceID: UUID,
        localDeviceName: String,
        manager: WordsManager,
        timeout: TimeInterval = LANSyncConstants.sessionTimeout
    ) {
        self.connection = connection
        self.localDeviceID = localDeviceID
        self.localDeviceName = localDeviceName
        self.manager = manager
        self.timeout = timeout
    }

    func start() async {
        print("[LANSyncSession] Starting connection")
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            print("[LANSyncSession] Connection state: \(state)")
        }
        connection.start(queue: .global(qos: .userInitiated))

        do {
            let mergeResult = try await runSessionWithTimeout()
            await MainActor.run {
                self.result = mergeResult
            }
        } catch LANSyncError.timeout {
            print("[LANSyncSession] Session timeout after \(timeout)s")
            await MainActor.run {
                self.errorMessage = "同步超时"
            }
        } catch {
            print("[LANSyncSession] Session error: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }

        connection.cancel()
        print("[LANSyncSession] Connection closed")
    }

    // MARK: - Timeout wrapper

    /// Wraps the session in a timeout. If the session does not complete within `timeout` seconds,
    /// throws LANSyncError.timeout.
    private func runSessionWithTimeout() async throws -> SyncMergeResult {
        enum Phase { case sessionDone, timeout }
        var phase: Phase? = nil

        let sessionTask = Task {
            defer { phase = .sessionDone }
            return try await runSession()
        }
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            phase = .timeout
        }

        // Wait for session to finish, but cancel if timeout fires first
        while phase == nil {
            if sessionTask.isCancelled { throw LANSyncError.timeout }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        timeoutTask.cancel()

        if phase == .timeout {
            sessionTask.cancel()
            throw LANSyncError.timeout
        }

        return try await sessionTask.value
    }

    // MARK: - Session Flow

    private func runSession() async throws -> SyncMergeResult {
        // Phase 1: Hello exchange
        print("[LANSyncSession] Sending hello")
        try await sendEnvelope(.hello, data: try JSONEncoder().encode(SyncHello(
            protocolVersion: 1,
            deviceID: localDeviceID,
            deviceName: localDeviceName
        )))
        print("[LANSyncSession] Hello sent")

        print("[LANSyncSession] Waiting for remote hello")
        let remoteHelloMsg = try await receiveEnvelope()
        guard remoteHelloMsg.type == .hello else {
            throw LANSyncError.invalidMessageOrder(expected: .hello, got: remoteHelloMsg.type)
        }
        guard let helloData = remoteHelloMsg.data else {
            throw LANSyncError.helloDecodeFailed
        }
        let remoteHello = try JSONDecoder().decode(SyncHello.self, from: helloData)
        print("[LANSyncSession] Remote hello received: \(remoteHello.deviceName) (\(remoteHello.deviceID))")

        guard remoteHello.protocolVersion == 1 else {
            throw LANSyncError.protocolVersionMismatch(remoteVersion: remoteHello.protocolVersion)
        }

        // Phase 2: Send our payload
        print("[LANSyncSession] Sending payload")
        let localLearned = Array(manager.learnedIDs).sorted()
        let localMistakes = Array(manager.mistakeIDs).sorted()
        try await sendEnvelope(.payload, data: try JSONEncoder().encode(SyncPayloadEnvelope(
            protocolVersion: 1,
            deviceID: localDeviceID,
            learnedIDs: localLearned,
            mistakeIDs: localMistakes
        )))
        print("[LANSyncSession] Payload sent")

        // Phase 3: Receive remote payload
        print("[LANSyncSession] Waiting for remote payload")
        let payloadMsg = try await receiveEnvelope()
        guard payloadMsg.type == .payload else {
            throw LANSyncError.invalidMessageOrder(expected: .payload, got: payloadMsg.type)
        }
        guard let payloadData = payloadMsg.data else {
            throw LANSyncError.payloadDecodeFailed
        }
        let remotePayload = try JSONDecoder().decode(SyncPayloadEnvelope.self, from: payloadData)
        print("[LANSyncSession] Remote payload received: learned=\(remotePayload.learnedIDs.count) mistakes=\(remotePayload.mistakeIDs.count)")

        // Phase 4: Send ack for remote payload
        print("[LANSyncSession] Sending payload ACK")
        try await sendEnvelope(.payloadAck, data: nil)
        print("[LANSyncSession] Payload ACK sent")

        // Phase 5: Receive ack for our payload
        print("[LANSyncSession] Waiting for remote payload ACK")
        let ackMsg = try await receiveEnvelope()
        guard ackMsg.type == .payloadAck else {
            throw LANSyncError.invalidMessageOrder(expected: .payloadAck, got: ackMsg.type)
        }
        print("[LANSyncSession] Remote payload ACK received")

        // Phase 6: Compute union and merge
        print("[LANSyncSession] Merging data")
        let remoteLearned = Set(remotePayload.learnedIDs)
        let remoteMistakes = Set(remotePayload.mistakeIDs)
        let oldLearned = manager.learnedIDs
        let oldMistakes = manager.mistakeIDs
        let mergedLearned = oldLearned.union(remoteLearned)
        let mergedMistakes = oldMistakes.union(remoteMistakes)
        let addedLearned = mergedLearned.subtracting(oldLearned).count
        let addedMistakes = mergedMistakes.subtracting(oldMistakes).count

        manager.mergeSyncedData(remoteLearnedIDs: remoteLearned, remoteMistakeIDs: remoteMistakes)
        print("[LANSyncSession] Merge completed: learned +\(addedLearned), mistakes +\(addedMistakes)")

        return SyncMergeResult(addedLearnedCount: addedLearned, addedMistakeCount: addedMistakes)

        // Phase 7: Send complete
        print("[LANSyncSession] Sending complete")
        try await sendEnvelope(.complete, data: nil)
        print("[LANSyncSession] Sync completed successfully")
    }

    // MARK: - Framing: Send

    /// Send a complete message: 4-byte big-endian body length + encoded SyncMessageEnvelope.
    private func sendEnvelope(_ type: SyncMessageType, data: Data?) async throws {
        let envelope = SyncMessageEnvelope(type: type, data: data)
        let body = try JSONEncoder().encode(envelope)
        guard body.count <= LANSyncConstants.maximumMessageSize else {
            throw LANSyncError.messageTooLarge
        }
        var length = UInt32(body.count).bigEndian
        let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        try await sendRaw(lengthData)
        try await sendRaw(body)
    }

    /// Send raw bytes via NWConnection completion API, wrapped in async.
    private func sendRaw(_ data: Data) async throws {
        let semaphore = DispatchSemaphore(value: 0)
        var error: Error? = nil
        connection.send(content: data, isComplete: false, completion: .contentProcessed { err in
            error = err
            semaphore.signal()
        })
        try await waitFor(semaphore)
        if let e = error { throw e }
    }

    // MARK: - Framing: Receive

    /// Receive a complete envelope: read 4-byte length, then read exactly that many bytes, decode.
    private func receiveEnvelope() async throws -> SyncMessageEnvelope {
        let lengthData = try await receiveExactly(4)
        let len = lengthData.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
        print("[LANSyncSession] Received frame length: \(len)")
        guard len > 0, len <= UInt32(LANSyncConstants.maximumMessageSize) else {
            throw LANSyncError.framingError
        }
        let body = try await receiveExactly(Int(len))
        do {
            return try JSONDecoder().decode(SyncMessageEnvelope.self, from: body)
        } catch {
            throw LANSyncError.framingError
        }
    }

    /// Receive exactly `count` bytes, handling partial TCP reads.
    private func receiveExactly(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var accumulated = Data()
        while accumulated.count < count {
            let remaining = count - accumulated.count
            let semaphore = DispatchSemaphore(value: 0)
            var chunk: Data? = nil
            var isComplete = false
            var error: Error? = nil

            connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, ctx, complete, err in
                chunk = data
                isComplete = complete
                error = err
                semaphore.signal()
            }
            try await waitFor(semaphore)

            if let e = error { throw e }
            if let d = chunk { accumulated.append(d) }
            if isComplete && accumulated.count < count {
                throw LANSyncError.connectionClosedUnexpectedly
            }
        }
        return accumulated
    }

    /// Wait for a semaphore without blocking the Swift concurrency worker thread.
    /// Runs the wait on a background DispatchQueue to avoid blocking the actor.
    private func waitFor(_ semaphore: DispatchSemaphore) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                DispatchQueue.main.async {
                    cont.resume()
                }
            }
        }
    }
}

// MARK: - LANSyncError

enum LANSyncError: LocalizedError {
    case framingError
    case messageTooLarge
    case connectionClosedUnexpectedly
    case helloDecodeFailed
    case payloadDecodeFailed
    case invalidMessageOrder(expected: SyncMessageType, got: SyncMessageType)
    case protocolVersionMismatch(remoteVersion: Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .framingError: return "消息帧格式错误"
        case .messageTooLarge: return "消息过大"
        case .connectionClosedUnexpectedly: return "连接意外关闭"
        case .helloDecodeFailed: return "无法解析对方 Hello 消息"
        case .payloadDecodeFailed: return "无法解析对方 Payload 消息"
        case .invalidMessageOrder(let expected, let got):
            return "消息顺序错误：期望 \(expected.rawValue)，收到 \(got.rawValue)"
        case .protocolVersionMismatch(let version):
            return "协议版本不兼容：远端版本 \(version)"
        case .timeout: return "同步超时"
        }
    }
}
