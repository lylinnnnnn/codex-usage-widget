import Foundation

/// A single, read-only app-server session for the running Capsule widget.
///
/// Notifications never patch the displayed data directly. Each notification
/// instead requests a fresh, complete `account/rateLimits/read`, so the mapper
/// continues to derive display windows and Credits only from complete
/// duration-based data.
actor CodexAppServerLiveRateLimitProvider:
    CapsuleDisplaySnapshotProviding,
    RateLimitEventProviding {
    private struct ActiveSession: Sendable {
        let identifier: UUID
        let connection: CodexAppServerRateLimitConnection
    }

    private let executableURL: URL?
    private let creditPricingProvider: any CreditPricingConfigurationProviding

    private var activeSession: ActiveSession?
    private var connectingConnection: CodexAppServerRateLimitConnection?
    private var connectingSessionIdentifier: UUID?
    private var disconnectedConnectingSessionIdentifiers = Set<UUID>()
    private var isConnecting = false
    private var connectionWaiters: [CheckedContinuation<ActiveSession, Error>] = []
    private var eventContinuations: [
        UUID: AsyncStream<RateLimitUpdateEvent>.Continuation
    ] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var hasConnectedOnce = false
    private var hasFailedConnectionAttempt = false
    private var accountGeneration: UInt64 = 0
    private var isStopped = false
    private var lifecycleGeneration: UInt64 = 0

    init(
        executableURL: URL? = CodexExecutableLocator.locate(),
        creditPricingProvider: any CreditPricingConfigurationProviding =
            CreditPricingConfigurationFileProvider()
    ) {
        self.executableURL = executableURL
        self.creditPricingProvider = creditPricingProvider
    }

    func fetchDisplaySnapshot() async throws -> CapsuleDisplaySnapshot {
        guard !isStopped else {
            throw CodexAppServerRateLimitError.stopped
        }

        while true {
            let session = try await activeSessionOrConnect()
            let generationAtReadStart = accountGeneration
            let readResult: AppServerRateLimitReadResult
            do {
                readResult = try await session.connection.readRateLimits()
            } catch {
                await invalidateSession(identifier: session.identifier)
                throw error
            }

            // The notification has no stable account identity. If it arrived
            // while the request was in flight, discard that response and read
            // again before any old-account values can reach the ViewModel.
            guard accountGeneration == generationAtReadStart else {
                continue
            }

            return try CodexAppServerCapsuleDisplaySnapshotMapper.map(
                readResult,
                creditPricing: creditPricingProvider.loadCreditPricing()
            )
        }
    }

    func makeEventStream() async -> AsyncStream<RateLimitUpdateEvent> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<RateLimitUpdateEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )

        guard !isStopped else {
            continuation.finish()
            return stream
        }

        eventContinuations[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeEventContinuation(identifier: identifier)
            }
        }

        Task { [weak self] in
            await self?.beginEventConnectionIfNeeded()
        }
        return stream
    }

    func stopEventMonitoring() async {
        isStopped = true
        lifecycleGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil

        let continuations = eventContinuations.values
        eventContinuations.removeAll()
        continuations.forEach { $0.finish() }

        let waiters = connectionWaiters
        connectionWaiters.removeAll()
        isConnecting = false
        connectingSessionIdentifier = nil
        disconnectedConnectingSessionIdentifiers.removeAll()
        waiters.forEach { $0.resume(throwing: CodexAppServerRateLimitError.stopped) }

        let activeConnection = activeSession?.connection
        activeSession = nil
        let pendingConnection = connectingConnection
        connectingConnection = nil

        if let activeConnection {
            await activeConnection.stop()
        }
        if let pendingConnection {
            await pendingConnection.stop()
        }
    }

    private func beginEventConnectionIfNeeded() async {
        guard !isStopped, activeSession == nil else { return }

        do {
            _ = try await activeSessionOrConnect()
        } catch {
            // The fallback timer still reads through this provider. If an event
            // session cannot start now, the reconnect loop below will retry.
        }
    }

    private func activeSessionOrConnect() async throws -> ActiveSession {
        if let activeSession {
            return activeSession
        }

        if isConnecting {
            return try await withCheckedThrowingContinuation { continuation in
                connectionWaiters.append(continuation)
            }
        }

        isConnecting = true
        let connectionGeneration = lifecycleGeneration
        let sessionIdentifier = UUID()
        connectingSessionIdentifier = sessionIdentifier
        disconnectedConnectingSessionIdentifiers.remove(sessionIdentifier)

        guard let executableURL else {
            isConnecting = false
            connectingSessionIdentifier = nil
            hasFailedConnectionAttempt = true
            resolveConnectionWaiters(
                with: .failure(CodexAppServerRateLimitError.executableNotFound)
            )
            scheduleReconnectIfNeeded()
            throw CodexAppServerRateLimitError.executableNotFound
        }

        let connection = CodexAppServerRateLimitConnection(
            executableURL: executableURL,
            timeout: 8,
            eventSink: { [weak self] event in
                await self?.handleSessionEvent(
                    event,
                    sessionIdentifier: sessionIdentifier
                )
            }
        )
        connectingConnection = connection

        do {
            try await connection.start()
            guard !isStopped, lifecycleGeneration == connectionGeneration else {
                await connection.stop()
                throw CodexAppServerRateLimitError.stopped
            }
            guard !disconnectedConnectingSessionIdentifiers.contains(
                sessionIdentifier
            ), await connection.isAlive() else {
                await connection.stop()
                throw CodexAppServerRateLimitError.missingResponse
            }

            let session = ActiveSession(
                identifier: sessionIdentifier,
                connection: connection
            )
            activeSession = session
            isConnecting = false
            connectingSessionIdentifier = nil
            connectingConnection = nil
            resolveConnectionWaiters(with: .success(session))

            let didReconnect = hasConnectedOnce || hasFailedConnectionAttempt
            hasConnectedOnce = true
            hasFailedConnectionAttempt = false
            if didReconnect {
                emit(.refreshRequired(.appServerReconnected))
            }
            return session
        } catch {
            isConnecting = false
            connectingSessionIdentifier = nil
            connectingConnection = nil
            disconnectedConnectingSessionIdentifiers.remove(sessionIdentifier)
            hasFailedConnectionAttempt = true
            resolveConnectionWaiters(with: .failure(error))
            await connection.stop()
            scheduleReconnectIfNeeded()
            throw error
        }
    }

    private func invalidateSession(identifier: UUID) async {
        guard let activeSession, activeSession.identifier == identifier else {
            return
        }

        self.activeSession = nil
        await activeSession.connection.stop()
        scheduleReconnectIfNeeded()
    }

    private func handleSessionEvent(
        _ event: CodexAppServerRateLimitSessionEvent,
        sessionIdentifier: UUID
    ) async {
        let isCurrentSession = activeSession?.identifier == sessionIdentifier
        let isConnectingSession = connectingSessionIdentifier == sessionIdentifier
        guard isCurrentSession || isConnectingSession else { return }

        switch event {
        case .rateLimitsUpdated:
            emit(.refreshRequired(.rateLimitNotification))

        case .accountUpdated:
            accountGeneration &+= 1
            emit(.refreshRequired(.accountChanged))

        case .disconnected:
            accountGeneration &+= 1
            if isConnectingSession {
                disconnectedConnectingSessionIdentifiers.insert(sessionIdentifier)
            }
            if isCurrentSession {
                activeSession = nil
            }
            if !isConnectingSession {
                scheduleReconnectIfNeeded()
            }
        }
    }

    private func removeEventContinuation(identifier: UUID) {
        eventContinuations.removeValue(forKey: identifier)
    }

    private func emit(_ event: RateLimitUpdateEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }

    private func resolveConnectionWaiters(
        with result: Result<ActiveSession, Error>
    ) {
        let waiters = connectionWaiters
        connectionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard !isStopped,
              !eventContinuations.isEmpty,
              reconnectTask == nil else {
            return
        }

        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        let delays: [UInt64] = [1, 5, 15, 60]

        for delay in delays {
            guard !Task.isCancelled,
                  !isStopped,
                  !eventContinuations.isEmpty else {
                reconnectTask = nil
                return
            }

            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch {
                reconnectTask = nil
                return
            }

            guard !Task.isCancelled,
                  !isStopped,
                  !eventContinuations.isEmpty else {
                reconnectTask = nil
                return
            }

            do {
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
