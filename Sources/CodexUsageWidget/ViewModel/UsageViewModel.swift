import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    enum Status: Equatable, Sendable {
        case loading
        case available
        case unavailable
    }

    @Published private(set) var displaySnapshot: CapsuleDisplaySnapshot?
    @Published private(set) var status: Status = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    private let snapshotProvider: any CodexUsageSnapshotProviding
    private var refreshPending = false
    private var isReconfirming = false
    private var reconfirmPending = false
    private var confirmedSessionGeneration: UInt64?
    private var invalidatedSessionGeneration: UInt64?
    private var confirmedAccountFingerprint: String?
    private var dataRevision: UInt64 = 0

    init(snapshotProvider: any CodexUsageSnapshotProviding) {
        self.snapshotProvider = snapshotProvider
    }

    func refresh() async {
        if isRefreshing {
            refreshPending = true
            return
        }

        isRefreshing = true
        repeat {
            refreshPending = false
            await refreshOnce()
        } while refreshPending && !Task.isCancelled
        isRefreshing = false
    }

    func refreshForSessionEvent(sessionGeneration: UInt64) async {
        guard shouldAcceptSessionEvent(sessionGeneration) else { return }
        await refresh()
    }

    func reconfirmAccount(sourceGeneration: UInt64? = nil) async {
        guard shouldReconfirm(for: sourceGeneration) else { return }

        invalidateForAccountChange()
        if isReconfirming {
            reconfirmPending = true
            return
        }

        isReconfirming = true
        repeat {
            reconfirmPending = false
            await reconfirmOnce()
        } while reconfirmPending && !Task.isCancelled
        isReconfirming = false
    }

    func invalidateForAccountChange() {
        if let confirmedSessionGeneration {
            invalidatedSessionGeneration = confirmedSessionGeneration
        }
        confirmedSessionGeneration = nil
        confirmedAccountFingerprint = nil
        displaySnapshot = nil
        lastUpdated = nil
        status = .loading
        dataRevision &+= 1
    }

    private func refreshOnce() async {
        if displaySnapshot == nil { status = .loading }
        let revisionAtStart = dataRevision

        do {
            let snapshot = try await snapshotProvider.fetchSnapshot()
            guard
                !Task.isCancelled,
                !isReconfirming,
                dataRevision == revisionAtStart
            else {
                return
            }
            _ = applyReadSnapshot(snapshot)
        } catch {
            guard
                !Task.isCancelled,
                !isReconfirming,
                dataRevision == revisionAtStart
            else {
                return
            }

            // Ordinary transport failures keep the last successful display.
            status = .unavailable
        }
    }

    private func reconfirmOnce() async {
        let revisionAtStart = dataRevision
        do {
            let snapshot = try await snapshotProvider.reconfirmAccountAndFetchSnapshot()
            guard !Task.isCancelled, dataRevision == revisionAtStart else { return }
            guard applyReadSnapshot(snapshot) else {
                throw CodexAppServerError.stopped
            }
        } catch {
            guard !Task.isCancelled, dataRevision == revisionAtStart else { return }
            displaySnapshot = nil
            lastUpdated = nil
            status = .unavailable
            confirmedSessionGeneration = nil
            confirmedAccountFingerprint = nil
            dataRevision &+= 1
        }
    }

    @discardableResult
    private func applyReadSnapshot(_ snapshot: CodexUsageSnapshot) -> Bool {
        guard shouldAcceptReadSnapshot(snapshot) else { return false }

        confirmedSessionGeneration = snapshot.sessionGeneration
        invalidatedSessionGeneration = nil
        confirmedAccountFingerprint = snapshot.accountFingerprint
        displaySnapshot = snapshot.displaySnapshot
        lastUpdated = Date()
        status = .available
        dataRevision &+= 1
        return true
    }

    private func shouldAcceptReadSnapshot(_ snapshot: CodexUsageSnapshot) -> Bool {
        if let confirmedSessionGeneration {
            guard snapshot.sessionGeneration >= confirmedSessionGeneration else {
                return false
            }

            if snapshot.sessionGeneration == confirmedSessionGeneration,
               let confirmedAccountFingerprint,
               let nextFingerprint = snapshot.accountFingerprint,
               nextFingerprint != confirmedAccountFingerprint {
                return false
            }
        }

        if let invalidatedSessionGeneration {
            return snapshot.sessionGeneration > invalidatedSessionGeneration
        }
        return true
    }

    private func shouldAcceptSessionEvent(_ sourceGeneration: UInt64) -> Bool {
        guard !isReconfirming else { return false }
        if let confirmedSessionGeneration {
            return sourceGeneration >= confirmedSessionGeneration
        }
        if let invalidatedSessionGeneration {
            return sourceGeneration > invalidatedSessionGeneration
        }
        return true
    }

    private func shouldReconfirm(for sourceGeneration: UInt64?) -> Bool {
        guard let sourceGeneration else { return true }
        if let confirmedSessionGeneration {
            return sourceGeneration >= confirmedSessionGeneration
        }
        if let invalidatedSessionGeneration {
            return sourceGeneration > invalidatedSessionGeneration
        }
        return true
    }
}
