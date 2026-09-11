import Foundation

struct CreditPricingConfiguration: Equatable, Sendable {
    static let defaultUSD = CreditPricingConfiguration(
        usdPerCredit: Decimal(string: "0.04")!
    )
    static let fullCapsuleValueInUSD = Decimal(40)

    let usdPerCredit: Decimal

    init?(usdPerCreditString: String) {
        guard let usdPerCredit = Self.parsePositiveDecimal(usdPerCreditString) else {
            return nil
        }
        self.init(usdPerCredit: usdPerCredit)
    }

    func usdBalance(for creditQuantity: Double) -> Decimal? {
        guard creditQuantity.isFinite, creditQuantity > 0 else { return nil }

        let wholeCredits = creditQuantity.rounded(.down)
        guard wholeCredits.isFinite, wholeCredits >= 1 else { return nil }

        let balance = Decimal(wholeCredits) * usdPerCredit
        return balance > 0 ? balance : nil
    }

    func fillPercent(forUSDBalance balance: Decimal) -> Double? {
        let balanceInUSD = NSDecimalNumber(decimal: balance).doubleValue
        let fullValueInUSD = NSDecimalNumber(
            decimal: Self.fullCapsuleValueInUSD
        ).doubleValue
        guard
            balanceInUSD.isFinite,
            balanceInUSD > 0,
            fullValueInUSD.isFinite,
            fullValueInUSD > 0
        else {
            return nil
        }

        return min(max(balanceInUSD / fullValueInUSD * 100, 0), 100)
    }

    func formattedUSD(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(decimal: amount)
        return "$\(formatter.string(from: number) ?? number.stringValue)"
    }

    private init(usdPerCredit: Decimal) {
        self.usdPerCredit = usdPerCredit
    }

    private static func parsePositiveDecimal(_ rawValue: String) -> Decimal? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            value.range(
                of: "^[0-9]+(?:\\.[0-9]+)?$",
                options: .regularExpression
            ) != nil,
            let decimal = Decimal(
                string: value,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            decimal > 0
        else {
            return nil
        }

        let doubleValue = NSDecimalNumber(decimal: decimal).doubleValue
        return doubleValue.isFinite && doubleValue > 0 ? decimal : nil
    }
}
