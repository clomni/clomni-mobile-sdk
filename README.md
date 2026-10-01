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
