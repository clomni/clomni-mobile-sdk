// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "clomni_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "clomni-flutter", targets: ["clomni_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // The iOS SDK (before it is published, an app can point Xcode at a checkout instead; README.md).
        .package(url: "https://github.com/clomni/clomni-mobile-sdk.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "clomni_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "ClomniMessenger", package: "clomni-mobile-sdk")
            ]
        )
    ]
)
