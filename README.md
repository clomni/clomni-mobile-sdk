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
