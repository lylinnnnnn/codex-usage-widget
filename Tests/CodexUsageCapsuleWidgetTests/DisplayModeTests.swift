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
        #expect(button.title == "5h -- · W --")
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
        #expect(restoredItem.button?.title == "5h -- · W --")
        #expect(restoredItem.button?.toolTip == "Waiting for usage data…")
        await restored.stop()
    }

    @Test("Absent weekly data is not replaced with monthly usage")
    func missingWeekly() async {
        _ = NSApplication.shared
        let suite = "CapsuleMissingWeeklyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DisplayModeStore(userDefaults: defaults).save(.notchCompact)
        let provider = DisplayProvider()
        await provider.setMonthlySnapshot()
        let window = WidgetWindowController(snapshotProvider: provider, userDefaults: defaults)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let status = StatusBarController(viewModel: window.viewModel, widgetWindowController: window, statusItem: item)
        defer { status.invalidate() }
        await window.viewModel.refresh()
        #expect(item.button?.title == "5h 78% · W --")
        await window.stop()
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

    func failNextRefresh() { shouldFail = true }

    func setMonthlySnapshot() {
        snapshot = CapsuleDisplaySnapshot(items: [
            Self.item(.fiveHour, "78%"), Self.item(.monthly, "90%")
        ])
    }

    private static func makeSnapshot(fiveHour: String, weekly: String) -> CapsuleDisplaySnapshot {
        CapsuleDisplaySnapshot(
            items: [item(.fiveHour, fiveHour), item(.weekly, weekly)],
            credits: CreditsDisplayItem(valueText: "$20 est.", accessibilityValue: "Estimated 20 dollars")
        )
    }

    private static func item(_ kind: CapsuleDisplayKind, _ text: String) -> CapsuleDisplayItem {
        CapsuleDisplayItem(kind: kind, fillPercent: 50, valueText: text, accessibilityValue: text)
    }
}
