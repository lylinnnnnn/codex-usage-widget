import SwiftUI

struct RateLimitCapsuleView: View {
    enum Metrics {
        static let columnWidth: CGFloat = 56
        static let columnHeight: CGFloat = 202
        static let capsuleWidth: CGFloat = 12
        static let capsuleHeight: CGFloat = 120
        static let percentageHeight: CGFloat = 18
        static let labelHeight: CGFloat = 15
        static let percentageToCapsuleMinimum: CGFloat = 6
        static let capsuleToLabelMinimum: CGFloat = 7
    }

    let kind: CapsuleDisplayKind
    let fillPercent: Double?
    let valueText: String?
    let itemAccessibilityValue: String?

    init(item: CapsuleDisplayItem) {
        kind = item.kind
        fillPercent = item.fillPercent
        valueText = item.valueText
        itemAccessibilityValue = item.accessibilityValue
    }

    init(unavailableKind kind: CapsuleDisplayKind) {
        self.kind = kind
        fillPercent = nil
        valueText = nil
        itemAccessibilityValue = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(valueText ?? "--%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(height: Metrics.percentageHeight)

            Spacer(minLength: Metrics.percentageToCapsuleMinimum)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))

                    Capsule()
                        .fill(Color.white.opacity(0.96))
                        .frame(
                            height: CapsuleFillMath.height(
                                for: fillPercent ?? 0,
                                within: geometry.size.height
                            )
                        )
                }
                .clipShape(Capsule())
            }
            .frame(
                width: Metrics.capsuleWidth,
                height: Metrics.capsuleHeight
            )

            Spacer(minLength: Metrics.capsuleToLabelMinimum)

            Text(kind.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(height: Metrics.labelHeight)
        }
        .frame(
            width: Metrics.columnWidth,
            height: Metrics.columnHeight
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.rawValue)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Remaining Codex usage")
    }

    private var accessibilityValue: String {
        itemAccessibilityValue ?? "Usage unavailable"
    }
}
