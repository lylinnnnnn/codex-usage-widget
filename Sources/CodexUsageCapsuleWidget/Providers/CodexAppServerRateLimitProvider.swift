import Darwin
import Foundation

enum CodexAppServerRateLimitError: Error, Equatable, Sendable {
    case executableNotFound
    case processExited(Int32)
    case timedOut
    case missingResponse
    case malformedResponse
    case rpcError
    case missingCodexRateLimits
    case invalidRateLimitSnapshot
    case invalidCapsuleDisplaySnapshot
    case stopped
}

protocol CodexAppServerRateLimitReading: Sendable {
    func readRateLimits(
        using executableURL: URL
    ) async throws -> AppServerRateLimitReadResult
}

struct CodexAppServerRateLimitProvider:
    RateLimitSnapshotProviding,
    CapsuleDisplaySnapshotProviding {
    private let executableURL: URL?
    private let reader: any CodexAppServerRateLimitReading
    private let creditPricingProvider: any CreditPricingConfigurationProviding

    init(
        executableURL: URL? = CodexExecutableLocator.locate(),
        reader: any CodexAppServerRateLimitReading = CodexAppServerRateLimitReader(),
        creditPricingProvider: any CreditPricingConfigurationProviding =
            CreditPricingConfigurationFileProvider()
    ) {
        self.executableURL = executableURL
        self.reader = reader
        self.creditPricingProvider = creditPricingProvider
    }

    func fetchSnapshot() async throws -> RateLimitSnapshot {
        guard let executableURL else {
            throw CodexAppServerRateLimitError.executableNotFound
        }

        let rateLimits = try await reader.readRateLimits(using: executableURL)
        return try CodexAppServerRateLimitSnapshotMapper.map(rateLimits)
    }

    func fetchDisplaySnapshot() async throws -> CapsuleDisplaySnapshot {
        guard let executableURL else {
            throw CodexAppServerRateLimitError.executableNotFound
        }

        let rateLimits = try await reader.readRateLimits(using: executableURL)
        let creditPricing = creditPricingProvider.loadCreditPricing()
        return try CodexAppServerCapsuleDisplaySnapshotMapper.map(
            rateLimits,
            creditPricing: creditPricing
        )
    }
}

struct CodexAppServerRateLimitReader: CodexAppServerRateLimitReading {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 8) {
        self.timeout = timeout
    }

    func readRateLimits(
        using executableURL: URL
    ) async throws -> AppServerRateLimitReadResult {
        let connection = CodexAppServerRateLimitConnection(
            executableURL: executableURL,
            timeout: timeout,
            eventSink: { _ in }
        )

        do {
            try await connection.start()
            let rateLimits = try await connection.readRateLimits()
            await connection.stop()
            return rateLimits
        } catch {
            await connection.stop()
            throw error
        }
    }
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

enum CodexAppServerRateLimitSnapshotMapper {
    static func map(_ readResult: AppServerRateLimitReadResult) throws -> RateLimitSnapshot {
        guard let rateLimits = selectedCodexRateLimits(from: readResult) else {
            throw CodexAppServerRateLimitError.missingCodexRateLimits
        }

        let payload = RateLimitSnapshotPayload(
            primary: payload(from: rateLimits.primary),
            secondary: payload(from: rateLimits.secondary)
        )
        guard let snapshot = RateLimitSnapshotMapper.map(payload) else {
            throw CodexAppServerRateLimitError.invalidRateLimitSnapshot
        }
        return snapshot
    }

    static func selectedCodexRateLimits(
        from readResult: AppServerRateLimitReadResult
    ) -> AppServerRateLimits? {
        if let codexRateLimits = readResult.rateLimitsByLimitId?["codex"] {
            return codexRateLimits
        }

        guard let fallbackRateLimits = readResult.rateLimits else {
            return nil
        }
        guard let limitId = fallbackRateLimits.limitId?.lowercased() else {
            return fallbackRateLimits
        }
        return limitId == "codex" ? fallbackRateLimits : nil
    }

    static func payload(
        from window: AppServerRateLimitWindow?
    ) -> RateLimitWindowPayload? {
        guard let window else { return nil }

        return RateLimitWindowPayload(
            windowDurationMins: window.windowDurationMins,
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt.flatMap { resetTimestamp in
                guard resetTimestamp.isFinite else { return nil }
                return Date(timeIntervalSince1970: resetTimestamp)
            }
        )
    }
}

enum CodexAppServerCapsuleDisplaySnapshotMapper {
    static func map(
        _ readResult: AppServerRateLimitReadResult,
        creditPricing: CreditPricingConfiguration = .defaultUSD
    ) throws -> CapsuleDisplaySnapshot {
        guard let rateLimits = CodexAppServerRateLimitSnapshotMapper.selectedCodexRateLimits(
            from: readResult
        ) else {
            throw CodexAppServerRateLimitError.missingCodexRateLimits
        }

        let payload = CapsuleDisplayPayload(
            windows: [rateLimits.primary, rateLimits.secondary].compactMap {
                CodexAppServerRateLimitSnapshotMapper.payload(from: $0)
            },
            credits: rateLimits.credits.map {
                WorkspaceCreditBalancePayload(
                    balance: $0.balance,
                    hasCredits: $0.hasCredits,
                    unlimited: $0.unlimited
                )
            }
        )
        guard let snapshot = CapsuleDisplaySnapshotMapper.map(
            payload,
            creditPricing: creditPricing
        ) else {
            throw CodexAppServerRateLimitError.invalidCapsuleDisplaySnapshot
        }
        return snapshot
    }
}

enum CodexAppServerRateLimitJSONLParser {
    static func rateLimitReadResult(
        from output: Data,
        responseID: Int
    ) throws -> AppServerRateLimitReadResult {
        let payload = try responsePayload(from: output, responseID: responseID)
        do {
            return try JSONDecoder().decode(AppServerRateLimitReadResult.self, from: payload)
        } catch {
            throw CodexAppServerRateLimitError.malformedResponse
        }
    }

    static func responsePayload(from output: Data, responseID: Int) throws -> Data {
        for line in output.split(separator: 0x0A) {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)),
                let message = object as? [String: Any],
                let identifier = (message["id"] as? NSNumber)?.intValue,
                identifier == responseID,
                message["result"] != nil || message["error"] != nil
            else {
                continue
            }

            if message["error"] != nil {
                throw CodexAppServerRateLimitError.rpcError
            }

            guard let result = message["result"] else {
                throw CodexAppServerRateLimitError.malformedResponse
            }
            do {
                return try JSONSerialization.data(withJSONObject: result)
            } catch {
                throw CodexAppServerRateLimitError.malformedResponse
            }
        }

        throw CodexAppServerRateLimitError.missingResponse
    }

    static func sessionEvent(
        from line: Data
    ) -> CodexAppServerRateLimitSessionEvent? {
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
}

enum CodexAppServerRateLimitSessionEvent: Equatable, Sendable {
    case rateLimitsUpdated
    case accountUpdated
    case disconnected
}

actor CodexAppServerRateLimitConnection {
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let executableURL: URL
    private let timeoutNanoseconds: UInt64
    private let eventSink: @Sendable (CodexAppServerRateLimitSessionEvent) async -> Void
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
        eventSink: @escaping @Sendable (
            CodexAppServerRateLimitSessionEvent
        ) async -> Void
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
            Task {
                await self?.processDidTerminate(status: status)
            }
        }

        try process.run()
        self.process = process
        inputHandle = standardInput.fileHandleForWriting
        outputHandle = standardOutput.fileHandleForReading
        outputHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeOutput(data)
            }
        }

        do {
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "CodexUsageCapsuleWidget",
                        "title": "Codex Usage Capsule Widget",
                        "version": "0.1.0"
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

    func readRateLimits() async throws -> AppServerRateLimitReadResult {
        guard hasCompletedHandshake else {
            throw CodexAppServerRateLimitError.stopped
        }

        let data = try await request(method: "account/rateLimits/read", params: nil)
        do {
            return try JSONDecoder().decode(AppServerRateLimitReadResult.self, from: data)
        } catch {
            throw CodexAppServerRateLimitError.malformedResponse
        }
    }

    func isAlive() -> Bool {
        process?.isRunning == true && hasCompletedHandshake
    }

    func stop() async {
        intentionallyStopped = true
        hasCompletedHandshake = false
        failAllPendingRequests(with: CodexAppServerRateLimitError.stopped)

        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)

        let activeProcess = process
        process = nil
        if let activeProcess {
            await terminateProcess(activeProcess)
        }
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
        if let identifier {
            message["id"] = identifier
        }
        if let params {
            message["params"] = params
        }

        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        return data
    }

    private func write(_ data: Data) throws {
        guard let inputHandle else {
            throw CodexAppServerRateLimitError.stopped
        }
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
            // Never answer app-server requests, especially requests that could
            // ask this local widget to participate in an auth flow.
            return
        }

        if let identifier = (message["id"] as? NSNumber)?.intValue {
            if message["error"] != nil {
                finishRequest(
                    identifier: identifier,
                    with: .failure(CodexAppServerRateLimitError.rpcError)
                )
                return
            }

            guard
                let result = message["result"],
                let resultData = try? JSONSerialization.data(
                    withJSONObject: result
                )
            else {
                finishRequest(
                    identifier: identifier,
                    with: .failure(CodexAppServerRateLimitError.malformedResponse)
                )
                return
            }
            finishRequest(identifier: identifier, with: .success(resultData))
            return
        }

        if let event = CodexAppServerRateLimitJSONLParser.sessionEvent(
            from: line
        ) {
            await eventSink(event)
        }
    }

    private func timeoutRequest(identifier: Int) {
        finishRequest(
            identifier: identifier,
            with: .failure(CodexAppServerRateLimitError.timedOut)
        )
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
        hasCompletedHandshake = false
        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        process = nil
        failAllPendingRequests(
            with: CodexAppServerRateLimitError.processExited(status)
        )

        if !wasIntentional {
            await eventSink(.disconnected)
        }
    }

    private func handleUnexpectedDisconnect() async {
        guard let activeProcess = process else { return }

        hasCompletedHandshake = false
        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        process = nil
        failAllPendingRequests(with: CodexAppServerRateLimitError.missingResponse)
        await terminateProcess(activeProcess)

        if !intentionallyStopped {
            await eventSink(.disconnected)
        }
    }

    private func terminateProcess(_ process: Process) async {
        let processIdentifier = process.processIdentifier
        guard processIdentifier > 0, processExists(processIdentifier) else {
            return
        }

        process.terminate()
        if await waitForProcessExit(processIdentifier, timeout: 0.5) {
            return
        }

        Darwin.kill(processIdentifier, SIGTERM)
        if await waitForProcessExit(processIdentifier, timeout: 0.5) {
            return
        }

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

        if Darwin.kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
