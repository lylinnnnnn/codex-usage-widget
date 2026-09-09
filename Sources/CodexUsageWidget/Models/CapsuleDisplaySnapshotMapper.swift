import Foundation

enum CapsuleDisplaySnapshotMapper {
    static func map(
        _ payload: CapsuleDisplayPayload,
        creditConfiguration: CreditDisplayConfiguration = .defaultConfiguration
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
            creditConfiguration: creditConfiguration
        )

        let items = CapsuleDisplayKind.allCases.compactMap { itemsByKind[$0] }
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
        creditConfiguration: CreditDisplayConfiguration
    ) -> CreditsDisplayItem? {
        guard let payload else { return nil }

        guard payload.hasCredits != false else { return nil }

        if payload.unlimited == true {
            return CreditsDisplayItem(
                valueText: "∞",
                accessibilityValue: "Unlimited credits"
            )
        }

        return creditConfiguration.displayItem(for: payload.balance)
    }
}
