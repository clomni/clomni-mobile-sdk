// swift-tools-version:5.9
import PackageDescription

// ClomniProtocol uses Foundation only, so it builds and tests on Linux as well; ClomniMessenger re-exports it and
// carries the UI. System frameworks only: the SDK has no third-party dependencies.
// The manifest sits at the repository root because SwiftPM resolves a package by its git URL from there; the
// sources stay under ios/ next to android/.
let package = Package(
    name: "ClomniMessenger",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ClomniMessenger", targets: ["ClomniMessenger"]),
    ],
    targets: [
        .target(name: "ClomniProtocol", path: "ios/Sources/ClomniProtocol"),
        .target(name: "ClomniMessenger", dependencies: ["ClomniProtocol"], path: "ios/Sources/ClomniMessenger"),
        .testTarget(name: "ClomniProtocolTests", dependencies: ["ClomniProtocol"], path: "ios/Tests/ClomniProtocolTests"),
        .testTarget(name: "ClomniMessengerTests", dependencies: ["ClomniMessenger"], path: "ios/Tests/ClomniMessengerTests"),
    ]
)
