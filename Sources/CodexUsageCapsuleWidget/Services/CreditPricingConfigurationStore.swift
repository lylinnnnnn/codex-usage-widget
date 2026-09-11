import Foundation

protocol CreditPricingConfigurationProviding: Sendable {
    func loadCreditPricing() -> CreditPricingConfiguration
}

struct CreditPricingConfigurationFileProvider:
    CreditPricingConfigurationProviding {
    private let fileURL: URL

    init(fileURL: URL = CreditPricingConfigurationStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func loadCreditPricing() -> CreditPricingConfiguration {
        return CreditPricingConfigurationStore.load(from: fileURL)
    }
}

enum CreditPricingConfigurationStore {
    private static let schemaVersion = 1

    static func load() -> CreditPricingConfiguration {
        load(from: defaultFileURL())
    }

    static func load(from fileURL: URL) -> CreditPricingConfiguration {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            writeDefaultIfMissing(to: fileURL, fileManager: fileManager)
            return .defaultUSD
        }

        guard
            let data = try? Data(contentsOf: fileURL),
            let storedPricing = try? JSONDecoder().decode(
                StoredCreditPricing.self,
                from: data
            ),
            storedPricing.schemaVersion == schemaVersion,
            let pricing = CreditPricingConfiguration(
                usdPerCreditString: storedPricing.usdPerCredit
            )
        else {
            // Preserve malformed user input so it can be fixed manually.
            return .defaultUSD
        }

        return pricing
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
            .appendingPathComponent(
                "CodexUsageCapsuleWidget",
                isDirectory: true
            )
            .appendingPathComponent("credit-pricing.json", isDirectory: false)
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
                StoredCreditPricing(
                    schemaVersion: schemaVersion,
                    usdPerCredit: "0.04"
                )
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A missing or unwritable local preference must not block the widget.
        }
    }

    private struct StoredCreditPricing: Codable {
        let schemaVersion: Int
        let usdPerCredit: String
    }
}
