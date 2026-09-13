import Foundation

enum DisplayMode: String, CaseIterable {
    case capsules
    case notchCompact

    var title: String {
        switch self {
        case .capsules: "Capsules"
        case .notchCompact: "Notch Compact"
        }
    }
}

struct DisplayModeStore {
    private static let key = "codexUsageCapsuleWidget.displayMode"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> DisplayMode {
        userDefaults.string(forKey: Self.key)
            .flatMap(DisplayMode.init(rawValue:)) ?? .capsules
    }

    func save(_ mode: DisplayMode) {
        userDefaults.set(mode.rawValue, forKey: Self.key)
    }
}
