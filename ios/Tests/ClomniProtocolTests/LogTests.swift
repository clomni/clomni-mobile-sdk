import Foundation
#if canImport(os)
import os
#endif
import XCTest
@testable import ClomniProtocol

final class LogTests: XCTestCase {
    private let log = LogCapture()
    private let levels = Locked<[LogLevel]>([])

    override func setUp() {
        super.setUp()
        ClomniLog.reset()
        let log = log
        let levels = levels
        ClomniLog.handler = { level, line in
            levels.write { $0.append(level) }
            log.append(ClomniLog.format(level, line))
        }
    }

    override func tearDown() {
        ClomniLog.reset()
        super.tearDown()
    }

    func testWarningsAndErrorsByDefault() {
        XCTAssertEqual(ClomniLog.level, .warning)
        ClomniLog.debug("socket closed")
        ClomniLog.info("refresh token refused; logging in again")
        ClomniLog.warning("config: not JSON, dropped")
        ClomniLog.error("api_key səhvdir və ya bu platforma üçün deyil")
        XCTAssertEqual(log.lines, ["[Clomni] warning: config: not JSON, dropped",
                                   "[Clomni] error: api_key səhvdir və ya bu platforma üçün deyil"])
    }

    func testEachLevelWritesItselfAndWhatIsAboveIt() {
        for (limit, expected) in [(LogLevel.error, 1), (.warning, 2), (.info, 3), (.debug, 4)] {
            ClomniLog.level = limit
            levels.write { $0 = [] }
            for level in [LogLevel.debug, .info, .warning, .error] {
                ClomniLog.write(level, "line")
            }
            XCTAssertEqual(levels.read { $0.count }, expected, "\(limit)")
            XCTAssertTrue(levels.read { $0.allSatisfy { $0 <= limit } })
        }
    }

    func testNothingIsWrittenOrEvenMadeWhenOff() {
        ClomniLog.level = nil
        var made = false
        ClomniLog.error({ made = true; return "x" }())
        XCTAssertFalse(made)
        XCTAssertTrue(log.lines.isEmpty)
    }

    /// Input the protocol drops still reaches the log, at its level.
    func testProtocolLinesHaveLevels() {
        ClomniLog.level = .debug
        XCTAssertNil(ProtocolJSON.parseMessage(Data("{}".utf8)))
        _ = ProtocolJSON.parseEvent(#"{"event":"conversation.rated","data":{},"ts":"2026-10-01T10:30:01Z"}"#)
        XCTAssertEqual(levels.read { $0 }, [.warning, .debug])
        XCTAssertTrue(log.lines[1].hasPrefix("[Clomni] debug: unknown event"))
    }

    #if canImport(os)
    /// CM-087: what the app asked for shows where developers look. As `.debug` and `.info` the lines were hidden in
    /// Console.app and `log stream` (and so in the React Native and Flutter log commands) unless told otherwise.
    func testEveryLevelIsVisibleInTheSystemLog() {
        XCTAssertEqual(ClomniLog.osLogType(.error), .error)
        for level in [LogLevel.warning, .info, .debug] {
            XCTAssertEqual(ClomniLog.osLogType(level), .default, level.name)
        }
    }
    #endif

    func testTheSystemLogTakesALine() {
        ClomniLog.reset()
        ClomniLog.system(.debug, "the system log takes any line")
        XCTAssertEqual(LogLevel.allLevels.map(\.name), ["error", "warning", "info", "debug"])
    }
}

private extension LogLevel {
    static let allLevels: [LogLevel] = [.error, .warning, .info, .debug]
}
