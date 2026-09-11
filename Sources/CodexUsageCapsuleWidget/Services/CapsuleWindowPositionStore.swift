import AppKit

struct CapsuleWindowPositionStore {
    private enum Key {
        static let x = "codexUsageCapsuleWidget.position.x"
        static let y = "codexUsageCapsuleWidget.position.y"
    }

    private let userDefaults: UserDefaults
    private let visibleFrames: () -> [NSRect]

    init(
        userDefaults: UserDefaults = .standard,
        visibleFrames: @escaping () -> [NSRect] = Self.currentVisibleFrames
    ) {
        self.userDefaults = userDefaults
        self.visibleFrames = visibleFrames
    }

    func save(origin: NSPoint) {
        guard origin.x.isFinite, origin.y.isFinite else { return }

        userDefaults.set(origin.x, forKey: Key.x)
        userDefaults.set(origin.y, forKey: Key.y)
    }

    func restoredOrigin(for windowSize: NSSize) -> NSPoint {
        let frames = visibleFrames()
        let fallbackFrame = frames.first ?? Self.fallbackVisibleFrame
        let origin = savedOrigin ?? defaultOrigin(
            for: windowSize,
            in: fallbackFrame
        )
        let targetFrame = visibleFrame(
            for: origin,
            windowSize: windowSize,
            among: frames
        ) ?? fallbackFrame

        return clamped(
            origin,
            to: targetFrame,
            windowSize: windowSize
        )
    }

    private var savedOrigin: NSPoint? {
        guard userDefaults.object(forKey: Key.x) != nil,
              userDefaults.object(forKey: Key.y) != nil else {
            return nil
        }

        let origin = NSPoint(
            x: userDefaults.double(forKey: Key.x),
            y: userDefaults.double(forKey: Key.y)
        )
        guard origin.x.isFinite, origin.y.isFinite else { return nil }
        return origin
    }

    private func defaultOrigin(
        for windowSize: NSSize,
        in visibleFrame: NSRect
    ) -> NSPoint {
        let proposed = NSPoint(
            x: visibleFrame.maxX - windowSize.width - 28,
            y: visibleFrame.maxY - windowSize.height - 72
        )
        return clamped(proposed, to: visibleFrame, windowSize: windowSize)
    }

    private func visibleFrame(
        for origin: NSPoint,
        windowSize: NSSize,
        among frames: [NSRect]
    ) -> NSRect? {
        let proposedFrame = NSRect(origin: origin, size: windowSize)
        guard let bestFrame = frames.max(by: { first, second in
            intersectionArea(first, proposedFrame)
                < intersectionArea(second, proposedFrame)
        }), intersectionArea(bestFrame, proposedFrame) > 0 else {
            return nil
        }

        return bestFrame
    }

    private func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private func clamped(
        _ origin: NSPoint,
        to visibleFrame: NSRect,
        windowSize: NSSize
    ) -> NSPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }

    private static func currentVisibleFrames() -> [NSRect] {
        let mainFrame = NSScreen.main.map(\.visibleFrame)
        let otherFrames = NSScreen.screens.map(\.visibleFrame)
        return ([mainFrame].compactMap { $0 } + otherFrames)
    }

    private static let fallbackVisibleFrame = NSRect(
        x: 0,
        y: 0,
        width: 1440,
        height: 900
    )
}
