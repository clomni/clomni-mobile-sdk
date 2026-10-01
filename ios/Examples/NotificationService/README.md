# Operator photo on Clomni notifications (optional)

Without this extension a Clomni notification shows the title ("Leyla · Apar") and the text. With it, the operator's
photo appears next to them.

1. In Xcode: File → New → Target → Notification Service Extension. Deployment target iOS 15 or later.
2. Replace the generated `NotificationService.swift` with [NotificationService.swift](NotificationService.swift).
   The extension does not need the Clomni SDK.
3. If the app already has a Notification Service Extension, keep it and add the Clomni branch: pushes with
   `"clomni": "1"` and an `avatar_url`.

Clomni sends every push with `mutable-content: 1`, so nothing else is needed on the server side.

## The app's side

The app target needs the Push Notifications capability (Signing & Capabilities), and the APNs key (.p8) goes into the
App SDK inbox's Push tab in Clomni.

```swift
import ClomniMessenger
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_8x2k…", apiKey: "ios_…")
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Clomni.setDeviceToken(token)
    }

    // A push while the app is open: not shown while the user is reading that conversation.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Clomni.shouldShowForeground(notification) ? [.banner, .sound, .list] : [])
    }

    // A tap: the conversation opens.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if !Clomni.handlePush(userInfo) {
            // The app's own push.
        }
        completionHandler()
    }
}
```

The APNs environment is read from the app's signature: a build signed with a development profile registers its
token for the sandbox, App Store and TestFlight builds for production.
