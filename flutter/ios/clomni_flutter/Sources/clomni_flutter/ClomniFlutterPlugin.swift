import ClomniMessenger
import Foundation
import Flutter
import UIKit

/// The iOS side of clomni_flutter: the method channel's calls go to the iOS SDK (`Clomni`), and the SDK's events go
/// to the event channel as `{name, count?, text?}` while Dart listens. Flutter calls in on the main thread; the SDK's
/// callbacks come on the main thread too, where an event sink must be used.
public final class ClomniFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private var unreadCount = 0
    private var unreadListener: UUID?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = ClomniFlutterPlugin()
        let methods = FlutterMethodChannel(name: "ai.clomni.flutter/methods", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: methods)
        FlutterEventChannel(name: "ai.clomni.flutter/events", binaryMessenger: registrar.messenger())
            .setStreamHandler(plugin)
        plugin.listen()
    }

    /// The app's Dart hears these; native code of the app should not set them as well.
    private func listen() {
        Clomni.onMessengerOpened = { [weak self] source in self?.send("messengerOpened", text: source) }
        Clomni.onMessengerClosed = { [weak self] in self?.send("messengerClosed") }
        Clomni.onConversationStarted = { [weak self] id in self?.send("conversationStarted", text: id) }
        Clomni.onFlowCompleted = { [weak self] flowId in self?.send("flowCompleted", text: flowId) }
        unreadListener = Clomni.addUnreadCountListener { [weak self] count in
            self?.unreadCount = count
            self?.send("unreadCountChanged", count: count)
        }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if let unreadListener { Clomni.removeUnreadCountListener(unreadListener) }
        Clomni.onMessengerOpened = nil
        Clomni.onMessengerClosed = nil
        Clomni.onConversationStarted = nil
        Clomni.onFlowCompleted = nil
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    private func send(_ name: String, count: Int? = nil, text: String? = nil) {
        var event: [String: Any] = ["name": name]
        if let count { event["count"] = count }
        if let text { event["text"] = text }
        sink?(event)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let map = call.arguments as? [String: Any] ?? [:]
        let text = { (key: String) in map[key] as? String }
        switch call.method {
        case "setup":
            guard let appId = text("appId"), let apiKey = text("apiKey") else { return result(Self.badArguments(call)) }
            Clomni.initialize(appId: appId, apiKey: apiKey, region: text("region") ?? "eu")
        case "loginUser":
            let user = map["user"] as? [String: String] ?? [:]
            Clomni.loginUser(ClomniUser(userId: user["userId"], email: user["email"], phone: user["phone"],
                                        name: user["name"]),
                             userHash: text("userHash"))
        case "loginUnidentifiedUser":
            Clomni.loginUnidentifiedUser()
        case "updateUser":
            Clomni.updateUser(name: text("name"), language: text("language"),
                              customAttributes: map["customAttributes"] as? [String: Any])
        case "logout":
            Clomni.logout()
        case "setLogLevel":
            let levels: [String: ClomniLogLevel] = ["none": .none, "error": .error, "warning": .warning,
                                                     "info": .info, "debug": .debug]
            guard let level = (call.arguments as? String).flatMap({ levels[$0] }) else {
                return result(Self.badArguments(call))
            }
            Clomni.setLogLevel(level)
        case "setTypeface":
            Clomni.setTypeface(call.arguments as? String)
        case "setTheme":
            // The SDK checks the colour; the mode is one of Dart's enum's names.
            let modes: [String: ClomniThemeMode] = ["system": .system, "light": .light, "dark": .dark]
            let name = text("mode")
            let mode = name.flatMap { modes[$0] }
            if name != nil, mode == nil { return result(Self.badArguments(call)) }
            Clomni.setTheme(primaryColor: text("primaryColor"), typeface: text("typeface"), mode: mode)
        case "present":
            Clomni.present(source: call.arguments as? String)
        case "presentNewConversation":
            Clomni.presentNewConversation(source: call.arguments as? String)
        case "presentConversation":
            guard let id = call.arguments as? String else { return result(Self.badArguments(call)) }
            Clomni.presentConversation(id)
        case "dismiss":
            Clomni.dismiss()
        case "startFlow":
            guard let event = text("event") else { return result(Self.badArguments(call)) }
            Clomni.startFlow(event, data: map["data"] as? [String: Any] ?? [:],
                             openMessenger: map["openMessenger"] as? Bool ?? false, source: text("source"))
        case "setLauncherVisible":
            Clomni.setLauncherVisible(call.arguments as? Bool ?? false)
        case "setBottomPadding":
            Clomni.setBottomPadding((call.arguments as? NSNumber)?.doubleValue ?? 0)
        case "setDeviceToken":
            // The APNs device token as hex, as Flutter's push plugins give it.
            guard let token = (call.arguments as? String).flatMap(Self.data(hex:)) else {
                return result(Self.badArguments(call))
            }
            Clomni.setDeviceToken(token)
        case "handlePush":
            return result(Clomni.handlePush(map))
        case "shouldShowForeground":
            return result(Clomni.shouldShowForeground(map))
        case "setNotificationIcon":
            break // Android only.
        case "getUnreadCount":
            return result(unreadCount)
        default:
            return result(FlutterMethodNotImplemented)
        }
        result(nil)
    }

    private static func badArguments(_ call: FlutterMethodCall) -> FlutterError {
        FlutterError(code: "bad_arguments", message: "\(call.method): unexpected arguments", details: nil)
    }

    /// "ab01…" → bytes; nil for anything else.
    static func data(hex: String) -> Data? {
        let digits = Array(hex.utf8)
        guard !digits.isEmpty, digits.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = 0
        while index < digits.count {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return Data(bytes)
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return digit - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
