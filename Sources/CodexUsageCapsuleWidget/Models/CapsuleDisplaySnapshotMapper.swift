import Foundation

enum CapsuleDisplaySnapshotMapper {
    static func map(
        _ payload: CapsuleDisplayPayload,
        creditPricing: CreditPricingConfiguration = .defaultUSD
    ) -> CapsuleDisplaySnapshot? {
        var itemsByKind: [CapsuleDisplayKind: CapsuleDisplayItem] = [:]

        for window in payload.windows {
            guard
                let windowDurationMins = window.windowDurationMins,
                let kind = CapsuleDisplayKind(windowDurationMins: windowDurationMins)
            else {
                continue
            }

            guard
                let usedPercent = window.usedPercent,
                usedPercent.isFinite,
                itemsByKind[kind] == nil
            else {
                return nil
            }

            let remainingPercent = min(max(100 - usedPercent, 0), 100)
            itemsByKind[kind] = usageItem(
                kind: kind,
                remainingPercent: remainingPercent
            )
        }

        let credits = creditItem(
            from: payload.credits,
            creditPricing: creditPricing
        )

        let items = itemsByKind.values.sorted {
            $0.kind.orderingDurationMins < $1.kind.orderingDurationMins
        }
        guard !items.isEmpty || credits != nil else { return nil }
        return CapsuleDisplaySnapshot(items: items, credits: credits)
    }

    private static func usageItem(
        kind: CapsuleDisplayKind,
        remainingPercent: Double
    ) -> CapsuleDisplayItem {
        let roundedPercent = Int(remainingPercent.rounded())
        return CapsuleDisplayItem(
            kind: kind,
            fillPercent: remainingPercent,
            valueText: "\(roundedPercent)%",
            accessibilityValue: "\(roundedPercent) percent remaining"
        )
    }

    private static func creditItem(
        from payload: WorkspaceCreditBalancePayload?,
        creditPricing: CreditPricingConfiguration
    ) -> CreditsDisplayItem? {
        guard let payload else { return nil }

        guard payload.hasCredits != false else { return nil }

        if payload.unlimited == true {
            return CreditsDisplayItem(
                valueText: "∞",
                accessibilityValue: "Unlimited credits"
            )
        }

        guard
            let creditQuantity = CreditQuantityParser.parse(payload.balance),
            let balanceInUSD = creditPricing.usdBalance(
                for: creditQuantity
            )
        else {
            return nil
        }

        let balanceText = creditPricing.formattedUSD(balanceInUSD)
        return CreditsDisplayItem(
            valueText: balanceText,
            accessibilityValue: "\(balanceText) in credits"
        )
    }
}

private enum CreditQuantityParser {
    static func parse(_ rawBalance: String?) -> Double? {
        guard let rawBalance else { return nil }

        let trimmed = rawBalance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let quantity = Double(trimmed),
            quantity.isFinite,
            quantity > 0
        else {
            return nil
        }
        return quantity
    }
}
