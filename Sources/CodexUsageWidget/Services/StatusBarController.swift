import AppKit
import Combine
import Foundation

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let viewModel: UsageViewModel
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
    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: UsageViewModel,
        widgetWindowController: WidgetWindowController
    ) {
        self.viewModel = viewModel
        self.widgetWindowController = widgetWindowController
        statusItem = NSStatusBar.system.statusItem(
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
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        usageItem.isEnabled = false
        updatedItem.isEnabled = false
        menu.addItem(usageItem)
        menu.addItem(updatedItem)
        menu.addItem(.separator())

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
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)

        viewModel.$status
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)

        viewModel.$lastUpdated
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)

        viewModel.$isRefreshing
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)
    }

    private func updateMenuState() {
        usageItem.title = usageTitle
        updatedItem.title = updateTitle
        widgetVisibilityItem.title = widgetWindowController.isVisible
            ? "Hide Widget"
            : "Show Widget"
    }

    private var usageTitle: String {
        guard let items = viewModel.displaySnapshot?.items, !items.isEmpty else {
            return "Codex Usage        --"
        }

        let summary = items.map { "\($0.kind.rawValue) \($0.valueText)" }
            .joined(separator: " · ")
        return "Codex Usage        \(summary)"
    }

    private var updateTitle: String {
        if viewModel.isRefreshing {
            return "Updating…"
        }

        switch viewModel.status {
        case .loading:
            return "Waiting for usage data…"
        case .available:
            return updatedTimeTitle(prefix: "Updated")
        case .unavailable:
            guard viewModel.lastUpdated != nil else {
                return "Usage unavailable"
            }
            return updatedTimeTitle(prefix: "Last update failed")
        }
    }

    private func updatedTimeTitle(prefix: String) -> String {
        guard let lastUpdated = viewModel.lastUpdated else {
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

    @objc private func refreshNow() {
        widgetWindowController.refreshNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
