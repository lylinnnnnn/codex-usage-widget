import Foundation

enum CapsuleDisplayKind: Hashable, Sendable {
    case fiveHour
    case weekly
    case monthly
    case custom(windowDurationMins: Int)

    var displayLabel: String {
        switch self {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case let .custom(windowDurationMins):
            return durationLabel(for: windowDurationMins)
        }
    }

    var compactLabel: String {
        switch self {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "W"
        case .monthly:
            return "M"
        case let .custom(windowDurationMins):
            return durationLabel(for: windowDurationMins)
        }
    }

    init?(windowDurationMins: Int) {
        guard windowDurationMins > 0 else { return nil }

        switch windowDurationMins {
        case 300:
            self = .fiveHour
        case 10_080:
            self = .weekly
        case 43_200:
            self = .monthly
        default:
            self = .custom(windowDurationMins: windowDurationMins)
        }
    }

    var orderingDurationMins: Int {
        switch self {
        case .fiveHour:
            return 300
        case .weekly:
            return 10_080
        case .monthly:
            return 43_200
        case let .custom(windowDurationMins):
            return windowDurationMins
        }
    }

    private func durationLabel(for windowDurationMins: Int) -> String {
        if windowDurationMins % 1_440 == 0 {
            return "\(windowDurationMins / 1_440)d"
        }
        if windowDurationMins % 60 == 0 {
            return "\(windowDurationMins / 60)h"
        }
        return "\(windowDurationMins)m"
    }
}

struct CapsuleDisplayItem: Identifiable, Equatable, Sendable {
    let kind: CapsuleDisplayKind
    let fillPercent: Double
    let valueText: String
    let accessibilityValue: String

    var id: CapsuleDisplayKind { kind }

    var compactText: String {
        "\(kind.compactLabel) \(valueText)"
    }

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
