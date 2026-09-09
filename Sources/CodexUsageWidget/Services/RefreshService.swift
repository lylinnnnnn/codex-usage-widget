import AppKit
import Foundation

@MainActor
final class RefreshService {
    private let viewModel: UsageViewModel
    private let refreshInterval: TimeInterval
    private let eventProvider: (any CodexUsageEventProviding)?
    private var refreshTimer: Timer?
    private var eventTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    init(
        viewModel: UsageViewModel,
        refreshInterval: TimeInterval = 60,
        eventProvider: (any CodexUsageEventProviding)? = nil
    ) {
        self.viewModel = viewModel
        self.refreshInterval = refreshInterval
        self.eventProvider = eventProvider
    }

    func start() {
        guard refreshTimer == nil else { return }

        installWakeObserver()
        installActivationObserver()
        beginEventMonitoringAndInitialRefresh()

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() async {
        refreshTimer?.invalidate()
        refreshTimer = nil
        eventTask?.cancel()
        eventTask = nil

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let eventProvider { await eventProvider.stopEventMonitoring() }
    }

    func refreshNow() {
        Task { [viewModel] in await viewModel.refresh() }
    }

    func reconfirmNow() {
        Task { [viewModel] in await viewModel.reconfirmAccount() }
    }

    private func beginEventMonitoringAndInitialRefresh() {
        guard let eventProvider else {
            refreshNow()
            return
        }

        eventTask = Task { [weak self, eventProvider] in
            let events = await eventProvider.makeEventStream()
            guard let self, !Task.isCancelled else { return }
            self.refreshNow()

            for await event in events {
                guard !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: CodexUsageUpdateEvent) {
        switch event {
        case let .refreshRequired(reason, sessionGeneration):
            if reason == .accountChanged {
                Task { [viewModel] in
                    await viewModel.reconfirmAccount(
                        sourceGeneration: sessionGeneration
                    )
                }
            } else {
                Task { [viewModel] in
                    await viewModel.refreshForSessionEvent(
                        sessionGeneration: sessionGeneration
                    )
                }
            }
        }
    }

    private func installWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconfirmNow() }
        }
    }

    private func installActivationObserver() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconfirmNow() }
        }
    }
}
