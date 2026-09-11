import SwiftUI

struct WidgetView: View {
    enum Metrics {
        static let windowWidth: CGFloat = 112
        static let usageAreaHeight: CGFloat = 202
        static let creditsTopSpacing: CGFloat = 8
        static let columnSpacing: CGFloat = 0

        static func windowHeight(hasCredits: Bool) -> CGFloat {
            usageAreaHeight + (hasCredits
                ? creditsTopSpacing + CreditsAccessoryCapsuleView.Metrics.height
                : 0)
        }
    }

    @ObservedObject var viewModel: RateLimitSnapshotViewModel

    var body: some View {
        let credits = viewModel.displaySnapshot?.credits

        VStack(spacing: credits == nil ? 0 : Metrics.creditsTopSpacing) {
            usageCapsules

            if let credits {
                CreditsAccessoryCapsuleView(item: credits)
            }
        }
        .frame(
            width: Metrics.windowWidth,
            height: Metrics.windowHeight(hasCredits: credits != nil),
            alignment: .top
        )
    }

    private var usageCapsules: some View {
        HStack(alignment: .top, spacing: Metrics.columnSpacing) {
            if viewModel.displaySnapshot?.items.isEmpty == false {
                ForEach(viewModel.displaySnapshot?.items ?? []) { item in
                    RateLimitCapsuleView(item: item)
                }
                ForEach(
                    0..<max(
                        0,
                        CapsuleDisplaySnapshot.maximumVisibleItems
                            - (viewModel.displaySnapshot?.items.count ?? 0)
                    ),
                    id: \.self
                ) { _ in
                    Color.clear.frame(
                        width: RateLimitCapsuleView.Metrics.columnWidth,
                        height: RateLimitCapsuleView.Metrics.columnHeight
                    )
                }
            } else {
                RateLimitCapsuleView(unavailableKind: .fiveHour)
                RateLimitCapsuleView(unavailableKind: .weekly)
            }
        }
        .frame(
            width: Metrics.windowWidth,
            height: Metrics.usageAreaHeight
        )
        .contentShape(Rectangle())
    }
}
