import Foundation
#if DEBUG
@_spi(ClomniUITesting) import ClomniMessenger
#endif

/// ClomniExampleUITests start the app with `-ClomniDemoConversation`, `-ClomniDemoHome`, `-ClomniDemoTabs` or
/// `-ClomniDemoLauncher`: no Clomni account and no push prompt; the messenger's conversation screen (over a fixed
/// conversation), Home, or the messenger with its tab bar opens as soon as the app is up, or the launcher is turned on
/// where an app initializes the SDK. Not for an app to copy.
@MainActor
enum UITestMode {
    static var isOn: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-ClomniDemoConversation") || arguments.contains("-ClomniDemoHome")
            || arguments.contains("-ClomniDemoTabs") || launcher
        #else
        return false
        #endif
    }

    private static var launcher: Bool {
        ProcessInfo.processInfo.arguments.contains("-ClomniDemoLauncher")
    }

    /// From `application(_:didFinishLaunchingWithOptions:)`, where an app calls `initialize`: before the app's scene
    /// and window are up.
    static func launching() {
        #if DEBUG
        if launcher { Clomni.startDemoLauncher() }
        #endif
    }

    static func start() {
        #if DEBUG
        if launcher { return }
        // Once the app's window is there to present from.
        let arguments = ProcessInfo.processInfo.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if arguments.contains("-ClomniDemoTabs") {
                Clomni.presentDemoTabs()
            } else if arguments.contains("-ClomniDemoHome") {
                Clomni.presentDemoHome()
            } else {
                Clomni.presentDemoConversation()
            }
        }
        #endif
    }
}
