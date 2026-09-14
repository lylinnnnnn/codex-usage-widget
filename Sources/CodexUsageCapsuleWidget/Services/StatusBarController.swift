import AppKit
import Combine
import Foundation

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let viewModel: RateLimitSnapshotViewModel
    private let widgetWindowController: WidgetWindowController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let usageItem = NSMenuItem(
        title: "Codex Usage        --",
        action: nil,
        keyEquivalent: ""
    )
    private let updatedItem = NSMenuItem(
        title: "Waiting for usage data…",
        action: nil,
        keyEquivalent: ""
    )
    private let widgetVisibilityItem = NSMenuItem()
    private let creditsItem = NSMenuItem(title: "Credits --", action: nil, keyEquivalent: "")
    private var displayModeItems: [DisplayMode: NSMenuItem] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let compactPillView = CompactStatusPillView(frame: .zero)

    init(
        viewModel: RateLimitSnapshotViewModel,
        widgetWindowController: WidgetWindowController,
        statusItem: NSStatusItem? = nil
    ) {
        self.viewModel = viewModel
        self.widgetWindowController = widgetWindowController
        self.statusItem = statusItem ?? NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        super.init()

        configureStatusItem()
        configureMenu()
        bindUsageState()
    }

    func invalidate() {
        cancellables.removeAll()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuState()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 7,
            weight: .regular,
            scale: .medium
        )
        let image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "Codex Usage"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Codex Usage"
        compactPillView.frame = button.bounds
        compactPillView.isHidden = true
        button.addSubview(compactPillView)
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        usageItem.isEnabled = false
        updatedItem.isEnabled = false
        menu.addItem(usageItem)
        menu.addItem(updatedItem)
        creditsItem.isEnabled = false
        menu.addItem(creditsItem)
        menu.addItem(.separator())

        let displayModeMenu = NSMenu(title: "Display Mode")
        let displayModeItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        displayModeItem.submenu = displayModeMenu
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            displayModeItems[mode] = item
            displayModeMenu.addItem(item)
        }
        menu.addItem(displayModeItem)

        widgetVisibilityItem.target = self
        widgetVisibilityItem.action = #selector(toggleWidgetVisibility)
        menu.addItem(widgetVisibilityItem)

        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Codex Usage",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        updateMenuState()
    }

    private func bindUsageState() {
        viewModel.$displaySnapshot
            .combineLatest(viewModel.$status, viewModel.$lastUpdated, viewModel.$isRefreshing)
            .sink { [weak self] snapshot, status, lastUpdated, isRefreshing in
                // @Published emits before storage changes; render the emitted
                // values so the compact title and timestamp never lag a refresh.
                self?.updateUsageState(
                    snapshot: snapshot,
                    status: status,
                    lastUpdated: lastUpdated,
                    isRefreshing: isRefreshing
                )
            }
            .store(in: &cancellables)
    }

    private func updateMenuState() {
        updateUsageState(
            snapshot: viewModel.displaySnapshot,
            status: viewModel.status,
            lastUpdated: viewModel.lastUpdated,
            isRefreshing: viewModel.isRefreshing
        )
        let mode = widgetWindowController.displayMode
        for (itemMode, item) in displayModeItems {
            item.state = itemMode == mode ? .on : .off
        }
        // Showing the floating panel would violate compact mode exclusivity.
        widgetVisibilityItem.isHidden = mode == .notchCompact
        widgetVisibilityItem.title = widgetWindowController.isVisible
            ? "Hide Widget"
            : "Show Widget"
    }

    private func updateUsageState(
        snapshot: CapsuleDisplaySnapshot?,
        status: RateLimitSnapshotViewModel.Status,
        lastUpdated: Date?,
        isRefreshing: Bool
    ) {
        usageItem.title = usageTitle(snapshot: snapshot)
        updatedItem.title = updateTitle(status: status, lastUpdated: lastUpdated, isRefreshing: isRefreshing)
        creditsItem.title = "Credits \(snapshot?.credits?.valueText ?? "--")"
        creditsItem.isHidden = snapshot?.credits == nil

        guard let button = statusItem.button else { return }
        if widgetWindowController.displayMode == .notchCompact {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .noImage
            button.font = CompactStatusPillView.font
            button.title = compactUsageTitle(snapshot: snapshot)
            compactPillView.title = button.title
            compactPillView.emphasizedLabels = snapshot?.items.map {
                $0.kind.compactLabel
            } ?? []
            // Keep the native title for intrinsic sizing and accessibility;
            // the non-interactive decoration renders its visible counterpart.
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [.font: CompactStatusPillView.font, .foregroundColor: NSColor.clear]
            )
            compactPillView.isHidden = false
            button.toolTip = compactTooltip(lastUpdated: lastUpdated)
        } else {
            compactPillView.isHidden = true
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Codex Usage"
            statusItem.length = NSStatusItem.squareLength
        }
    }

    private func compactUsageTitle(snapshot: CapsuleDisplaySnapshot?) -> String {
        guard let items = snapshot?.items, !items.isEmpty else {
            return "--"
        }
        return items.map(\.compactText).joined(separator: " · ")
    }

    private func compactTooltip(lastUpdated: Date?) -> String {
        guard let lastUpdated else { return "Waiting for usage data…" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    private func usageTitle(snapshot: CapsuleDisplaySnapshot?) -> String {
        guard let items = snapshot?.items, !items.isEmpty else {
            return "Codex Usage        --"
        }

        let summary = items.map { "\($0.kind.displayLabel) \($0.valueText)" }
            .joined(separator: " · ")
        return "Codex Usage        \(summary)"
    }

    private func updateTitle(
        status: RateLimitSnapshotViewModel.Status,
        lastUpdated: Date?,
        isRefreshing: Bool
    ) -> String {
        if isRefreshing {
            return "Updating…"
        }

        switch status {
        case .loading:
            return "Waiting for usage data…"
        case .available:
            return updatedTimeTitle(prefix: "Updated", lastUpdated: lastUpdated)
        case .unavailable:
            guard lastUpdated != nil else {
                return "Usage unavailable"
            }
            return updatedTimeTitle(prefix: "Last update failed", lastUpdated: lastUpdated)
        }
    }

    private func updatedTimeTitle(prefix: String, lastUpdated: Date?) -> String {
        guard let lastUpdated else {
            return prefix
        }
        let time = DateFormatter.localizedString(
            from: lastUpdated,
            dateStyle: .none,
            timeStyle: .short
        )
        return "\(prefix) \(time)"
    }

    @objc private func toggleWidgetVisibility() {
        widgetWindowController.toggleVisibility()
        updateMenuState()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: rawValue) else { return }
        widgetWindowController.setDisplayMode(mode)
        updateMenuState()
    }

    @objc private func refreshNow() {
        widgetWindowController.refreshNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
