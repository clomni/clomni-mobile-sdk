# iOS

## Requirements

- iOS 15 or newer, Xcode 15 or newer.
- The App ID and the iOS API key (`ios_…`) from **Installation** in the panel's side menu.
- For push: an Apple Developer account and an APNs key ([Push keys](08-push-keys.md)).

## Install

### Swift Package Manager

In Xcode: **File → Add Package Dependencies**, enter `https://github.com/clomni/clomni-mobile-sdk.git`, choose the rule
"Up to Next Major Version" from `1.0.0`, and add the product `ClomniMessenger` to your app target.

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/clomni/clomni-mobile-sdk.git", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "ClomniMessenger", package: "clomni-mobile-sdk"),
    ]),
]
```

### CocoaPods

The SDK is not on CocoaPods trunk. A CocoaPods project takes the pod from the repository's tag:

```ruby
# Podfile, in the app's target
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
```

### Info.plist

Users can send photos in a conversation. Add the two texts iOS shows when it asks for access:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>To send photos to support</string>
<key>NSCameraUsageDescription</key>
<string>To take and send photos to support</string>
```

## Initialize

Call `initialize` once, when the app starts.

UIKit:

```swift
import ClomniMessenger
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_…", apiKey: "ios_…")
        #if DEBUG
        Clomni.setLogLevel(.debug)
        #endif
        return true
    }
}
```

SwiftUI: give the app an `AppDelegate` with `@UIApplicationDelegateAdaptor`. Push needs one anyway.

```swift
import SwiftUI

@main
struct ExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

Every method of `Clomni` may be called from any thread. Callbacks arrive on the main thread. A second `initialize` is
ignored.

## The user

```swift
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: hashFromYourServer)   // the hash from your server

Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])

// With your app's own logout:
Clomni.logout()
```

See [Identifying users](02-identity.md) for the hash.

## Open the Messenger

```swift
// SwiftUI
Button("Support") { Clomni.present(source: "profile_support") }

// UIKit
@objc private func supportTapped() {
    Clomni.present(source: "profile_support")
}
```

| Call | What it does |
|---|---|
| `Clomni.present(source:)` | Opens Home |
| `Clomni.presentNewConversation(source:)` | Opens a new conversation straight away |
| `Clomni.presentConversation(_:)` | Opens a known conversation; the ID comes from `onConversationStarted` |
| `Clomni.dismiss()` | Closes the Messenger from code |

The Messenger is presented over the app's top screen. Call `present` once a screen is visible, not in
`didFinishLaunching`.

### Unread count

```swift
import ClomniMessenger
import SwiftUI

struct SupportRow: View {
    @State private var unread = 0
    @State private var token: UUID?

    var body: some View {
        Button {
            Clomni.present(source: "profile_support")
        } label: {
            HStack {
                Text("Support")
                Spacer()
                if unread > 0 { Text("\(unread)").foregroundStyle(.red) }
            }
        }
        .onAppear { token = Clomni.addUnreadCountListener { count in unread = count } }
        .onDisappear { if let token { Clomni.removeUnreadCountListener(token) } }
    }
}
```

The listener hears the current count at once and then every change.

### Floating button (optional)

Off by default. The panel can turn it on; a value set in code wins. `setBottomPadding` lifts it above a tab bar, in
points.

```swift
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Flows started by the app

Build a flow in the panel with the "App event" trigger and the event name, publish it, then:

```swift
Clomni.startFlow("ride_problem", data: ["ride_id": "R-1923"], openMessenger: true, source: "ride_screen")
```

The flow's texts can use the data as `{{data.ride_id}}`. Without a published flow bound to the event nothing
happens. For an event the user did not tap, keep `openMessenger: false`.

## Events

```swift
Clomni.onMessengerOpened = { source in print("opened from \(source ?? "-")") }
Clomni.onMessengerClosed = { print("closed") }
Clomni.onConversationStarted = { id in print("conversation \(id)") }
Clomni.onFlowCompleted = { flowId in print("flow \(flowId) completed") }
Clomni.onUnreadCountChanged = { count in print("unread \(count)") }
```

Each event has one listener; `nil` removes it.

## Links

A news item's button can carry a web address or your app's deep link. With `onLink` set, every link comes to your
app and the app opens it. Without it, the system opens links.

```swift
Clomni.onLink = { url in
    if url.scheme == "example" {
        // route inside your app
    } else {
        UIApplication.shared.open(url)
    }
}
```

## Language, sounds and look

```swift
Clomni.setLanguage("en")          // az, en or ru; nil follows the phone
Clomni.setSoundsEnabled(false)
Clomni.setTheme(primaryColor: "#0A66C2", typeface: "Montserrat", mode: .dark)
```

- `setLanguage` picks one of the languages turned on in the panel. `nil`, or a language that is off, follows the
  phone, then the panel's main language.
- `setTheme`: the colour is `#RRGGBB`, the mode `.light`, `.dark` or `.system`. Each call replaces the previous one; a
  value left out stays the panel's.
- The font is a family name of a font in the app bundle, listed under `UIAppFonts` in `Info.plist`
  (`Montserrat-Regular.ttf` → `"Montserrat"`). Text keeps following Dynamic Type. For the font alone:
  `Clomni.setTypeface("Montserrat")`.

## Push notifications

Clomni sends iOS pushes straight to APNs with your `.p8` key. Firebase is not involved on iOS.

You need:

1. An APNs key uploaded to the panel ([Push keys](08-push-keys.md)). The key must be made for
   **Sandbox & Production**.
2. The Push Notifications capability in the app.
3. The code below.

### 1. Capability

In Xcode: select the app target → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.

> **Path:** `Xcode → Project navigator → project → TARGETS → app → Signing & Capabilities → + Capability → Push Notifications`
>
> Configuration: **All**. Double-click **Push Notifications** in the library; it appears below the **Signing** section.
>
> Docs: [developer.apple.com/documentation/xcode/adding-capabilities-to-your-app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app#Add-a-capability)

### 2. AppDelegate

```swift
import ClomniMessenger
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_…", apiKey: "ios_…")
        UNUserNotificationCenter.current().delegate = self
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true { UIApplication.shared.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Clomni.setDeviceToken(deviceToken)
    }

    // A push while the app is open. Clomni's are not shown while the Messenger is open.
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // A tap on a notification: a Clomni push opens its conversation.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // the app's own push
    }
}
```

- Keep both delegate methods `@MainActor`, not `nonisolated`. The system may call them from a background queue, and
  Swift calls the system's completion handler where the method ends. Ended off the main thread, UIKit stops the app
  with "Call must be made on main thread".
- Ask for the notification permission at a moment that suits your users. The example asks at start for brevity.
- `Clomni.isClomniPush(userInfo)` tells a Clomni push from your own without handling it.

### 3. Sandbox and production

The SDK reports the APNs environment of each device by itself:

| How the app was installed | APNs environment |
|---|---|
| Run from Xcode (development profile) | sandbox |
| TestFlight, App Store, Ad Hoc | production |

One `.p8` key serves both, as long as it was made for **Sandbox & Production**. A key limited to one environment
fails on the other with `BadEnvironmentKeyInToken`. The Test push list in the panel shows the environment of each
device.

### 4. The agent's photo (optional)

Without anything more, a Clomni notification shows the title ("Leyla · Example") and the text. A Notification Service
Extension adds the agent's photo.

1. In Xcode: **File → New → Target → Notification Service Extension**. Deployment target iOS 15 or newer.

   > **Path:** `Xcode → File → New → Target… → iOS → Notification Service Extension → Next → Product Name → Finish`
   >
   > Docs: [developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)

2. Replace the generated `NotificationService.swift` with the file below. The extension does not need the Clomni SDK.
3. If the app already has a Notification Service Extension, keep it and add the Clomni branch: pushes with
   `"clomni": "1"` and an `avatar_url`.

Clomni sends every push with `mutable-content: 1`, so nothing else is needed.

```swift
// NotificationService.swift, in the extension target
import Foundation
import UserNotifications

/// Puts the operator's photo on Clomni notifications. Clomni sends its pushes with `mutable-content: 1` and an
/// `avatar_url`, which lets this extension download the photo before iOS shows the notification. Other pushes pass
/// through unchanged, and so does a Clomni push whose photo does not arrive in time: the text never waits for it.
///
/// Uses Foundation and UserNotifications only; the extension does not link the Clomni SDK. Its state is behind a
/// lock: the download finishes on URLSession's queue, the deadline on another.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var download: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              content.userInfo["clomni"] as? String == "1",
              let avatar = (content.userInfo["avatar_url"] as? String).flatMap(URL.init(string:)),
              avatar.scheme == "https" else {
            return contentHandler(request.content)
        }
        let download = URLSession.shared.downloadTask(with: avatar) { [weak self] location, response, _ in
            // The downloaded file is deleted when this closure returns, so it is moved first.
            let attachment = location.flatMap { NotificationService.attachment(from: $0, response: response) }
            self?.finish(with: attachment)
        }
        lock.lock()
        self.contentHandler = contentHandler
        self.content = content
        self.download = download
        lock.unlock()
        download.resume()
    }

    /// The system's deadline (about 30 seconds) is near: the notification goes out without the photo.
    override func serviceExtensionTimeWillExpire() {
        lock.lock()
        let download = self.download
        lock.unlock()
        download?.cancel()
        finish(with: nil)
    }

    /// Hands the notification to iOS once, whichever of the download and the deadline comes first.
    private func finish(with attachment: UNNotificationAttachment?) {
        lock.lock()
        let handler = contentHandler
        let content = self.content
        contentHandler = nil
        lock.unlock()
        guard let handler, let content else { return }
        if let attachment { content.attachments = [attachment] }
        handler(content)
    }

    /// iOS recognises an image attachment by its file extension: JPEG, PNG or GIF.
    private static func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let types = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"]
        let fromPath = response?.url?.pathExtension.lowercased()
        guard let ext = response?.mimeType.flatMap({ types[$0] })
                ?? (["jpg", "jpeg", "png", "gif"].contains(fromPath ?? "") ? fromPath : nil) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            // iOS moves the file into its own store; it is not ours to delete afterwards.
            return try UNNotificationAttachment(identifier: "avatar", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }
}
```

### Test it

1. Run the app on a real iPhone (the simulator cannot receive APNs pushes from Clomni), allow notifications and open
   the Messenger once.
2. In the panel: **Push** in the side menu → **Test push** → choose the device → **Send**.

## Problems

| Symptom | What to do |
|---|---|
| `api_key səhvdir və ya bu platforma üçün deyil` | Use the `ios_…` key, not the Android one |
| The Messenger does not open, the log says `no window to present the messenger from yet` | Call `present` after a screen is shown |
| `font family "…" is not in the app; the system font stays` | Add the font file to the target and to `UIAppFonts` |
| Test push says `BadEnvironmentKeyInToken` | The APNs key is limited to one environment. Make a key for Sandbox & Production ([Push keys](08-push-keys.md)) |
| Test push says `DeviceTokenNotForTopic` | The Bundle ID under **Push** is not the app's Bundle ID |
| No device in the Test push list | Notifications are not allowed on the phone, or `setDeviceToken` is never called |
| The app crashes on a notification tap with "Call must be made on main thread" | Mark the delegate methods `@MainActor` as above |

Logs are in the Xcode console and in Console.app: subsystem `ai.clomni.messenger`, category `Clomni`. More in
[Troubleshooting](09-troubleshooting.md).
