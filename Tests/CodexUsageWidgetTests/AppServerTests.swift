import Foundation
import Testing
@testable import CodexUsageWidget

@Suite("App-server mapping and sessions")
struct AppServerTests {
    @Test("JSONL maps the Codex bucket and fingerprints account identity")
    func mappingAndPrivacy() throws {
        let output = """
        {"id":2,"result":{"account":{"type":"chatgpt","email":"person@example.invalid","planType":"pro"}}}
        {"method":"account/rateLimits/updated","params":{}}
        {"id":3,"result":{"rateLimits":{"limitId":"other","primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":34,"windowDurationMins":300},"secondary":{"usedPercent":47,"windowDurationMins":10080},"credits":{"balance":"500","hasCredits":true,"unlimited":false}}}}}
        """

        let raw = try CodexAppServerJSONLParser.rawSnapshot(
            from: Data(output.utf8),
            accountResponseID: 2,
            rateLimitResponseID: 3
        )
        let snapshot = try CodexAppServerSnapshotMapper.map(
            raw,
            creditConfiguration: .defaultConfiguration,
            sessionGeneration: 7
        )

        #expect(snapshot.displaySnapshot.items.map(\.valueText) == ["66%", "53%"])
        #expect(snapshot.displaySnapshot.credits?.valueText == "500")
        #expect(snapshot.sessionGeneration == 7)
        #expect(snapshot.accountFingerprint?.count == 64)
        #expect(snapshot.accountFingerprint?.contains("person") == false)
    }

    @Test("Unsupported accounts and non-Codex fallbacks fail closed")
    func closedBoundaries() {
        let raw = AppServerRawSnapshot(
            account: AppServerAccountReadResult(
                account: AppServerAccount(type: "apiKey", email: nil, planType: nil)
            ),
            rateLimits: rateLimitResult(limitID: "codex")
        )

        do {
            _ = try CodexAppServerSnapshotMapper.map(
                raw,
                creditConfiguration: .defaultConfiguration,
                sessionGeneration: 0
            )
            Issue.record("Expected an unsupported account error")
        } catch {
            #expect(error as? CodexAppServerError == .unsupportedAccount)
        }

        #expect(
            CodexAppServerSnapshotMapper.selectedCodexRateLimits(
                from: rateLimitResult(limitID: "other")
            ) == nil
        )
    }

    @Test("Notifications are separated from responses")
    func notificationParsing() {
        #expect(
            CodexAppServerJSONLParser.sessionEvent(
                from: Data("{\"method\":\"account/updated\"}".utf8)
            ) == .accountUpdated
        )
        #expect(
            CodexAppServerJSONLParser.sessionEvent(
                from: Data("{\"method\":\"account/rateLimits/updated\"}".utf8)
            ) == .rateLimitsUpdated
        )
        #expect(
            CodexAppServerJSONLParser.sessionEvent(
                from: Data("{\"id\":2,\"result\":{}}".utf8)
            ) == nil
        )
    }

    @Test("Normal reads reuse a session and reconfirm creates a new generation")
    func sessionReconfirmation() async throws {
        let fixture = try FakeAppServerFixture()
        defer { fixture.remove() }
        let provider = CodexAppServerProvider(
            executableLocator: { fixture.executableURL },
            creditConfigurationProvider: FixedCreditConfigurationProvider()
        )

        do {
            let first = try await provider.fetchSnapshot()
            let second = try await provider.fetchSnapshot()
            #expect(try fixture.launchCount() == 1)
            #expect(first.sessionGeneration == second.sessionGeneration)
            #expect(first.accountFingerprint == second.accountFingerprint)

            let reconfirmed = try await provider.reconfirmAccountAndFetchSnapshot()
            #expect(try fixture.launchCount() == 2)
            #expect(reconfirmed.sessionGeneration > first.sessionGeneration)
            #expect(reconfirmed.accountFingerprint != first.accountFingerprint)
            await provider.stopEventMonitoring()
        } catch {
            await provider.stopEventMonitoring()
            throw error
        }
    }

    private func rateLimitResult(limitID: String) -> AppServerRateLimitReadResult {
        AppServerRateLimitReadResult(
            rateLimits: AppServerRateLimits(
                limitId: limitID,
                primary: AppServerRateLimitWindow(
                    usedPercent: 10,
                    windowDurationMins: 300,
                    resetsAt: nil
                ),
                secondary: nil,
                credits: nil
            ),
            rateLimitsByLimitId: nil
        )
    }
}

private struct FixedCreditConfigurationProvider: CreditDisplayConfigurationProviding {
    func loadCreditDisplayConfiguration() -> CreditDisplayConfiguration {
        .defaultConfiguration
    }
}

private final class FakeAppServerFixture: @unchecked Sendable {
    let directoryURL: URL
    let executableURL: URL
    private let launchCountURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageWidgetTests-\(UUID().uuidString)")
        executableURL = directoryURL.appendingPathComponent("fake-codex")
        launchCountURL = directoryURL.appendingPathComponent("launch-count")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let script = """
        #!/bin/zsh
        set -u
        state_file="\(launchCountURL.path)"
        launch_count=0
        if [[ -f "$state_file" ]]; then
          launch_count="$(<"$state_file")"
        fi
        launch_count=$((launch_count + 1))
        print -r -- "$launch_count" > "$state_file"

        while IFS= read -r request; do
          request_id="$(print -r -- "$request" | /usr/bin/sed -E 's/.*"id"[ ]*:[ ]*([0-9]+).*/\\1/')"
          if [[ "$request" == *'"method":"initialize"'* ]]; then
            print -r -- "{\"id\":$request_id,\"result\":{\"serverInfo\":{\"name\":\"test\"}}}"
          elif [[ "$request" == *'"method":"account/read"'* ]]; then
            print -r -- "{\"id\":$request_id,\"result\":{\"account\":{\"type\":\"chatgpt\",\"email\":\"account-$launch_count@example.invalid\",\"planType\":\"test\"}}}"
          elif [[ "$request" == *'"method":"account/rateLimits/read"'* ]]; then
            print -r -- "{\"id\":$request_id,\"result\":{\"rateLimitsByLimitId\":{\"codex\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":34,\"windowDurationMins\":300},\"secondary\":{\"usedPercent\":47,\"windowDurationMins\":10080},\"credits\":{\"balance\":\"500\",\"hasCredits\":true,\"unlimited\":false}}}}}"
          fi
        done
        """

        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func launchCount() throws -> Int {
        let value = try String(contentsOf: launchCountURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(value) else { throw FixtureError.invalidLaunchCount }
        return count
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private enum FixtureError: Error {
    case invalidLaunchCount
}
