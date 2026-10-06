import ClomniMessenger
import Foundation

// What Runtime/iOS/ClomniIOS.cs calls: C functions over the ClomniMessenger pod. Strings arrive as UTF-8 (NULL for
// null), dictionaries as JSON text, flags as 0/1. The SDK's events go back to the receiver object as
// "name" or "name\ntext" through UnitySendMessage, whose pointer ClomniUnityBridge.mm hands over.

public typealias ClomniUnitySend = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void

private var unitySend: ClomniUnitySend?
private var receiver = "ClomniMessenger"
private var unreadListener: UUID?

@_cdecl("clomni_unity_set_sender")
public func clomniUnitySetSender(_ name: UnsafePointer<CChar>?, _ send: ClomniUnitySend?) {
    if let name = text(name) { receiver = name }
    unitySend = send
}

@_cdecl("clomni_initialize")
public func clomniInitialize(_ appId: UnsafePointer<CChar>?, _ apiKey: UnsafePointer<CChar>?,
                             _ region: UnsafePointer<CChar>?) {
    Clomni.initialize(appId: text(appId) ?? "", apiKey: text(apiKey) ?? "", region: text(region) ?? "eu")
    Clomni.onMessengerOpened = { source in emit("messengerOpened", source) }
    Clomni.onMessengerClosed = { emit("messengerClosed") }
    Clomni.onConversationStarted = { id in emit("conversationStarted", id) }
    Clomni.onFlowCompleted = { flowId in emit("flowCompleted", flowId) }
    if unreadListener == nil {
        unreadListener = Clomni.addUnreadCountListener { count in emit("unreadCountChanged", String(count)) }
    }
}

@_cdecl("clomni_login_user")
public func clomniLoginUser(_ userId: UnsafePointer<CChar>?, _ email: UnsafePointer<CChar>?,
                            _ phone: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?,
                            _ userHash: UnsafePointer<CChar>?) {
    Clomni.loginUser(ClomniUser(userId: text(userId), email: text(email), phone: text(phone), name: text(name)),
                     userHash: text(userHash))
}

@_cdecl("clomni_login_unidentified_user")
public func clomniLoginUnidentifiedUser() {
    Clomni.loginUnidentifiedUser()
}

@_cdecl("clomni_update_user")
public func clomniUpdateUser(_ name: UnsafePointer<CChar>?, _ language: UnsafePointer<CChar>?,
                             _ customAttributes: UnsafePointer<CChar>?) {
    Clomni.updateUser(name: text(name), language: text(language), customAttributes: object(customAttributes))
}

@_cdecl("clomni_logout")
public func clomniLogout() {
    Clomni.logout()
}

@_cdecl("clomni_set_log_level")
public func clomniSetLogLevel(_ level: UnsafePointer<CChar>?) {
    let levels: [String: ClomniLogLevel] = ["none": .none, "error": .error, "warning": .warning, "info": .info,
                                             "debug": .debug]
    guard let name = text(level), let known = levels[name] else {
        return NSLog("[Clomni] setLogLevel: unknown level \"%@\"", text(level) ?? "")
    }
    Clomni.setLogLevel(known)
}

@_cdecl("clomni_set_typeface")
public func clomniSetTypeface(_ familyName: UnsafePointer<CChar>?) {
    Clomni.setTypeface(text(familyName))
}

@_cdecl("clomni_set_theme")
public func clomniSetTheme(_ primaryColor: UnsafePointer<CChar>?, _ typeface: UnsafePointer<CChar>?,
                           _ mode: UnsafePointer<CChar>?) {
    let modes: [String: ClomniThemeMode] = ["light": .light, "dark": .dark, "system": .system]
    Clomni.setTheme(primaryColor: text(primaryColor), typeface: text(typeface), mode: text(mode).flatMap { modes[$0] })
}

@_cdecl("clomni_set_sounds_enabled")
public func clomniSetSoundsEnabled(_ enabled: Int32) {
    Clomni.setSoundsEnabled(enabled != 0)
}

@_cdecl("clomni_set_language")
public func clomniSetLanguage(_ language: UnsafePointer<CChar>?) {
    Clomni.setLanguage(text(language))
}

/// While C# has an OnLink listener, the messenger's links go to it as "link" and the SDK leaves them be.
@_cdecl("clomni_set_link_listener")
public func clomniSetLinkListener(_ enabled: Int32) {
    if enabled != 0 {
        Clomni.onLink = { url in emit("link", url.absoluteString) }
    } else {
        Clomni.onLink = nil
    }
}

@_cdecl("clomni_present")
public func clomniPresent(_ source: UnsafePointer<CChar>?) {
    Clomni.present(source: text(source))
}

@_cdecl("clomni_present_new_conversation")
public func clomniPresentNewConversation(_ source: UnsafePointer<CChar>?) {
    Clomni.presentNewConversation(source: text(source))
}

@_cdecl("clomni_present_conversation")
public func clomniPresentConversation(_ conversationId: UnsafePointer<CChar>?) {
    Clomni.presentConversation(text(conversationId) ?? "")
}

@_cdecl("clomni_dismiss")
public func clomniDismiss() {
    Clomni.dismiss()
}

@_cdecl("clomni_start_flow")
public func clomniStartFlow(_ event: UnsafePointer<CChar>?, _ data: UnsafePointer<CChar>?, _ openMessenger: Int32,
                            _ source: UnsafePointer<CChar>?) {
    Clomni.startFlow(text(event) ?? "", data: object(data) ?? [:], openMessenger: openMessenger != 0,
                     source: text(source))
}

@_cdecl("clomni_set_launcher_visible")
public func clomniSetLauncherVisible(_ visible: Int32) {
    Clomni.setLauncherVisible(visible != 0)
}

@_cdecl("clomni_set_bottom_padding")
public func clomniSetBottomPadding(_ padding: Double) {
    Clomni.setBottomPadding(padding)
}

/// The APNs device token as hex text, as Unity's notification packages give it.
@_cdecl("clomni_set_device_token")
public func clomniSetDeviceToken(_ hex: UnsafePointer<CChar>?) {
    guard let token = text(hex).flatMap(bytes(hex:)) else {
        return NSLog("[Clomni] setDeviceToken: not an APNs token in hex; nothing registered")
    }
    Clomni.setDeviceToken(token)
}

@_cdecl("clomni_handle_push")
public func clomniHandlePush(_ data: UnsafePointer<CChar>?) {
    _ = Clomni.handlePush(object(data) ?? [:])
}

@_cdecl("clomni_should_show_foreground")
public func clomniShouldShowForeground(_ data: UnsafePointer<CChar>?) -> Int32 {
    Clomni.shouldShowForeground(object(data) ?? [:]) ? 1 : 0
}

private func emit(_ name: String, _ value: String? = nil) {
    guard let unitySend else { return }
    let message = value.map { "\(name)\n\($0)" } ?? name
    receiver.withCString { target in
        "OnClomniEvent".withCString { method in
            message.withCString { unitySend(target, method, $0) }
        }
    }
}

private func text(_ value: UnsafePointer<CChar>?) -> String? {
    value.map { String(cString: $0) }
}

private func object(_ json: UnsafePointer<CChar>?) -> [String: Any]? {
    guard let data = text(json)?.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// "ab01…" → bytes; nil for anything else.
private func bytes(hex: String) -> Data? {
    let digits = Array(hex.utf8)
    guard !digits.isEmpty, digits.count % 2 == 0 else { return nil }
    var result = Data(capacity: digits.count / 2)
    var index = 0
    while index < digits.count {
        guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
        result.append(high << 4 | low)
        index += 2
    }
    return result
}

private func nibble(_ digit: UInt8) -> UInt8? {
    switch digit {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return digit - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return digit - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return digit - UInt8(ascii: "A") + 10
    default: return nil
    }
}
