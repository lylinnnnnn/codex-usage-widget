import Foundation

protocol CreditDisplayConfigurationProviding: Sendable {
    func loadCreditDisplayConfiguration() -> CreditDisplayConfiguration
}

struct CreditDisplayConfigurationFileProvider: CreditDisplayConfigurationProviding {
    private let fileURL: URL

    init(fileURL: URL = CreditDisplayConfigurationStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func loadCreditDisplayConfiguration() -> CreditDisplayConfiguration {
        CreditDisplayConfigurationStore.load(from: fileURL)
    }
}

enum CreditDisplayConfigurationStore {
    private static let schemaVersion = 1

    static func load(from fileURL: URL = defaultFileURL()) -> CreditDisplayConfiguration {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            writeDefaultIfMissing(to: fileURL, fileManager: fileManager)
            return .defaultConfiguration
        }

        guard
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data),
            stored.schemaVersion == schemaVersion,
            let mode = CreditDisplayMode(rawValue: stored.displayMode),
            let configuration = CreditDisplayConfiguration(
                displayMode: mode,
                usdPerCreditString: stored.usdPerCredit
            )
        else {
            return .defaultConfiguration
        }

        return configuration
    }

    static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )

        return applicationSupportDirectory
            .appendingPathComponent("CodexUsageWidget", isDirectory: true)
            .appendingPathComponent("credit-display.json", isDirectory: false)
    }

    private static func writeDefaultIfMissing(
        to fileURL: URL,
        fileManager: FileManager
    ) {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(atPath: fileURL.path) else { return }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                StoredConfiguration(
                    schemaVersion: schemaVersion,
                    displayMode: CreditDisplayMode.credits.rawValue,
                    usdPerCredit: "0.04"
                )
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A local display preference must never prevent usage from loading.
        }
    }

    private struct StoredConfiguration: Codable {
        let schemaVersion: Int
        let displayMode: String
        let usdPerCredit: String
    }
}
