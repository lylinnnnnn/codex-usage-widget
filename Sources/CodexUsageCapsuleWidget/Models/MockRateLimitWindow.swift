import Foundation

struct MockRateLimitWindow: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case fiveHour = "5h"
        case weekly = "Weekly"
    }

    let kind: Kind
    let remainingPercent: Double

    var id: Kind { kind }

    static let phase1Values = [
        MockRateLimitWindow(kind: .fiveHour, remainingPercent: 65),
        MockRateLimitWindow(kind: .weekly, remainingPercent: 69)
    ]
}

enum CapsuleFillMath {
    static func fraction(for remainingPercent: Double) -> Double {
        guard remainingPercent.isFinite else { return 0 }
        return min(max(remainingPercent, 0), 100) / 100
    }

    static func height(for remainingPercent: Double, within totalHeight: Double) -> Double {
        guard totalHeight.isFinite, totalHeight > 0 else { return 0 }
        return totalHeight * fraction(for: remainingPercent)
    }
}
