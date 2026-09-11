import Combine
import Foundation

@MainActor
final class RateLimitSnapshotViewModel: ObservableObject {
    enum Status: Equatable, Sendable {
        case loading
        case available
        case unavailable
    }

    @Published private(set) var displaySnapshot: CapsuleDisplaySnapshot?
    @Published private(set) var status: Status = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    private let snapshotProvider: any CapsuleDisplaySnapshotProviding
    private var refreshPending = false
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskID: UInt64 = 0
    private var snapshotGeneration: UInt64 = 0

    init(snapshotProvider: any CapsuleDisplaySnapshotProviding) {
        self.snapshotProvider = snapshotProvider
    }

    func requestRefresh() {
        guard refreshTask == nil else {
            refreshPending = true
            return
        }

        refreshTaskID &+= 1
        let taskID = refreshTaskID
        refreshTask = Task { [weak self] in
            await self?.refresh()
            guard let self, self.refreshTaskID == taskID else { return }
            self.refreshTask = nil
        }
    }

    func refresh() async {
        if isRefreshing {
            refreshPending = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            guard !Task.isCancelled else { return }

            refreshPending = false
            await refreshOnce()
        } while refreshPending && !Task.isCancelled
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID &+= 1
        refreshPending = false
        isRefreshing = false
    }

    func invalidateForAccountChange() {
        snapshotGeneration &+= 1
        displaySnapshot = nil
        lastUpdated = nil
        status = .loading
    }

    private func refreshOnce() async {
        if displaySnapshot == nil {
            status = .loading
        }
        let generationAtStart = snapshotGeneration

        do {
            let nextSnapshot = try await snapshotProvider.fetchDisplaySnapshot()
            guard !Task.isCancelled,
                  snapshotGeneration == generationAtStart else {
                return
            }

            displaySnapshot = nextSnapshot
            lastUpdated = Date()
            status = .available
        } catch {
            guard !Task.isCancelled,
                  snapshotGeneration == generationAtStart else {
                return
            }

            // A later refresh must not make a previously usable widget blank.
            // When no data has ever loaded, both properties are already nil and
            // the unavailable placeholder remains the correct initial state.
            status = .unavailable
        }
    }
}
