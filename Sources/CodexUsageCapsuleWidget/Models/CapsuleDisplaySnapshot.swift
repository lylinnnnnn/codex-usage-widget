import Foundation

enum CapsuleDisplayKind: String, CaseIterable, Sendable {
    case fiveHour = "5h"
    case weekly = "Weekly"
    case monthly = "Monthly"

    init?(windowDurationMins: Int) {
        switch windowDurationMins {
        case 300:
            self = .fiveHour
        case 10_080:
            self = .weekly
        case 43_200:
            self = .monthly
        default:
            return nil
        }
    }
}

struct CapsuleDisplayItem: Identifiable, Equatable, Sendable {
    let kind: CapsuleDisplayKind
    let fillPercent: Double
    let valueText: String
    let accessibilityValue: String

    var id: CapsuleDisplayKind { kind }

    init(
        kind: CapsuleDisplayKind,
        fillPercent: Double,
        valueText: String,
        accessibilityValue: String
    ) {
        self.kind = kind
        self.fillPercent = fillPercent.isFinite
            ? min(max(fillPercent, 0), 100)
            : 0
        self.valueText = valueText
        self.accessibilityValue = accessibilityValue
    }
}

struct CapsuleDisplaySnapshot: Equatable, Sendable {
    static let maximumVisibleItems = 2

    let items: [CapsuleDisplayItem]
    let credits: CreditsDisplayItem?

    init(
        items: [CapsuleDisplayItem],
        credits: CreditsDisplayItem? = nil
    ) {
        self.items = Array(items.prefix(Self.maximumVisibleItems))
        self.credits = credits
    }
}

struct CreditsDisplayItem: Equatable, Sendable {
    let valueText: String
    let accessibilityValue: String
}

struct CapsuleDisplayPayload: Equatable, Sendable {
    let windows: [RateLimitWindowPayload]
    let credits: WorkspaceCreditBalancePayload?
}

struct WorkspaceCreditBalancePayload: Equatable, Sendable {
    let balance: String?
    let hasCredits: Bool?
    let unlimited: Bool?
}
