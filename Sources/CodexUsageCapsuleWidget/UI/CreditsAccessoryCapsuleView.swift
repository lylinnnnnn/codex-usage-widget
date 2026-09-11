import SwiftUI

struct CreditsAccessoryCapsuleView: View {
    enum Metrics {
        static let width: CGFloat = 104
        static let height: CGFloat = 28
        static let horizontalPadding: CGFloat = 8
    }

    let item: CreditsDisplayItem

    var body: some View {
        HStack(spacing: 0) {
            Text("Credits")
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(item.valueText)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, Metrics.horizontalPadding)
        .frame(width: Metrics.width, height: Metrics.height)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.20))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Credits")
        .accessibilityValue(item.accessibilityValue)
    }
}
