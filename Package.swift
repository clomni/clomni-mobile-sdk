// swift-tools-version:5.9
import PackageDescription

// ClomniProtocol (models), ClomniCore (REST, socket, cache, outbox) and ClomniPresentation (theme, texts, what each
// screen shows) use Foundation only, so they build and test on Linux as well; ClomniMessenger re-exports the first two
// and draws the screens with SwiftUI. System frameworks only: the SDK has no third-party dependencies.
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
        .target(name: "ClomniCore", dependencies: ["ClomniProtocol"], path: "ios/Sources/ClomniCore"),
        .target(name: "ClomniPresentation", dependencies: ["ClomniCore"], path: "ios/Sources/ClomniPresentation"),
        .target(name: "ClomniMessenger", dependencies: ["ClomniCore", "ClomniPresentation"],
                path: "ios/Sources/ClomniMessenger", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "ClomniProtocolTests", dependencies: ["ClomniProtocol"], path: "ios/Tests/ClomniProtocolTests"),
        .testTarget(name: "ClomniCoreTests", dependencies: ["ClomniCore"], path: "ios/Tests/ClomniCoreTests"),
        .testTarget(name: "ClomniPresentationTests", dependencies: ["ClomniPresentation"],
                    path: "ios/Tests/ClomniPresentationTests"),
        .testTarget(name: "ClomniMessengerTests", dependencies: ["ClomniMessenger", "ClomniPresentation", "ClomniProtocol"],
                    path: "ios/Tests/ClomniMessengerTests"),
    ]
)
