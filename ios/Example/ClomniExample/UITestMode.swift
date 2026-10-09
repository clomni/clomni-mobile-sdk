import Foundation
#if DEBUG
@_spi(ClomniUITesting) import ClomniMessenger
#endif

/// ClomniExampleUITests start the app with `-ClomniDemoConversation` or `-ClomniDemoHome`: no Clomni account and no
/// push prompt; the messenger's conversation screen (over a fixed conversation) or Home opens as soon as the app is
/// up. Not for an app to copy.
@MainActor
enum UITestMode {
    static var isOn: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-ClomniDemoConversation") || arguments.contains("-ClomniDemoHome")
        #else
        return false
        #endif
    }

    static func start() {
        #if DEBUG
        // Once the app's window is there to present from.
        let home = ProcessInfo.processInfo.arguments.contains("-ClomniDemoHome")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if home { Clomni.presentDemoHome() } else { Clomni.presentDemoConversation() }
        }
        #endif
    }
}
