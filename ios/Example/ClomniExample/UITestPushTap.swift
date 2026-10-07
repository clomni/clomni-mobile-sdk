import Foundation
import UIKit
import UserNotifications

/// ClomniExampleUITests start the app with `-ClomniPushTap conv_a,conv_b,…`: taps on Clomni notifications without a
/// real push. The first comes at launch (a cold start), each next one `interval` after the one before. Each
/// reaches the app delegate as UIKit sends a real one: its Objective-C method, called from a background queue, with a
/// completion handler that has to be called on the main thread, as UIKit's has. Not for an app to copy.
@MainActor
enum UITestPushTap {
    private static var pending: [String] = []
    private static weak var delegate: NSObject?
    private static var timer: Timer?
    /// Room for the test to close the messenger between two taps, on a slow runner too.
    private static let interval: TimeInterval = 12

    /// true when the UI tests asked for taps: the app then asks for no push permission.
    static func start(_ delegate: NSObject & UNUserNotificationCenterDelegate) -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-ClomniPushTap"), flag + 1 < arguments.count else { return false }
        pending = arguments[flag + 1].split(separator: ",").map(String.init)
        self.delegate = delegate
        tapNext()
        // On a timer, not on coming back from the home screen: the runner's simulator never reported the app leaving
        // the foreground (f22aecb to 015fa4d), with a home press or with Springboard brought to the front.
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            MainActor.assumeIsolated { UITestPushTap.pending.isEmpty ? timer.invalidate() : UITestPushTap.tapNext() }
        }
        return true
        #else
        return false
        #endif
    }

    private static func tapNext() {
        guard let delegate = Self.delegate, !pending.isEmpty else { return }
        let id = pending.removeFirst()
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Clomni", "body": "Salam"]] as [String: Any],
            "clomni": "1", "type": "message", "conversation_id": id, "title": "Clomni", "body": "Salam",
            "unread_total": 1,
        ]
        let tap = SystemTap(delegate: delegate, response: StandInResponse(userInfo))
        DispatchQueue.global(qos: .userInitiated).async { tap.run() }
    }
}

/// `userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:` as UIKit calls it.
private struct SystemTap: @unchecked Sendable {
    let delegate: NSObject
    let response: NSObject

    func run() {
        typealias DidReceive = @convention(c) (NSObject, Selector, UNUserNotificationCenter, NSObject,
                                               @escaping @convention(block) () -> Void) -> Void
        let selector = NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")
        guard let method = delegate.method(for: selector) else { preconditionFailure("no \(selector) on the delegate") }
        let didReceive = unsafeBitCast(method, to: DidReceive.self)
        didReceive(delegate, selector, UNUserNotificationCenter.current(), response) {
            // What UIKit's own completion handler checks.
            precondition(Thread.isMainThread, "Call must be made on main thread")
        }
    }
}

/// Only what the delegate reads, `notification.request.content.userInfo`: a real UNNotificationResponse comes only
/// from a real notification.
private final class StandInResponse: NSObject {
    @objc let notification: StandInNotification

    init(_ userInfo: [AnyHashable: Any]) {
        notification = StandInNotification(userInfo)
    }
}

private final class StandInNotification: NSObject {
    @objc let request: UNNotificationRequest

    init(_ userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        request = UNNotificationRequest(identifier: "clomni-ui-test", content: content, trigger: nil)
    }
}
