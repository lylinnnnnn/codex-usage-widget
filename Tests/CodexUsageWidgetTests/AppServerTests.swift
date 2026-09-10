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
            creditConfigurationProvider: FixedCreditConfigurationProvider(),
            requestTimeout: Self.appServerRequestTimeout
        )
        var stage = "first snapshot"

        do {
            let first = try await provider.fetchSnapshot()
            stage = "second snapshot"
            let second = try await provider.fetchSnapshot()
            stage = "verifying session reuse"
            #expect(try fixture.launchCount() == 1)
            #expect(first.sessionGeneration == second.sessionGeneration)
            #expect(first.accountFingerprint == second.accountFingerprint)

            stage = "reconfirmed snapshot"
            let reconfirmed = try await provider.reconfirmAccountAndFetchSnapshot()
            stage = "verifying reconfirmation"
            #expect(try fixture.launchCount() == 2)
            #expect(reconfirmed.sessionGeneration > first.sessionGeneration)
            #expect(reconfirmed.accountFingerprint != first.accountFingerprint)
            await provider.stopEventMonitoring()
        } catch {
            await provider.stopEventMonitoring()
            throw FakeAppServerDiagnosticError(
                stage: stage,
                underlyingError: String(describing: error),
                transcript: fixture.transcript()
            )
        }
    }

    private static var appServerRequestTimeout: TimeInterval {
        ProcessInfo.processInfo.environment["CI"] == "true" ? 30 : 8
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
    private let transcriptURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageWidgetTests-\(UUID().uuidString)")
        executableURL = directoryURL.appendingPathComponent("fake-codex")
        launchCountURL = directoryURL.appendingPathComponent("launch-count")
        transcriptURL = directoryURL.appendingPathComponent("transcript.log")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let script = """
        #!/bin/zsh
        set -u
        state_file="\(launchCountURL.path)"
        transcript_file="\(transcriptURL.path)"
        launch_count=0
        if [[ -f "$state_file" ]]; then
          launch_count="$(<"$state_file")"
        fi
        launch_count=$((launch_count + 1))
        builtin printf '%s\n' "$launch_count" > "$state_file"
        builtin printf 'launch=%s started pid=%s\n' "$launch_count" "$$" >> "$transcript_file"

        while IFS= read -r request; do
          builtin printf 'launch=%s received=%s\n' "$launch_count" "$request" >> "$transcript_file"
          if [[ "$request" =~ '"id"[[:space:]]*:[[:space:]]*([0-9]+)' ]]; then
            request_id="$match[1]"
          else
            builtin printf 'launch=%s ignored=request-without-id\n' "$launch_count" >> "$transcript_file"
            continue
          fi

          method='unknown'
          if [[ "$request" == *'"method"'*'initialize'* ]]; then
            method='initialize'
            builtin printf '{"id":%s,"result":{"serverInfo":{"name":"test"}}}\n' "$request_id"
          elif [[ "$request" == *'"method"'*'account'*'rateLimits'*'read'* ]]; then
            method='account/rateLimits/read'
            builtin printf '{"id":%s,"result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":34,"windowDurationMins":300},"secondary":{"usedPercent":47,"windowDurationMins":10080},"credits":{"balance":"500","hasCredits":true,"unlimited":false}}}}}\n' "$request_id"
          elif [[ "$request" == *'"method"'*'account'*'read'* ]]; then
            method='account/read'
            builtin printf '{"id":%s,"result":{"account":{"type":"chatgpt","email":"account-%s@example.invalid","planType":"test"}}}\n' "$request_id" "$launch_count"
          else
            builtin printf 'launch=%s ignored=unknown-method id=%s\n' "$launch_count" "$request_id" >> "$transcript_file"
            continue
          fi
          # zsh's builtin writes directly to the pipe, without stdio buffering.
          builtin printf 'launch=%s sent=%s id=%s\n' "$launch_count" "$method" "$request_id" >> "$transcript_file"
        done
        builtin printf 'launch=%s stdin-closed\n' "$launch_count" >> "$transcript_file"
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

    func transcript() -> String {
        (try? String(contentsOf: transcriptURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<empty>"
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private enum FixtureError: Error {
    case invalidLaunchCount
}

private struct FakeAppServerDiagnosticError: Error, CustomStringConvertible, LocalizedError {
    let stage: String
    let underlyingError: String
    let transcript: String

    var description: String {
        """
        Fake app-server failed during \(stage): \(underlyingError)
        Transcript:
        \(transcript)
        """
    }

    var errorDescription: String? { description }
}
