import Foundation

protocol RateLimitSnapshotProviding: Sendable {
    func fetchSnapshot() async throws -> RateLimitSnapshot
}

protocol CapsuleDisplaySnapshotProviding: Sendable {
    func fetchDisplaySnapshot() async throws -> CapsuleDisplaySnapshot
}
