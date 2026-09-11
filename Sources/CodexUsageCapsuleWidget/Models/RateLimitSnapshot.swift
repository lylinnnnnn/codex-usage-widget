import Foundation

enum RateLimitWindowKind: String, CaseIterable, Sendable {
    case fiveHour = "5h"
    case weekly = "Weekly"

    init?(windowDurationMins: Int) {
        switch windowDurationMins {
        case 300:
            self = .fiveHour
        case 10_080:
            self = .weekly
        default:
            return nil
        }
    }
}

struct RateLimitWindow: Identifiable, Equatable, Sendable {
    let kind: RateLimitWindowKind
    let remainingPercent: Double
    let resetDate: Date?

    var id: RateLimitWindowKind { kind }
}

struct RateLimitSnapshot: Equatable, Sendable {
    let fiveHour: RateLimitWindow
    let weekly: RateLimitWindow

    var windows: [RateLimitWindow] {
        [fiveHour, weekly]
    }
}
