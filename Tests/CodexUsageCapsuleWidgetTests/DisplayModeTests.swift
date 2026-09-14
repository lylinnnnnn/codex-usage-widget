import AppKit
import Foundation
import Testing
@testable import CodexUsageCapsuleWidget

@Suite("Capsule display modes", .serialized)
@MainActor
struct DisplayModeTests {
    @Test("First launch defaults to Capsules; both modes survive store recreation")
    func persistence() {
        let suite = "CapsuleDisplayModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisplayModeStore(userDefaults: defaults)
        #expect(store.load() == .capsules)
        for mode in DisplayMode.allCases {
            store.save(mode)
            #expect(DisplayModeStore(userDefaults: UserDefaults(suiteName: suite)!).load() == mode)
        }
        defaults.set("unknown", forKey: "codexUsageCapsuleWidget.displayMode")
        #expect(store.load() == .capsules)
    }

    @Test("Menu switches exclusive UIs, preserves details, refreshes and restores compact launch")
    func displayLifecycle() async throws {
        _ = NSApplication.shared
        let suite = "CapsuleDisplayLifecycleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = DisplayProvider()
        let window = WidgetWindowController(snapshotProvider: provider, userDefaults: defaults)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let status = StatusBarController(viewModel: window.viewModel, widgetWindowController: window, statusItem: item)
        defer { status.invalidate() }
        let menu = try #require(item.menu)
        let modes = try #require(menu.item(withTitle: "Display Mode")?.submenu)
        let capsules = try #require(modes.item(withTitle: "Capsules"))
        let compact = try #require(modes.item(withTitle: "Notch Compact"))
        let button = try #require(item.button)

        // A mode can be selected before data arrives, without fabricated values.
        modes.performActionForItem(at: modes.index(of: compact))
        #expect(button.title == "--")
        #expect(button.toolTip == "Waiting for usage data…")
        #expect(!window.isVisible)
        modes.performActionForItem(at: modes.index(of: capsules))
        #expect(window.isVisible)
        #expect(button.title.isEmpty)
        #expect(button.imagePosition == .imageOnly)
        #expect(button.image != nil)
        #expect(capsules.state == .on && compact.state == .off)

        window.start()
        try await waitUntil { window.viewModel.lastUpdated != nil && !window.viewModel.isRefreshing }
        #expect(await provider.fetchCount == 1)
        let firstTimestamp = try #require(window.viewModel.lastUpdated)
        modes.performActionForItem(at: modes.index(of: compact))
        #expect(!window.isVisible)
        #expect(button.title == "5h 78% · W 64%")
        #expect(button.imagePosition == .noImage)
        #expect(item.length == NSStatusItem.variableLength)
        #expect(compact.state == .on && capsules.state == .off)
        #expect(item.menu === menu)
        #expect(menu.item(withTitle: "Credits $20 est.")?.isHidden == false)
        #expect(menu.items.contains { $0.title.contains("5h 78% · Weekly 64%") })
        #expect(menu.item(withTitle: "Show Widget")?.isHidden == true)
        window.toggleVisibility()
        #expect(!window.isVisible)
        #expect(button.toolTip == expectedTooltip(firstTimestamp))

        await provider.setSnapshot(fiveHour: "77%", weekly: "63%")
        let refresh = try #require(menu.item(withTitle: "Refresh Now"))
        menu.performActionForItem(at: menu.index(of: refresh))
        try await waitUntil { button.title == "5h 77% · W 63%" && !window.viewModel.isRefreshing }
        let nextTimestamp = try #require(window.viewModel.lastUpdated)
        #expect(nextTimestamp >= firstTimestamp)
        #expect(button.toolTip == expectedTooltip(nextTimestamp))
        #expect(await provider.fetchCount == 2)
        #expect(!window.isVisible)

        await provider.failNextRefresh()
        menu.performActionForItem(at: menu.index(of: refresh))
        try await waitUntil { window.viewModel.status == .unavailable && !window.viewModel.isRefreshing }
        #expect(button.title == "5h 77% · W 63%")
        #expect(button.toolTip == expectedTooltip(nextTimestamp))
        #expect(window.viewModel.lastUpdated == nextTimestamp)

        modes.performActionForItem(at: modes.index(of: capsules))
        #expect(window.isVisible)
        #expect(button.title.isEmpty)
        #expect(button.imagePosition == .imageOnly)
        #expect(item.length == NSStatusItem.squareLength)
        #expect(capsules.state == .on && compact.state == .off)
        #expect(menu.item(withTitle: "Hide Widget")?.isHidden == false)
        #expect(window.viewModel.displaySnapshot?.items.map(\.valueText) == ["77%", "63%"])
        modes.performActionForItem(at: modes.index(of: compact))
        #expect(await provider.fetchCount == 3) // Switching never starts a fetch.
        await window.stop()

        let restored = WidgetWindowController(snapshotProvider: provider, userDefaults: UserDefaults(suiteName: suite)!)
        let restoredItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let restoredStatus = StatusBarController(viewModel: restored.viewModel, widgetWindowController: restored, statusItem: restoredItem)
        defer { restoredStatus.invalidate() }
        #expect(restored.displayMode == .notchCompact)
        restored.start()
        #expect(!restored.isVisible)
        try await waitUntil { restored.viewModel.lastUpdated != nil && !restored.viewModel.isRefreshing }
        #expect(restoredItem.button?.title == "5h 77% · W 63%")
        #expect(await provider.fetchCount == 4)

        // Account invalidation must clear the previous account's title and time.
        restored.viewModel.invalidateForAccountChange()
        #expect(restoredItem.button?.title == "--")
        #expect(restoredItem.button?.toolTip == "Waiting for usage data…")
        await restored.stop()
    }

    @Test("Compact renders the available usage windows without empty slots")
    func compactUsageWindows() async throws {
        _ = NSApplication.shared
        let suite = "CapsuleCompactUsageWindowsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DisplayModeStore(userDefaults: defaults).save(.notchCompact)
        let provider = DisplayProvider()
        let window = WidgetWindowController(snapshotProvider: provider, userDefaults: defaults)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let status = StatusBarController(viewModel: window.viewModel, widgetWindowController: window, statusItem: item)
        defer { status.invalidate() }
        let button = try #require(item.button)
        let menu = try #require(item.menu)

        let cases: [(windows: [(duration: Int, usedPercent: Double)], title: String)] = [
            (
                [(duration: 300, usedPercent: 22), (duration: 10_080, usedPercent: 36)],
                "5h 78% · W 64%"
            ),
            ([(duration: 300, usedPercent: 22)], "5h 78%"),
            ([(duration: 10_080, usedPercent: 36)], "W 64%"),
            ([(duration: 43_200, usedPercent: 18)], "M 82%"),
            ([(duration: 1_440, usedPercent: 50)], "1d 50%"),
            (
                [(duration: 300, usedPercent: 22), (duration: 43_200, usedPercent: 18)],
                "5h 78% · M 82%"
            )
        ]

        for scenario in cases {
            let snapshot = try #require(
                CapsuleDisplaySnapshotMapper.map(
                    CapsuleDisplayPayload(
                        windows: scenario.windows.map {
                            RateLimitWindowPayload(
                                windowDurationMins: $0.duration,
                                usedPercent: $0.usedPercent,
                                resetsAt: nil
                            )
                        },
                        credits: nil
                    )
                )
            )
            await provider.setSnapshot(items: snapshot.items)
            await window.viewModel.refresh()

            #expect(button.title == scenario.title)
            #expect(button.title.contains("·") == (scenario.windows.count > 1))
            #expect(item.length == NSStatusItem.variableLength)
        }

        let appServerMonthlyOnly = try CodexAppServerCapsuleDisplaySnapshotMapper.map(
            AppServerRateLimitReadResult(
                rateLimits: AppServerRateLimits(
                    limitId: "codex",
                    primary: AppServerRateLimitWindow(
                        usedPercent: 18,
                        windowDurationMins: 43_200,
                        resetsAt: nil
                    ),
                    secondary: nil,
                    credits: nil
                ),
                rateLimitsByLimitId: nil
            )
        )
        await provider.setSnapshot(appServerMonthlyOnly)
        await window.viewModel.refresh()
        #expect(button.title == "M 82%")

        await provider.setSnapshot(items: [])
        await window.viewModel.refresh()
        #expect(button.title == "--")
        #expect(!button.title.contains("·"))
        #expect(item.length == NSStatusItem.variableLength)

        let creditsOnly = try #require(
            CapsuleDisplaySnapshotMapper.map(
                CapsuleDisplayPayload(
                    windows: [],
                    credits: WorkspaceCreditBalancePayload(
                        balance: nil,
                        hasCredits: true,
                        unlimited: true
                    )
                )
            )
        )
        await provider.setSnapshot(creditsOnly)
        await window.viewModel.refresh()
        #expect(button.title == "--")
        #expect(menu.item(withTitle: "Credits ∞")?.isHidden == false)

        await window.stop()
    }

    @Test("Account changes replace compact windows without retaining old values")
    func accountChangesReplaceCompactWindows() async throws {
        _ = NSApplication.shared
        let suite = "CapsuleAccountSwitchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DisplayModeStore(userDefaults: defaults).save(.notchCompact)

        let accountA = DisplayProvider.snapshot(items: [
            DisplayProvider.item(.fiveHour, "78%"),
            DisplayProvider.item(.weekly, "64%")
        ])
        let accountB = DisplayProvider.snapshot(items: [
            DisplayProvider.item(.monthly, "82%")
        ])
        let provider = AccountSwitchingDisplayProvider(snapshot: accountA)
        let window = WidgetWindowController(snapshotProvider: provider, userDefaults: defaults)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let status = StatusBarController(viewModel: window.viewModel, widgetWindowController: window, statusItem: item)
        defer { status.invalidate() }
        let button = try #require(item.button)

        do {
            window.start()
            try await waitUntil {
                button.title == "5h 78% · W 64%" && !window.viewModel.isRefreshing
            }

            await provider.setSnapshot(accountB)
            await provider.holdNextFetch()
            await provider.emitAccountChange()
            try await waitUntilFetchIsHeld(provider)
            try await waitUntil {
                button.title == "--"
                    && button.toolTip == "Waiting for usage data…"
                    && window.viewModel.isRefreshing
            }
            await provider.resumeFetch()
            try await waitUntil {
                button.title == "M 82%" && !window.viewModel.isRefreshing
            }

            await provider.setSnapshot(accountA)
            await provider.holdNextFetch()
            await provider.emitAccountChange()
            try await waitUntilFetchIsHeld(provider)
            try await waitUntil {
                button.title == "--"
                    && button.toolTip == "Waiting for usage data…"
                    && window.viewModel.isRefreshing
            }
            await provider.resumeFetch()
            try await waitUntil {
                button.title == "5h 78% · W 64%" && !window.viewModel.isRefreshing
            }

            await window.stop()
        } catch {
            await window.stop()
            throw error
        }
    }

    private func expectedTooltip(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "Updated \(formatter.string(from: timestamp))"
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "Timed out waiting for the existing refresh pipeline")
    }

    private func waitUntilFetchIsHeld(
        _ provider: AccountSwitchingDisplayProvider
    ) async throws {
        for _ in 0..<200 {
            if await provider.isFetchHeld() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let isHeld = await provider.isFetchHeld()
        #expect(isHeld, "Timed out waiting for the account refresh read to start")
    }
}

private actor DisplayProvider: CapsuleDisplaySnapshotProviding {
    private(set) var fetchCount = 0
    private var shouldFail = false
    private var snapshot = makeSnapshot(fiveHour: "78%", weekly: "64%")

    func fetchDisplaySnapshot() async throws -> CapsuleDisplaySnapshot {
        fetchCount += 1
        if shouldFail {
            shouldFail = false
            throw URLError(.notConnectedToInternet)
        }
        return snapshot
    }

    func setSnapshot(fiveHour: String, weekly: String) {
        snapshot = Self.makeSnapshot(fiveHour: fiveHour, weekly: weekly)
    }

    func setSnapshot(items: [CapsuleDisplayItem]) {
        snapshot = Self.snapshot(items: items)
    }

    func setSnapshot(_ snapshot: CapsuleDisplaySnapshot) {
        self.snapshot = snapshot
    }

    func failNextRefresh() { shouldFail = true }

    private static func makeSnapshot(fiveHour: String, weekly: String) -> CapsuleDisplaySnapshot {
        CapsuleDisplaySnapshot(
            items: [item(.fiveHour, fiveHour), item(.weekly, weekly)],
            credits: CreditsDisplayItem(valueText: "$20 est.", accessibilityValue: "Estimated 20 dollars")
        )
    }

    nonisolated static func snapshot(items: [CapsuleDisplayItem]) -> CapsuleDisplaySnapshot {
        CapsuleDisplaySnapshot(items: items)
    }

    nonisolated static func item(_ kind: CapsuleDisplayKind, _ text: String) -> CapsuleDisplayItem {
        CapsuleDisplayItem(kind: kind, fillPercent: 50, valueText: text, accessibilityValue: text)
    }
}

private actor AccountSwitchingDisplayProvider:
    CapsuleDisplaySnapshotProviding,
    RateLimitEventProviding {
    private var snapshot: CapsuleDisplaySnapshot
    private var eventContinuation: AsyncStream<RateLimitUpdateEvent>.Continuation?
    private var shouldHoldNextFetch = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: CapsuleDisplaySnapshot) {
        self.snapshot = snapshot
    }

    func fetchDisplaySnapshot() async throws -> CapsuleDisplaySnapshot {
        if shouldHoldNextFetch {
            shouldHoldNextFetch = false
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
            }
        }
        return snapshot
    }

    func makeEventStream() async -> AsyncStream<RateLimitUpdateEvent> {
        let (stream, continuation) = AsyncStream<RateLimitUpdateEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        eventContinuation = continuation
        return stream
    }

    func stopEventMonitoring() async {
        eventContinuation?.finish()
        eventContinuation = nil
        fetchContinuation?.resume()
        fetchContinuation = nil
    }

    func setSnapshot(_ snapshot: CapsuleDisplaySnapshot) {
        self.snapshot = snapshot
    }

    func holdNextFetch() {
        shouldHoldNextFetch = true
    }

    func isFetchHeld() -> Bool {
        fetchContinuation != nil
    }

    func resumeFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }

    func emitAccountChange() {
        eventContinuation?.yield(.refreshRequired(.accountChanged))
    }
}
