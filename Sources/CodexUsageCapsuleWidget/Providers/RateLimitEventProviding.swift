import Foundation

enum RateLimitRefreshReason: Equatable, Sendable {
    case rateLimitNotification
    case accountChanged
    case appServerReconnected
}

enum RateLimitUpdateEvent: Sendable {
    case refreshRequired(RateLimitRefreshReason)
}

protocol RateLimitEventProviding: Sendable {
    func makeEventStream() async -> AsyncStream<RateLimitUpdateEvent>
    func stopEventMonitoring() async
}
