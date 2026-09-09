import AppKit
import Foundation
import Testing
@testable import CodexUsageWidget

@Suite("Local persistence", .serialized)
struct PersistenceTests {
    @Test("Saved window position is restored and clamped")
    func savedPosition() {
        let suiteName = "WindowPositionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screen = NSRect(x: 0, y: 0, width: 500, height: 400)
        let store = WindowPositionStore(
            userDefaults: defaults,
            visibleFrames: { [screen] }
        )
        store.save(origin: NSPoint(x: 900, y: -100))

        #expect(
            store.restoredOrigin(for: NSSize(width: 100, height: 200))
                == NSPoint(x: 400, y: 0)
        )
    }

    @Test("Missing Credits configuration creates a raw-balance default")
    func defaultCreditConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreditConfigurationTests-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("credit-display.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = CreditDisplayConfigurationStore.load(from: fileURL)
        #expect(configuration.displayMode == .credits)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let storedText = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(storedText.contains("\"displayMode\" : \"credits\""))
        #expect(storedText.contains("\"usdPerCredit\" : \"0.04\""))
    }

    @Test("Custom estimate configuration is loaded")
    func customCreditConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreditConfigurationTests-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("credit-display.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        {"schemaVersion":1,"displayMode":"estimatedUSD","usdPerCredit":"0.05"}
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = CreditDisplayConfigurationStore.load(from: fileURL)
        #expect(configuration.displayMode == .estimatedUSD)
        #expect(configuration.displayItem(for: "500")?.valueText == "$25 est.")
    }
}
