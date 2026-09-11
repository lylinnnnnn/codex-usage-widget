import SwiftUI

struct WidgetView: View {
    enum Metrics {
        static let windowWidth: CGFloat = 56
        static let windowHeight: CGFloat = 202
        static let barWidth: CGFloat = 12
        static let barHeight: CGFloat = 120
        static let percentageHeight: CGFloat = 18
        static let labelHeight: CGFloat = 15
        static let percentageToBarMinimum: CGFloat = 6
        static let barToLabelMinimum: CGFloat = 7
    }

    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let usage = viewModel.displaySnapshot?.items.first

        VStack(spacing: 0) {
            Text(usage?.valueText ?? "--%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(height: Metrics.percentageHeight)

            Spacer(minLength: Metrics.percentageToBarMinimum)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))

                    Capsule()
                        .fill(Color.white.opacity(0.96))
                        .frame(
                            height: CapsuleFillMath.height(
                                for: usage?.fillPercent ?? 0,
                                within: geometry.size.height
                            )
                        )
                }
                .clipShape(Capsule())
            }
            .frame(width: Metrics.barWidth, height: Metrics.barHeight)

            Spacer(minLength: Metrics.barToLabelMinimum)

            Text("Codex")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(height: Metrics.labelHeight)
        }
        .frame(
            width: Metrics.windowWidth,
            height: Metrics.windowHeight
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex usage")
        .accessibilityValue(usage?.accessibilityValue ?? "Usage unavailable")
        .accessibilityHint("Remaining Codex usage")
    }
}
