import AppKit

@main
struct CodexUsageCapsuleWidgetMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var widgetWindowController: WidgetWindowController?
    private var statusBarController: StatusBarController?
    private var terminationRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = WidgetWindowController()
        widgetWindowController = controller
        statusBarController = StatusBarController(
            viewModel: controller.viewModel,
            widgetWindowController: controller
        )
        controller.start()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateNow }
        terminationRequested = true

        Task { [weak self] in
            self?.statusBarController?.invalidate()
            await self?.widgetWindowController?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
