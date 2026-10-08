# Operator photo on Clomni notifications (optional)

Without this extension a Clomni notification shows the title ("Leyla · Example") and the text. With it, the operator's
photo appears next to them.

1. In Xcode: File → New → Target → Notification Service Extension. Deployment target iOS 15 or later.
2. Replace the generated `NotificationService.swift` with [NotificationService.swift](NotificationService.swift).
   The extension does not need the Clomni SDK.
3. If the app already has a Notification Service Extension, keep it and add the Clomni branch: pushes with
   `"clomni": "1"` and an `avatar_url`.

Clomni sends every push with `mutable-content: 1`, so nothing else is needed on the server side.

## The app's side

The app target needs the Push Notifications capability (Signing & Capabilities), and the APNs key (.p8) goes into the
App SDK inbox's Push tab in Clomni. `setDeviceToken`, `shouldShowForeground` and `handlePush` are wired in the Example
app's [AppDelegate.swift](../../Example/ClomniExample/AppDelegate.swift), where CI compiles this extension too.
