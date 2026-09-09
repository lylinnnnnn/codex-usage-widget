import Foundation

enum CreditDisplayMode: String, Codable, Sendable {
    case credits
    case estimatedUSD
}

struct CreditDisplayConfiguration: Equatable, Sendable {
    static let defaultConfiguration = CreditDisplayConfiguration(
        displayMode: .credits,
        usdPerCredit: Decimal(string: "0.04")!
    )

    let displayMode: CreditDisplayMode
    let usdPerCredit: Decimal

    init?(displayMode: CreditDisplayMode, usdPerCreditString: String) {
        guard let usdPerCredit = Self.parsePositiveDecimal(usdPerCreditString) else {
            return nil
        }
        self.init(displayMode: displayMode, usdPerCredit: usdPerCredit)
    }

    func displayItem(for rawBalance: String?) -> CreditsDisplayItem? {
        guard let balance = Self.parsePositiveDecimal(rawBalance) else { return nil }

        switch displayMode {
        case .credits:
            let value = Self.formatted(balance, maximumFractionDigits: 2)
            return CreditsDisplayItem(
                valueText: value,
                accessibilityValue: "\(value) credits"
            )

        case .estimatedUSD:
            let estimate = balance * usdPerCredit
            let value = "$\(Self.formatted(estimate, maximumFractionDigits: 2)) est."
            return CreditsDisplayItem(
                valueText: value,
                accessibilityValue: "\(value) in user-estimated credit value"
            )
        }
    }

    private init(displayMode: CreditDisplayMode, usdPerCredit: Decimal) {
        self.displayMode = displayMode
        self.usdPerCredit = usdPerCredit
    }

    private static func parsePositiveDecimal(_ rawValue: String?) -> Decimal? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            value.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
            let decimal = Decimal(
                string: value,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            decimal > 0
        else {
            return nil
        }

        return decimal
    }

    private static func formatted(
        _ amount: Decimal,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? NSDecimalNumber(decimal: amount).stringValue
    }
}
