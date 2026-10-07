import ClomniMessenger
import UIKit
import UserNotifications

// @preconcurrency: the delegate methods below run on the main actor, as the rest of an app delegate does (Swift 6).
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // UI tests: no account, no push prompt (UITestMode).
        if UITestMode.isOn { return true }
        // From Clomni: Channels → Mobile app. The iOS API key, not the Android one. A build may set them instead
        // (build settings CLOMNI_APP_ID and CLOMNI_API_KEY, into Info.plist), as the TestFlight build does.
        Clomni.initialize(appId: Self.infoValue("CLOMNI_APP_ID") ?? "app_xxxxxxxx",
                          apiKey: Self.infoValue("CLOMNI_API_KEY") ?? "ios_xxxxxxxx")
        #if DEBUG
        Clomni.setLogLevel(.debug)
        #endif

        // Push: the Push Notifications capability, and the APNs key (.p8) in the Clomni panel.
        UNUserNotificationCenter.current().delegate = self
        // UI tests: a tap on a notification without a real push (UITestPushTap), and no push prompt.
        if UITestPushTap.start(self) { return true }
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    /// An Info.plist value, nil when the build left it empty.
    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Clomni.setDeviceToken(deviceToken)
    }

    // A push while the app is open. Clomni's are not shown while the messenger is open: it shows the message itself.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // A tap on a notification: a Clomni push opens its conversation.
    // On the main actor, not nonisolated: the system may call this from a background queue, and Swift calls the
    // system's completion handler where this method ends. Ended off the main thread, UIKit stops the app ("Call must
    // be made on main thread").
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // The app's own push.
    }
}
