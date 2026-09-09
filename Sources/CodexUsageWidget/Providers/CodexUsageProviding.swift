import Foundation

protocol CodexUsageSnapshotProviding: Sendable {
    func fetchSnapshot() async throws -> CodexUsageSnapshot
    func reconfirmAccountAndFetchSnapshot() async throws -> CodexUsageSnapshot
}

enum CodexUsageRefreshReason: Equatable, Sendable {
    case rateLimitNotification
    case accountChanged
    case appServerReconnected
}

enum CodexUsageUpdateEvent: Sendable {
    case refreshRequired(CodexUsageRefreshReason, sessionGeneration: UInt64)
}

protocol CodexUsageEventProviding: Sendable {
    func makeEventStream() async -> AsyncStream<CodexUsageUpdateEvent>
    func stopEventMonitoring() async
}
