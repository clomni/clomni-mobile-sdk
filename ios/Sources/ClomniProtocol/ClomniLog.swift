import Foundation
#if canImport(os)
import os
#endif

/// How much the SDK writes to the log; `Clomni.setLogLevel` chooses.
package enum LogLevel: Int, Sendable, Comparable {
    /// The integration is wrong (api key, user_hash, initialize missing), or what the app asked for failed.
    case error = 1
    /// Something was dropped or could not be done; the SDK carries on.
    case warning
    /// Expected, but worth knowing: a session opened again, a newer server's message shown as its fallback text.
    case info
    /// Everything else, for a bug report.
    case debug

    package static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    package var name: String {
        switch self {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "info"
        case .debug: return "debug"
        }
    }
}

/// The SDK's log. Lines up to `level` go to `handler`: the system log by default (Xcode's console, Console.app),
/// each as `[Clomni] warning: …`.
package enum ClomniLog {
    package static let defaultLevel = LogLevel.warning

    /// The most detailed level written; nil writes nothing.
    package static var level: LogLevel? {
        get { state.read { $0.level } }
        set { state.write { $0.level = newValue } }
    }

    /// Where the lines go; tests collect them here.
    package static var handler: @Sendable (LogLevel, String) -> Void {
        get { state.read { $0.handler } }
        set { state.write { $0.handler = newValue } }
    }

    package static func reset() {
        state.write { $0 = Settings() }
    }

    package static func error(_ line: @autoclosure () -> String) { write(.error, line()) }
    package static func warning(_ line: @autoclosure () -> String) { write(.warning, line()) }
    package static func info(_ line: @autoclosure () -> String) { write(.info, line()) }
    package static func debug(_ line: @autoclosure () -> String) { write(.debug, line()) }

    /// The line is only made when its level is written.
    package static func write(_ level: LogLevel, _ line: @autoclosure () -> String) {
        let settings = state.read { $0 }
        guard let limit = settings.level, level <= limit else { return }
        settings.handler(level, line())
    }

    package static func format(_ level: LogLevel, _ line: String) -> String {
        "[Clomni] \(level.name): \(line)"
    }

    package static let system: @Sendable (LogLevel, String) -> Void = { level, line in
        #if canImport(os)
        logger.log(level: osLogType(level), "\(format(level, line), privacy: .public)")
        #else
        print(format(level, line))
        #endif
    }

    #if canImport(os)
    private static let logger = Logger(subsystem: "ai.clomni.messenger", category: "Clomni")

    /// Errors as errors; every other line as the system log's default. The lines below `warning` are written only
    /// when the app asked for them (`setLogLevel`), and as `.info` or `.debug` Console.app, `log stream` and the
    /// React Native and Flutter log commands hid them unless told otherwise (CM-087): the level is in the line.
    package static func osLogType(_ level: LogLevel) -> OSLogType {
        level == .error ? .error : .default
    }
    #endif

    private struct Settings {
        var level: LogLevel? = ClomniLog.defaultLevel
        var handler: @Sendable (LogLevel, String) -> Void = ClomniLog.system
    }

    private static let state = Locked(Settings())
}

/// A value behind a lock, for the few settings any thread may read.
package final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    package init(_ value: Value) {
        self.value = value
    }

    package func read<T>(_ body: (Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(value)
    }

    package func write<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
