// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nashi",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NashiCore", targets: ["NashiCore"]),
        .executable(name: "Nashi", targets: ["NashiApp"]),
        .executable(name: "nashi-cli", targets: ["NashiCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "NashiCore", resources: [.copy("Resources")]),
        // The frozen XPC wire protocol stays at its sealed source path. It is compiled
        // into the renamed module without changing its Objective-C identity.
        .target(name: "NashiUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources", exclude: ["NashiApp", "NashiCore", "NashiCLI", "UpdateCredentialBroker"], sources: ["NashiUpdates", "TangerineUpdates/UpdateCredentialBrokerProtocol.swift"]),
        .executableTarget(name: "NashiApp", dependencies: ["NashiCore", "NashiUpdates"], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "NashiCLI", dependencies: ["NashiCore"]),
        .testTarget(name: "NashiCoreTests", dependencies: ["NashiCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "NashiUpdatesTests", dependencies: ["NashiUpdates"])
    ],
    swiftLanguageModes: [.v5]
)
