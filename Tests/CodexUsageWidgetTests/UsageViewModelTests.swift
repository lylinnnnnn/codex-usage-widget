import Foundation
import Testing
@testable import CodexUsageWidget

@Suite("Usage view model")
struct UsageViewModelTests {
    @MainActor
    @Test("Ordinary failure keeps the last successful display")
    func staleRetention() async {
        let first = snapshot(value: 80, generation: 1, fingerprint: "account-a")
        let provider = TestUsageProvider(
            fetchResults: [.success(first), .failure(.missingResponse)],
            reconfirmResults: []
        )
        let viewModel = UsageViewModel(snapshotProvider: provider)

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(viewModel.displaySnapshot?.items.first?.valueText == "80%")
        #expect(viewModel.status == .unavailable)
        #expect(viewModel.lastUpdated != nil)
    }

    @MainActor
    @Test("Reconfirm replaces account and generation")
    func reconfirmSuccess() async {
        let first = snapshot(value: 80, generation: 1, fingerprint: "account-a")
        let second = snapshot(value: 25, generation: 2, fingerprint: "account-b")
        let provider = TestUsageProvider(
            fetchResults: [.success(first)],
            reconfirmResults: [.success(second)]
        )
        let viewModel = UsageViewModel(snapshotProvider: provider)

        await viewModel.refresh()
        await viewModel.reconfirmAccount()

        #expect(viewModel.displaySnapshot?.items.first?.valueText == "25%")
        #expect(viewModel.status == .available)
        #expect(await provider.counts().reconfirm == 1)
    }

    @MainActor
    @Test("Reconfirm failure clears old account data")
    func reconfirmFailure() async {
        let first = snapshot(value: 80, generation: 1, fingerprint: "account-a")
        let provider = TestUsageProvider(
            fetchResults: [.success(first)],
            reconfirmResults: [.failure(.missingResponse)]
        )
        let viewModel = UsageViewModel(snapshotProvider: provider)

        await viewModel.refresh()
        await viewModel.reconfirmAccount()

        #expect(viewModel.displaySnapshot == nil)
        #expect(viewModel.lastUpdated == nil)
        #expect(viewModel.status == .unavailable)
    }

    @MainActor
    @Test("Old-generation responses and events are ignored")
    func oldGenerationProtection() async {
        let current = snapshot(value: 25, generation: 2, fingerprint: "account-b")
        let delayed = snapshot(value: 80, generation: 1, fingerprint: "account-a")
        let provider = TestUsageProvider(
            fetchResults: [.success(current), .success(delayed)],
            reconfirmResults: []
        )
        let viewModel = UsageViewModel(snapshotProvider: provider)

        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refreshForSessionEvent(sessionGeneration: 1)

        #expect(viewModel.displaySnapshot?.items.first?.valueText == "25%")
        #expect(await provider.counts().fetch == 2)
    }

    @MainActor
    @Test("A delayed account event cannot trigger another reconfirmation")
    func delayedAccountEventProtection() async {
        let first = snapshot(value: 80, generation: 1, fingerprint: "account-a")
        let second = snapshot(value: 25, generation: 2, fingerprint: "account-b")
        let provider = TestUsageProvider(
            fetchResults: [.success(first)],
            reconfirmResults: [.success(second)]
        )
        let viewModel = UsageViewModel(snapshotProvider: provider)

        await viewModel.refresh()
        await viewModel.reconfirmAccount(sourceGeneration: 1)
        await viewModel.reconfirmAccount(sourceGeneration: 1)

        #expect(viewModel.displaySnapshot?.items.first?.valueText == "25%")
        #expect(await provider.counts().reconfirm == 1)
    }

    private func snapshot(
        value: Double,
        generation: UInt64,
        fingerprint: String
    ) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            accountFingerprint: fingerprint,
            displaySnapshot: CapsuleDisplaySnapshot(
                items: [
                    CapsuleDisplayItem(
                        kind: .fiveHour,
                        fillPercent: value,
                        valueText: "\(Int(value))%",
                        accessibilityValue: "\(Int(value)) percent remaining"
                    )
                ]
            ),
            sessionGeneration: generation
        )
    }
}

private actor TestUsageProvider: CodexUsageSnapshotProviding {
    private var fetchResults: [Result<CodexUsageSnapshot, CodexAppServerError>]
    private var reconfirmResults: [Result<CodexUsageSnapshot, CodexAppServerError>]
    private var fetchCount = 0
    private var reconfirmCount = 0

    init(
        fetchResults: [Result<CodexUsageSnapshot, CodexAppServerError>],
        reconfirmResults: [Result<CodexUsageSnapshot, CodexAppServerError>]
    ) {
        self.fetchResults = fetchResults
        self.reconfirmResults = reconfirmResults
    }

    func fetchSnapshot() async throws -> CodexUsageSnapshot {
        fetchCount += 1
        guard !fetchResults.isEmpty else { throw CodexAppServerError.missingResponse }
        return try fetchResults.removeFirst().get()
    }

    func reconfirmAccountAndFetchSnapshot() async throws -> CodexUsageSnapshot {
        reconfirmCount += 1
        guard !reconfirmResults.isEmpty else {
            throw CodexAppServerError.missingResponse
        }
        return try reconfirmResults.removeFirst().get()
    }

    func counts() -> (fetch: Int, reconfirm: Int) {
        (fetchCount, reconfirmCount)
    }
}
