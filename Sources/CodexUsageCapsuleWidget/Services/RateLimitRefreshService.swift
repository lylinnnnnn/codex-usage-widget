import AppKit
import Foundation

@MainActor
final class RateLimitRefreshService {
    private let viewModel: RateLimitSnapshotViewModel
    private let refreshInterval: TimeInterval
    private let eventProvider: (any RateLimitEventProviding)?
    private var refreshTimer: Timer?
    private var eventTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(
        viewModel: RateLimitSnapshotViewModel,
        refreshInterval: TimeInterval = 60,
        eventProvider: (any RateLimitEventProviding)? = nil
    ) {
        self.viewModel = viewModel
        self.refreshInterval = refreshInterval
        self.eventProvider = eventProvider
    }

    func start() {
        guard refreshTimer == nil else { return }

        installWakeObserver()
        beginEventMonitoringAndInitialRefresh()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak viewModel] _ in
            Task { @MainActor in
                viewModel?.requestRefresh()
            }
        }
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

        viewModel.stopRefreshing()
        if let eventProvider {
            await eventProvider.stopEventMonitoring()
        }
    }

    func refreshNow() {
        viewModel.requestRefresh()
    }

    private func beginEventMonitoringAndInitialRefresh() {
        guard let eventProvider else {
            viewModel.requestRefresh()
            return
        }

        eventTask = Task { [weak self, eventProvider] in
            let events = await eventProvider.makeEventStream()
            guard let self, !Task.isCancelled else { return }

            // Register before the startup read. That way a rate-limit change
            // between session setup and the first read becomes a queued follow-up
            // instead of a missed update.
            self.viewModel.requestRefresh()

            for await event in events {
                guard !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    private func installWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak viewModel] _ in
            Task { @MainActor in
                viewModel?.requestRefresh()
            }
        }
    }

    private func handle(_ event: RateLimitUpdateEvent) {
        switch event {
        case let .refreshRequired(reason):
            if reason == .accountChanged {
                viewModel.invalidateForAccountChange()
            }
            viewModel.requestRefresh()
        }
    }
}
