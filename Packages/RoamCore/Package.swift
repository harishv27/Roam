// swift-tools-version: 5.9
import PackageDescription

// The networking and data layer: endpoints, response decoding, an HTTP client with retries, a disk cache with
// stale-data fallback, and the ranking of nearby places. No UI and no real network in the tests, so `swift test`
// runs in a second.
let package = Package(
    name: "RoamCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RoamCore", targets: ["RoamCore"])],
    targets: [
        .target(name: "RoamCore"),
        .testTarget(name: "RoamCoreTests", dependencies: ["RoamCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageVersions: [.v5]
)
