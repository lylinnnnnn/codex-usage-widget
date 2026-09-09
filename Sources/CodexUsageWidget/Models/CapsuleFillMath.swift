import Foundation

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
