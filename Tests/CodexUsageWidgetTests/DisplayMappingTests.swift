import Foundation
import Testing
@testable import CodexUsageWidget

@Suite("Display mapping")
struct DisplayMappingTests {
    @Test("5h and Weekly map to remaining percentages")
    func usageWindows() throws {
        let snapshot = try #require(
            CapsuleDisplaySnapshotMapper.map(
                CapsuleDisplayPayload(
                    windows: [
                        window(duration: 10_080, used: 47),
                        window(duration: 300, used: 34)
                    ],
                    credits: nil
                )
            )
        )

        #expect(snapshot.items.map(\.kind) == [.fiveHour, .weekly])
        #expect(snapshot.items.map(\.fillPercent) == [66, 53])
        #expect(snapshot.items.map(\.valueText) == ["66%", "53%"])
    }

    @Test("Two slots prioritize 5h and Weekly")
    func slotPriority() throws {
        let snapshot = try #require(
            CapsuleDisplaySnapshotMapper.map(
                CapsuleDisplayPayload(
                    windows: [
                        window(duration: 43_200, used: 20),
                        window(duration: 10_080, used: 30),
                        window(duration: 300, used: 40)
                    ],
                    credits: nil
                )
            )
        )
        #expect(snapshot.items.map(\.kind) == [.fiveHour, .weekly])
    }

    @Test("Raw Credits are the default")
    func rawCredits() throws {
        let snapshot = try #require(
            CapsuleDisplaySnapshotMapper.map(
                CapsuleDisplayPayload(
                    windows: [window(duration: 300, used: 10)],
                    credits: WorkspaceCreditBalancePayload(
                        balance: "542.52",
                        hasCredits: true,
                        unlimited: false
                    )
                )
            )
        )
        #expect(snapshot.credits?.valueText == "542.52")
        #expect(snapshot.credits?.accessibilityValue == "542.52 credits")
    }

    @Test("Estimated USD is explicit and configurable")
    func estimatedCredits() throws {
        let configuration = try #require(
            CreditDisplayConfiguration(
                displayMode: .estimatedUSD,
                usdPerCreditString: "0.05"
            )
        )
        let snapshot = try #require(
            CapsuleDisplaySnapshotMapper.map(
                CapsuleDisplayPayload(
                    windows: [],
                    credits: WorkspaceCreditBalancePayload(
                        balance: "500",
                        hasCredits: true,
                        unlimited: false
                    )
                ),
                creditConfiguration: configuration
            )
        )
        #expect(snapshot.credits?.valueText == "$25 est.")
        #expect(
            snapshot.credits?.accessibilityValue
                == "$25 est. in user-estimated credit value"
        )
    }

    @Test("Unlimited and invalid Credits are handled safely")
    func creditEdgeCases() throws {
        let unlimited = try #require(
            CapsuleDisplaySnapshotMapper.map(
                CapsuleDisplayPayload(
                    windows: [],
                    credits: WorkspaceCreditBalancePayload(
                        balance: nil,
                        hasCredits: true,
                        unlimited: true
                    )
                )
            )
        )
        #expect(unlimited.credits?.valueText == "∞")

        let invalid = CapsuleDisplaySnapshotMapper.map(
            CapsuleDisplayPayload(
                windows: [],
                credits: WorkspaceCreditBalancePayload(
                    balance: "$20",
                    hasCredits: true,
                    unlimited: false
                )
            )
        )
        #expect(invalid == nil)
    }

    @Test("Capsule fill math clamps invalid values")
    func fillMath() {
        #expect(CapsuleFillMath.fraction(for: -10) == 0)
        #expect(CapsuleFillMath.fraction(for: 120) == 1)
        #expect(CapsuleFillMath.fraction(for: .nan) == 0)
        #expect(CapsuleFillMath.height(for: 50, within: 120) == 60)
        #expect(CapsuleFillMath.height(for: 50, within: -1) == 0)
    }

    private func window(duration: Int, used: Double) -> RateLimitWindowPayload {
        RateLimitWindowPayload(
            windowDurationMins: duration,
            usedPercent: used,
            resetsAt: nil
        )
    }
}
