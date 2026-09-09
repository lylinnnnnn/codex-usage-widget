import Foundation

enum CodexExecutableLocator {
    static func locate() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment[
            "CODEX_USAGE_WIDGET_CODEX_PATH"
        ], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".npm-global/bin/codex"),
            homeDirectory.appendingPathComponent(".volta/bin/codex"),
            homeDirectory.appendingPathComponent(".asdf/shims/codex"),
            homeDirectory.appendingPathComponent(".fnm/current/bin/codex"),
            homeDirectory.appendingPathComponent("Library/pnpm/codex")
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path
                .split(separator: ":")
                .map { directory in
                    URL(fileURLWithPath: String(directory)).appendingPathComponent("codex")
                }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
