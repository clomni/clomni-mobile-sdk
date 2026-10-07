import Foundation
#if DEBUG
@_spi(ClomniUITesting) import ClomniMessenger
#endif

/// ClomniExampleUITests start the app with `-ClomniDemoConversation`: no Clomni account and no push prompt; the
/// messenger's conversation screen opens over a fixed conversation as soon as the app is up. Not for an app to copy.
@MainActor
enum UITestMode {
    static var isOn: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ClomniDemoConversation")
        #else
        return false
        #endif
    }

    static func start() {
        #if DEBUG
        // Once the app's window is there to present from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Clomni.presentDemoConversation() }
        #endif
    }
}
