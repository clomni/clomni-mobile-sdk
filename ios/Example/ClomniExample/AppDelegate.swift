import ClomniMessenger
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // From Clomni: Channels → Mobile app. The iOS API key, not the Android one.
        Clomni.initialize(appId: "app_xxxxxxxx", apiKey: "ios_xxxxxxxx")
        #if DEBUG
        Clomni.setLogLevel(.debug)
        #endif

        // Push: the Push Notifications capability, and the APNs key (.p8) in the Clomni panel.
        UNUserNotificationCenter.current().delegate = self
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Clomni.setDeviceToken(deviceToken)
    }

    // A push while the app is open. Clomni's are not shown while the messenger is open: it shows the message itself.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // A tap on a notification: a Clomni push opens its conversation.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if Clomni.handlePush(userInfo) { return }
        // The app's own push.
    }
}
