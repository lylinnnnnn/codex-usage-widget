import AppKit
import Combine
import SwiftUI

@MainActor
final class WidgetWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let positionStore: CapsuleWindowPositionStore
    private let refreshService: RateLimitRefreshService
    let viewModel: RateLimitSnapshotViewModel
    private var hasShownPanel = false
    private var sizeCancellable: AnyCancellable?

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        let snapshotProvider = CodexAppServerLiveRateLimitProvider()
        let viewModel = RateLimitSnapshotViewModel(
            snapshotProvider: snapshotProvider
        )
        self.viewModel = viewModel
        positionStore = CapsuleWindowPositionStore()
        refreshService = RateLimitRefreshService(
            viewModel: viewModel,
            eventProvider: snapshotProvider
        )
        panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: WidgetView.Metrics.windowWidth,
                    height: WidgetView.Metrics.windowHeight(hasCredits: false)
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel()
        bindPanelSize()
    }

    func show() {
        if !hasShownPanel {
            panel.setFrameOrigin(
                positionStore.restoredOrigin(for: panel.frame.size)
            )
            hasShownPanel = true
        }
        panel.orderFrontRegardless()
        refreshService.start()
#if DEBUG
        print(
            "CodexUsageCapsuleWidget ready "
                + "frame=\(panel.frame) visible=\(panel.isVisible)"
        )
#endif
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    func refreshNow() {
        refreshService.refreshNow()
    }

    func stop() async {
        panel.orderOut(nil)
        await refreshService.stop()
    }

    func windowDidMove(_ notification: Notification) {
        let usageOnlyOrigin = NSPoint(
            x: panel.frame.origin.x,
            y: panel.frame.maxY - WidgetView.Metrics.usageAreaHeight
        )
        positionStore.save(origin: usageOnlyOrigin)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "Codex Usage Capsule Widget"
        panel.setAccessibilityLabel("Codex Usage Capsule Widget")
        panel.setAccessibilityHelp("Floating Codex usage widget")
        panel.setAccessibilityIdentifier("CodexUsageCapsuleWidgetPanel")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.contentView = DraggableHostingView(
            rootView: WidgetView(viewModel: viewModel)
        )
    }

    private func bindPanelSize() {
        sizeCancellable = viewModel.$displaySnapshot
            .map { $0?.credits != nil }
            .removeDuplicates()
            .sink { [weak self] hasCredits in
                self?.updatePanelHeight(hasCredits: hasCredits)
            }
    }

    private func updatePanelHeight(hasCredits: Bool) {
        let targetHeight = WidgetView.Metrics.windowHeight(
            hasCredits: hasCredits
        )
        guard panel.frame.height != targetHeight else { return }

        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = topEdge - targetHeight
        panel.setFrame(frame, display: panel.isVisible)
    }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
