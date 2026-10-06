// swift-tools-version:5.9
import PackageDescription

// Type-checks Plugins/iOS/ClomniUnityBridge.swift on Linux, where the real ClomniMessenger (SwiftUI) does not build:
// against a stub with the signatures of ios/api/ClomniMessenger.txt. From the repository root:
//   swift build --package-path unity/Tests~/Swift
let package = Package(
    name: "ClomniUnityBridgeCheck",
    targets: [
        .target(name: "ClomniMessenger"),
        .target(name: "ClomniUnityBridge", dependencies: ["ClomniMessenger"]),
    ]
)
