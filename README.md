# Clomni Messenger mobile SDK

Native SDKs that open the Clomni Messenger inside a customer's own iOS or Android app. In Clomni each app is an
"App SDK" inbox: messages land with the operators, and the flows built for the website chat (language choice, menu
buttons, handover to an operator) run here with native buttons. Push notifications deliver replies while the app is
closed.

| Directory | Package |
|---|---|
| `android/` | `ai.clomni:messenger` (Kotlin, Jetpack Compose) |
| `ios/` | `ClomniMessenger` (Swift Package Manager, CocoaPods) |
| `react-native/` | `@clomni/react-native` (wraps the native SDKs) |
| `flutter/` | `clomni_flutter` (wraps the native SDKs) |
| `unity/` | `ai.clomni.messenger` (Unity package, wraps the native SDKs) |
| `protocol/` | JSON Schemas and fixtures, copied from the Clomni server repo (`scripts/sync-protocol.sh`) |

Both native SDKs render the same `protocol/fixtures`; their tests fail when a fixture no longer parses or renders.

## iOS

iOS 15 or later, Xcode 15 or later.

**Swift Package Manager**: File → Add Package Dependencies → `https://github.com/rzayevkenann/clomni-mobile-sdk.git`,
version 1.0.0 or later, product `ClomniMessenger`.

**CocoaPods**:

```ruby
pod 'ClomniMessenger', '~> 1.0'
```

Then, at launch, with the App ID and the iOS API key from Clomni (Channels → Mobile app):

```swift
import ClomniMessenger

Clomni.initialize(appId: "app_…", apiKey: "ios_…")
```

and open the messenger from the app's own button: `Clomni.present(source: "profile_support")`. Login, push and the rest
are in the Example app ([ios/Example](ios/Example)), whose code CI compiles; the public API is listed in
[ios/api/ClomniMessenger.txt](ios/api/ClomniMessenger.txt) and the changes in [ios/CHANGELOG.md](ios/CHANGELOG.md).

### Releasing iOS

SwiftPM finds versions by the repository's tags, so the iOS SDK's tags are bare semantic versions (`1.0.0`); the other
packages' tags carry a prefix (`android-1.0.0`, `react-native-1.0.0`, `flutter-1.0.0`, `unity-1.0.0`) and SwiftPM ignores them.

1. The same version in `ClomniMessenger.podspec`, `SDKInfo.version` and a `## 1.0.0` section of `ios/CHANGELOG.md`
   without "(unreleased)": `scripts/ios-release-check.sh 1.0.0 --release`.
2. Push the tag `1.0.0`. SwiftPM has the release at once; the "iOS release" workflow tests, builds and lints it,
   publishes the podspec to CocoaPods trunk (secret `COCOAPODS_TRUNK_TOKEN`; skipped with a warning without it) and
   writes the GitHub release from the changelog section.

Run by hand, the workflow is a dry run: the same checks, nothing published.
