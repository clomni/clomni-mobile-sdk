// swift-tools-version:5.9
import PackageDescription

// ClomniProtocol uses Foundation only, so it builds and tests on Linux as well; ClomniMessenger re-exports it and
// carries the UI. System frameworks only: the SDK has no third-party dependencies.
let package = Package(
    name: "ClomniMessenger",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ClomniMessenger", targets: ["ClomniMessenger"]),
    ],
    targets: [
        .target(name: "ClomniProtocol"),
        .target(name: "ClomniMessenger", dependencies: ["ClomniProtocol"]),
        .testTarget(name: "ClomniProtocolTests", dependencies: ["ClomniProtocol"]),
        .testTarget(name: "ClomniMessengerTests", dependencies: ["ClomniMessenger"]),
    ]
)
