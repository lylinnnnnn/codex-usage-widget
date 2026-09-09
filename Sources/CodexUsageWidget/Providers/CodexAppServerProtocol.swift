import CryptoKit
import Darwin
import Foundation

enum CodexAppServerError: Error, Equatable, Sendable {
    case executableNotFound
    case processExited(Int32)
    case timedOut
    case missingResponse
    case malformedResponse
    case rpcError
    case unsupportedAccount
    case missingCodexRateLimits
    case invalidDisplaySnapshot
    case stopped
}

struct AppServerAccountReadResult: Decodable, Equatable, Sendable {
    let account: AppServerAccount?
}

struct AppServerAccount: Decodable, Equatable, Sendable {
    let type: String
    let email: String?
    let planType: String?
}

struct AppServerRateLimitReadResult: Decodable, Equatable, Sendable {
    let rateLimits: AppServerRateLimits?
    let rateLimitsByLimitId: [String: AppServerRateLimits]?
}

struct AppServerRateLimits: Decodable, Equatable, Sendable {
    let limitId: String?
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let credits: AppServerWorkspaceCredits?
}

struct AppServerWorkspaceCredits: Decodable, Equatable, Sendable {
    let balance: String?
    let hasCredits: Bool?
    let unlimited: Bool?
}

struct AppServerRateLimitWindow: Decodable, Equatable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

struct AppServerRawSnapshot: Equatable, Sendable {
    let account: AppServerAccountReadResult
    let rateLimits: AppServerRateLimitReadResult
}

struct CodexUsageSnapshot: Equatable, Sendable {
    let accountFingerprint: String?
    let displaySnapshot: CapsuleDisplaySnapshot
    let sessionGeneration: UInt64
}

enum CodexAppServerSnapshotMapper {
    static func map(
        _ rawSnapshot: AppServerRawSnapshot,
        creditConfiguration: CreditDisplayConfiguration,
        sessionGeneration: UInt64
    ) throws -> CodexUsageSnapshot {
        guard
            let account = rawSnapshot.account.account,
            account.type.lowercased() == "chatgpt"
        else {
            throw CodexAppServerError.unsupportedAccount
        }

        guard let rateLimits = selectedCodexRateLimits(from: rawSnapshot.rateLimits) else {
            throw CodexAppServerError.missingCodexRateLimits
        }

        let payload = CapsuleDisplayPayload(
            windows: [rateLimits.primary, rateLimits.secondary].compactMap(windowPayload),
            credits: rateLimits.credits.map {
                WorkspaceCreditBalancePayload(
                    balance: $0.balance,
                    hasCredits: $0.hasCredits,
                    unlimited: $0.unlimited
                )
            }
        )

        guard let displaySnapshot = CapsuleDisplaySnapshotMapper.map(
            payload,
            creditConfiguration: creditConfiguration
        ) else {
            throw CodexAppServerError.invalidDisplaySnapshot
        }

        return CodexUsageSnapshot(
            accountFingerprint: accountFingerprint(for: account),
            displaySnapshot: displaySnapshot,
            sessionGeneration: sessionGeneration
        )
    }

    static func selectedCodexRateLimits(
        from readResult: AppServerRateLimitReadResult
    ) -> AppServerRateLimits? {
        if let codexRateLimits = readResult.rateLimitsByLimitId?["codex"] {
            return codexRateLimits
        }

        guard let fallback = readResult.rateLimits else { return nil }
        guard let limitIdentifier = fallback.limitId?.lowercased() else {
            return fallback
        }
        return limitIdentifier == "codex" ? fallback : nil
    }

    private static func windowPayload(
        _ window: AppServerRateLimitWindow?
    ) -> RateLimitWindowPayload? {
        guard let window else { return nil }
        return RateLimitWindowPayload(
            windowDurationMins: window.windowDurationMins,
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt.flatMap {
                $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
            }
        )
    }

    private static func accountFingerprint(for account: AppServerAccount) -> String? {
        guard let email = account.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !email.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(data: Data("chatgpt|\(email)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum CodexAppServerJSONLParser {
    static func rawSnapshot(
        from output: Data,
        accountResponseID: Int,
        rateLimitResponseID: Int
    ) throws -> AppServerRawSnapshot {
        let accountPayload = try responsePayload(from: output, responseID: accountResponseID)
        let rateLimitPayload = try responsePayload(
            from: output,
            responseID: rateLimitResponseID
        )

        do {
            return AppServerRawSnapshot(
                account: try JSONDecoder().decode(
                    AppServerAccountReadResult.self,
                    from: accountPayload
                ),
                rateLimits: try JSONDecoder().decode(
                    AppServerRateLimitReadResult.self,
                    from: rateLimitPayload
                )
            )
        } catch {
            throw CodexAppServerError.malformedResponse
        }
    }

    static func sessionEvent(from line: Data) -> CodexAppServerSessionEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let message = object as? [String: Any],
            message["id"] == nil,
            let method = message["method"] as? String
        else {
            return nil
        }

        switch method {
        case "account/rateLimits/updated":
            return .rateLimitsUpdated
        case "account/updated":
            return .accountUpdated
        default:
            return nil
        }
    }

    private static func responsePayload(
        from output: Data,
        responseID: Int
    ) throws -> Data {
        for line in output.split(separator: 0x0A) {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)),
                let message = object as? [String: Any],
                let identifier = (message["id"] as? NSNumber)?.intValue,
                identifier == responseID
            else {
                continue
            }

            if message["error"] != nil { throw CodexAppServerError.rpcError }
            guard let result = message["result"] else {
                throw CodexAppServerError.malformedResponse
            }
            guard let data = try? JSONSerialization.data(withJSONObject: result) else {
                throw CodexAppServerError.malformedResponse
            }
            return data
        }

        throw CodexAppServerError.missingResponse
    }
}

enum CodexAppServerSessionEvent: Equatable, Sendable {
    case rateLimitsUpdated
    case accountUpdated
    case disconnected
}

actor CodexAppServerConnection {
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let executableURL: URL
    private let timeoutNanoseconds: UInt64
    private let eventSink: @Sendable (CodexAppServerSessionEvent) async -> Void
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var nextRequestIdentifier = 1
    private var hasCompletedHandshake = false
    private var intentionallyStopped = false

    init(
        executableURL: URL,
        timeout: TimeInterval,
        eventSink: @escaping @Sendable (CodexAppServerSessionEvent) async -> Void
    ) {
        self.executableURL = executableURL
        timeoutNanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        self.eventSink = eventSink
    }

    func start() async throws {
        guard process == nil else { return }

        intentionallyStopped = false
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]

        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { await self?.processDidTerminate(status: status) }
        }

        try process.run()
        self.process = process
        inputHandle = standardInput.fileHandleForWriting
        outputHandle = standardOutput.fileHandleForReading
        outputHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.consumeOutput(data) }
        }

        do {
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "CodexUsageWidget",
                        "title": "Codex Usage Widget",
                        "version": "1.0.0"
                    ]
                ]
            )
            try sendNotification(method: "initialized", params: [:])
            hasCompletedHandshake = true
        } catch {
            await stop()
            throw error
        }
    }

    func readSnapshot() async throws -> AppServerRawSnapshot {
        guard hasCompletedHandshake else { throw CodexAppServerError.stopped }

        async let accountData = request(
            method: "account/read",
            params: ["refreshToken": false]
        )
        async let rateLimitData = request(
            method: "account/rateLimits/read",
            params: nil
        )

        do {
            return try AppServerRawSnapshot(
                account: JSONDecoder().decode(
                    AppServerAccountReadResult.self,
                    from: try await accountData
                ),
                rateLimits: JSONDecoder().decode(
                    AppServerRateLimitReadResult.self,
                    from: try await rateLimitData
                )
            )
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            throw CodexAppServerError.malformedResponse
        }
    }

    func isAlive() -> Bool {
        process?.isRunning == true && hasCompletedHandshake
    }

    func stop() async {
        intentionallyStopped = true
        hasCompletedHandshake = false
        failAllPendingRequests(with: CodexAppServerError.stopped)
        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)

        let activeProcess = process
        process = nil
        if let activeProcess { await terminateProcess(activeProcess) }
    }

    private func request(method: String, params: [String: Any]?) async throws -> Data {
        let identifier = nextRequestIdentifier
        nextRequestIdentifier += 1
        let requestData = try messageData(
            method: method,
            identifier: identifier,
            params: params
        )
        let requestTimeoutNanoseconds = timeoutNanoseconds

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: requestTimeoutNanoseconds)
                } catch {
                    return
                }
                await self?.timeoutRequest(identifier: identifier)
            }
            pendingRequests[identifier] = PendingRequest(
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            do {
                try write(requestData)
            } catch {
                finishRequest(identifier: identifier, with: .failure(error))
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try write(messageData(method: method, identifier: nil, params: params))
    }

    private func messageData(
        method: String,
        identifier: Int?,
        params: [String: Any]?
    ) throws -> Data {
        var message: [String: Any] = ["method": method]
        if let identifier { message["id"] = identifier }
        if let params { message["params"] = params }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        return data
    }

    private func write(_ data: Data) throws {
        guard let inputHandle else { throw CodexAppServerError.stopped }
        try inputHandle.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) async {
        guard !data.isEmpty else {
            await handleUnexpectedDisconnect()
            return
        }

        outputBuffer.append(data)
        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newlineIndex])
            outputBuffer.removeSubrange(...newlineIndex)
            await handleLine(line)
        }
    }

    private func handleLine(_ line: Data) async {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let message = object as? [String: Any]
        else {
            return
        }

        if message["method"] != nil,
           message["id"] != nil,
           message["result"] == nil,
           message["error"] == nil {
            return
        }

        if let identifier = (message["id"] as? NSNumber)?.intValue {
            if message["error"] != nil {
                finishRequest(identifier: identifier, with: .failure(CodexAppServerError.rpcError))
                return
            }
            guard
                let result = message["result"],
                let resultData = try? JSONSerialization.data(withJSONObject: result)
            else {
                finishRequest(
                    identifier: identifier,
                    with: .failure(CodexAppServerError.malformedResponse)
                )
                return
            }
            finishRequest(identifier: identifier, with: .success(resultData))
            return
        }

        if let event = CodexAppServerJSONLParser.sessionEvent(from: line) {
            await eventSink(event)
        }
    }

    private func timeoutRequest(identifier: Int) {
        finishRequest(identifier: identifier, with: .failure(CodexAppServerError.timedOut))
    }

    private func finishRequest(identifier: Int, with result: Result<Data, Error>) {
        guard let pendingRequest = pendingRequests.removeValue(forKey: identifier) else {
            return
        }
        pendingRequest.timeoutTask.cancel()
        pendingRequest.continuation.resume(with: result)
    }

    private func failAllPendingRequests(with error: Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    private func processDidTerminate(status: Int32) async {
        guard process != nil else { return }
        let wasIntentional = intentionallyStopped
        clearProcessState(error: CodexAppServerError.processExited(status))
        if !wasIntentional { await eventSink(.disconnected) }
    }

    private func handleUnexpectedDisconnect() async {
        guard let activeProcess = process else { return }
        clearProcessState(error: CodexAppServerError.missingResponse)
        await terminateProcess(activeProcess)
        if !intentionallyStopped { await eventSink(.disconnected) }
    }

    private func clearProcessState(error: Error) {
        hasCompletedHandshake = false
        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        process = nil
        failAllPendingRequests(with: error)
    }

    private func terminateProcess(_ process: Process) async {
        let processIdentifier = process.processIdentifier
        guard processIdentifier > 0, processExists(processIdentifier) else { return }
        process.terminate()
        if await waitForProcessExit(processIdentifier, timeout: 0.5) { return }
        Darwin.kill(processIdentifier, SIGTERM)
        if await waitForProcessExit(processIdentifier, timeout: 0.5) { return }
        Darwin.kill(processIdentifier, SIGKILL)
        _ = await waitForProcessExit(processIdentifier, timeout: 1)
    }

    private func waitForProcessExit(
        _ processIdentifier: pid_t,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while processExists(processIdentifier), Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 25_000_000)
            } catch {
                break
            }
        }
        return !processExists(processIdentifier)
    }

    private func processExists(_ processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0 else { return false }
        if Darwin.kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }
}
