// The part of Flutter's iOS plugin API that ClomniFlutterPlugin.swift uses, as Swift sees it, for type-checking the
// plugin where there is no Flutter for iOS (Linux). Not shipped; scripts/typecheck-ios-plugin.sh only.
import Foundation

public typealias FlutterResult = (Any?) -> Void
public typealias FlutterEventSink = (Any?) -> Void
public let FlutterMethodNotImplemented = NSObject()

public protocol FlutterBinaryMessenger: AnyObject {}

public protocol FlutterPlugin: NSObjectProtocol {
    static func register(with registrar: FlutterPluginRegistrar)
}

public protocol FlutterPluginRegistrar: AnyObject {
    func messenger() -> FlutterBinaryMessenger
    func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel)
}

public protocol FlutterStreamHandler: NSObjectProtocol {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError?
    func onCancel(withArguments arguments: Any?) -> FlutterError?
}

public final class FlutterMethodCall: NSObject {
    public let method: String
    public let arguments: Any?

    public init(methodName method: String, arguments: Any?) {
        self.method = method
        self.arguments = arguments
    }
}

public final class FlutterError: NSObject {
    public init(code: String, message: String?, details: Any?) {}
}

public final class FlutterMethodChannel: NSObject {
    public init(name: String, binaryMessenger messenger: FlutterBinaryMessenger) {}
}

public final class FlutterEventChannel: NSObject {
    public init(name: String, binaryMessenger messenger: FlutterBinaryMessenger) {}
    public func setStreamHandler(_ handler: FlutterStreamHandler?) {}
}
