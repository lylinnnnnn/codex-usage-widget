import Foundation

struct RateLimitWindowPayload: Equatable, Sendable {
    let windowDurationMins: Int?
    let usedPercent: Double?
    let resetsAt: Date?
}

struct RateLimitSnapshotPayload: Equatable, Sendable {
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
}

enum RateLimitSnapshotMapper {
    static func map(_ payload: RateLimitSnapshotPayload) -> RateLimitSnapshot? {
        map([payload.primary, payload.secondary].compactMap { $0 })
    }

    static func map(_ payloads: [RateLimitWindowPayload]) -> RateLimitSnapshot? {
        guard payloads.count == RateLimitWindowKind.allCases.count else {
            return nil
        }

        var windowsByKind: [RateLimitWindowKind: RateLimitWindow] = [:]

        for payload in payloads {
            guard
                let windowDurationMins = payload.windowDurationMins,
                let kind = RateLimitWindowKind(windowDurationMins: windowDurationMins),
                let usedPercent = payload.usedPercent,
                usedPercent.isFinite,
                windowsByKind[kind] == nil
            else {
                return nil
            }

            let remainingPercent = min(max(100 - usedPercent, 0), 100)
            windowsByKind[kind] = RateLimitWindow(
                kind: kind,
                remainingPercent: remainingPercent,
                resetDate: payload.resetsAt
            )
        }

        guard
            let fiveHour = windowsByKind[.fiveHour],
            let weekly = windowsByKind[.weekly]
        else {
            return nil
        }

        return RateLimitSnapshot(fiveHour: fiveHour, weekly: weekly)
    }
}
