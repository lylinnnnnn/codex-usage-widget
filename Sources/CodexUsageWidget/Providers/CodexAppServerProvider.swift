import Foundation

actor CodexAppServerProvider: CodexUsageSnapshotProviding, CodexUsageEventProviding {
    private struct ActiveSession: Sendable {
        let identifier: UUID
        let generation: UInt64
        let connection: CodexAppServerConnection
    }

    private var activeSession: ActiveSession?
    private var connectingConnection: CodexAppServerConnection?
    private var connectingIdentifier: UUID?
    private var connectingGeneration: UInt64?
    private var disconnectedConnectingIdentifiers = Set<UUID>()
    private var isConnecting = false
    private var connectionWaiters: [CheckedContinuation<ActiveSession, Error>] = []
    private var eventContinuations: [
        UUID: AsyncStream<CodexUsageUpdateEvent>.Continuation
    ] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var hasConnectedOnce = false
    private var hasFailedConnectionAttempt = false
    private var sessionGeneration: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var isStopped = false

    private let executableLocator: @Sendable () -> URL?
    private let creditConfigurationProvider: any CreditDisplayConfigurationProviding

    init(
        executableLocator: @escaping @Sendable () -> URL? = {
            CodexExecutableLocator.locate()
        },
        creditConfigurationProvider: any CreditDisplayConfigurationProviding =
            CreditDisplayConfigurationFileProvider()
    ) {
        self.executableLocator = executableLocator
        self.creditConfigurationProvider = creditConfigurationProvider
    }

    func fetchSnapshot() async throws -> CodexUsageSnapshot {
        guard !isStopped else { throw CodexAppServerError.stopped }

        while true {
            let session = try await activeSessionOrConnect()
            do {
                let rawSnapshot = try await session.connection.readSnapshot()
                guard isCurrent(session) else { continue }

                return try CodexAppServerSnapshotMapper.map(
                    rawSnapshot,
                    creditConfiguration: creditConfigurationProvider
                        .loadCreditDisplayConfiguration(),
                    sessionGeneration: session.generation
                )
            } catch {
                guard isCurrent(session) else { continue }
                await invalidateSession(session)
                throw error
            }
        }
    }

    func reconfirmAccountAndFetchSnapshot() async throws -> CodexUsageSnapshot {
        guard !isStopped else { throw CodexAppServerError.stopped }
        await retireCurrentSessions()
        return try await fetchSnapshot()
    }

    func makeEventStream() async -> AsyncStream<CodexUsageUpdateEvent> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<CodexUsageUpdateEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )

        guard !isStopped else {
            continuation.finish()
            return stream
        }

        eventContinuations[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(identifier: identifier) }
        }

        Task { [weak self] in
            await self?.beginEventConnectionIfNeeded()
        }
        return stream
    }

    func stopEventMonitoring() async {
        isStopped = true
        let continuations = eventContinuations.values
        eventContinuations.removeAll()
        continuations.forEach { $0.finish() }
        await retireCurrentSessions()
    }

    private func beginEventConnectionIfNeeded() async {
        guard !isStopped, activeSession == nil else { return }
        _ = try? await activeSessionOrConnect()
    }

    private func activeSessionOrConnect() async throws -> ActiveSession {
        guard !isStopped else { throw CodexAppServerError.stopped }
        if let activeSession { return activeSession }

        if isConnecting {
            return try await withCheckedThrowingContinuation { continuation in
                connectionWaiters.append(continuation)
            }
        }

        isConnecting = true
        let connectionLifecycle = lifecycleGeneration
        let connectionGeneration = sessionGeneration
        let identifier = UUID()
        connectingIdentifier = identifier
        connectingGeneration = connectionGeneration
        disconnectedConnectingIdentifiers.remove(identifier)

        guard let executableURL = executableLocator() else {
            clearConnectingAttempt(identifier: identifier)
            hasFailedConnectionAttempt = true
            resolveConnectionWaiters(with: .failure(CodexAppServerError.executableNotFound))
            scheduleReconnectIfNeeded()
            throw CodexAppServerError.executableNotFound
        }

        let connection = CodexAppServerConnection(
            executableURL: executableURL,
            timeout: 8,
            eventSink: { [weak self] event in
                await self?.handleSessionEvent(
                    event,
                    identifier: identifier,
                    generation: connectionGeneration
                )
            }
        )
        connectingConnection = connection

        do {
            try await connection.start()
            guard
                !isStopped,
                lifecycleGeneration == connectionLifecycle,
                sessionGeneration == connectionGeneration,
                connectingIdentifier == identifier,
                !disconnectedConnectingIdentifiers.contains(identifier),
                await connection.isAlive()
            else {
                await connection.stop()
                throw CodexAppServerError.stopped
            }

            let session = ActiveSession(
                identifier: identifier,
                generation: connectionGeneration,
                connection: connection
            )
            activeSession = session
            clearConnectingAttempt(identifier: identifier)
            resolveConnectionWaiters(with: .success(session))

            let didReconnect = hasConnectedOnce || hasFailedConnectionAttempt
            hasConnectedOnce = true
            hasFailedConnectionAttempt = false
            if didReconnect {
                emit(
                    .refreshRequired(
                        .appServerReconnected,
                        sessionGeneration: session.generation
                    )
                )
            }
            return session
        } catch {
            let wasCurrentAttempt = connectingIdentifier == identifier
            if wasCurrentAttempt {
                clearConnectingAttempt(identifier: identifier)
                hasFailedConnectionAttempt = true
                resolveConnectionWaiters(with: .failure(error))
            }
            await connection.stop()
            if wasCurrentAttempt { scheduleReconnectIfNeeded() }
            throw error
        }
    }

    private func handleSessionEvent(
        _ event: CodexAppServerSessionEvent,
        identifier: UUID,
        generation: UInt64
    ) async {
        let currentSession = activeSession?.identifier == identifier
            && activeSession?.generation == generation
        let connectingSession = connectingIdentifier == identifier
            && connectingGeneration == generation
        guard currentSession || connectingSession else { return }

        switch event {
        case .rateLimitsUpdated:
            emit(
                .refreshRequired(
                    .rateLimitNotification,
                    sessionGeneration: generation
                )
            )

        case .accountUpdated:
            await retireCurrentSessions()
            emit(
                .refreshRequired(
                    .accountChanged,
                    sessionGeneration: generation
                )
            )

        case .disconnected:
            if currentSession { activeSession = nil }
            if connectingSession {
                disconnectedConnectingIdentifiers.insert(identifier)
            }
            advanceGeneration(past: generation)
            if !connectingSession { scheduleReconnectIfNeeded() }
        }
    }

    private func invalidateSession(_ session: ActiveSession) async {
        guard isCurrent(session) else { return }
        activeSession = nil
        advanceGeneration(past: session.generation)
        await session.connection.stop()
        scheduleReconnectIfNeeded()
    }

    private func retireCurrentSessions() async {
        lifecycleGeneration &+= 1
        sessionGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil

        let activeConnection = activeSession?.connection
        let pendingConnection = connectingConnection
        activeSession = nil
        connectingConnection = nil
        connectingIdentifier = nil
        connectingGeneration = nil
        disconnectedConnectingIdentifiers.removeAll()
        isConnecting = false
        resolveConnectionWaiters(with: .failure(CodexAppServerError.stopped))

        if let activeConnection { await activeConnection.stop() }
        if let pendingConnection { await pendingConnection.stop() }
    }

    private func isCurrent(_ session: ActiveSession) -> Bool {
        activeSession?.identifier == session.identifier
            && activeSession?.generation == session.generation
            && sessionGeneration == session.generation
    }

    private func advanceGeneration(past generation: UInt64) {
        if sessionGeneration <= generation { sessionGeneration = generation &+ 1 }
    }

    private func clearConnectingAttempt(identifier: UUID) {
        guard connectingIdentifier == identifier else { return }
        isConnecting = false
        connectingConnection = nil
        connectingIdentifier = nil
        connectingGeneration = nil
        disconnectedConnectingIdentifiers.remove(identifier)
    }

    private func removeEventContinuation(identifier: UUID) {
        eventContinuations.removeValue(forKey: identifier)
    }

    private func emit(_ event: CodexUsageUpdateEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }

    private func resolveConnectionWaiters(
        with result: Result<ActiveSession, Error>
    ) {
        let waiters = connectionWaiters
        connectionWaiters.removeAll()
        waiters.forEach { $0.resume(with: result) }
    }

    private func scheduleReconnectIfNeeded() {
        guard
            !isStopped,
            !eventContinuations.isEmpty,
            reconnectTask == nil
        else {
            return
        }

        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        for delay in [UInt64(1), 5, 15, 60] {
            guard !Task.isCancelled, !isStopped, !eventContinuations.isEmpty else {
                reconnectTask = nil
                return
            }

            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                _ = try await activeSessionOrConnect()
                reconnectTask = nil
                return
            } catch {
                continue
            }
        }

        reconnectTask = nil
        scheduleReconnectIfNeeded()
    }
}

struct MockCodexUsageProvider: CodexUsageSnapshotProviding {
    func fetchSnapshot() async throws -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            accountFingerprint: "mock",
            displaySnapshot: CapsuleDisplaySnapshot(
                items: [
                    CapsuleDisplayItem(
                        kind: .fiveHour,
                        fillPercent: 72,
                        valueText: "72%",
                        accessibilityValue: "72 percent remaining"
                    ),
                    CapsuleDisplayItem(
                        kind: .weekly,
                        fillPercent: 41,
                        valueText: "41%",
                        accessibilityValue: "41 percent remaining"
                    )
                ],
                credits: CreditsDisplayItem(
                    valueText: "500",
                    accessibilityValue: "500 credits"
                )
            ),
            sessionGeneration: 0
        )
    }

    func reconfirmAccountAndFetchSnapshot() async throws -> CodexUsageSnapshot {
        try await fetchSnapshot()
    }
}
