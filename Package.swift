// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Full Xcode installations expose Swift Testing automatically. A few
// Command Line Tools-only installations place it in this developer-framework
// directory instead, so opt into that fallback only when it actually exists.
let commandLineToolsFrameworks =
    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let commandLineToolsSwiftLibraries =
    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let needsCommandLineToolsTestingFallback = FileManager.default.fileExists(
    atPath: commandLineToolsFrameworks + "/Testing.framework"
)

let localTestingSwiftSettings: [SwiftSetting] = needsCommandLineToolsTestingFallback
    ? [.unsafeFlags(["-F", commandLineToolsFrameworks])]
    : []

let localTestingLinkerSettings: [LinkerSetting] = needsCommandLineToolsTestingFallback
    ? [
        .unsafeFlags([
            "-F", commandLineToolsFrameworks,
            "-framework", "Testing",
            "-Xlinker", "-rpath",
            "-Xlinker", commandLineToolsFrameworks,
            "-Xlinker", "-rpath",
            "-Xlinker", commandLineToolsSwiftLibraries
        ])
    ]
    : []

let package = Package(
    name: "CodexUsageWidget",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CodexUsageWidget",
            targets: ["CodexUsageWidget"]
        ),
        .executable(
            name: "CodexUsageCapsuleWidget",
            targets: ["CodexUsageCapsuleWidget"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageWidget",
            path: "Sources/CodexUsageWidget"
        ),
        .executableTarget(
            name: "CodexUsageCapsuleWidget",
            path: "Sources/CodexUsageCapsuleWidget"
        ),
        .testTarget(
            name: "CodexUsageCapsuleWidgetTests",
            dependencies: ["CodexUsageCapsuleWidget"],
            path: "Tests/CodexUsageCapsuleWidgetTests",
            swiftSettings: localTestingSwiftSettings,
            linkerSettings: localTestingLinkerSettings
        ),
        .testTarget(
            name: "CodexUsageWidgetTests",
            dependencies: ["CodexUsageWidget"],
            path: "Tests/CodexUsageWidgetTests",
            swiftSettings: localTestingSwiftSettings,
            linkerSettings: localTestingLinkerSettings
        )
    ]
)
