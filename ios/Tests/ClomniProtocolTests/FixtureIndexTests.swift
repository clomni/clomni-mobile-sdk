import Foundation
import XCTest
@testable import ClomniProtocol

/// Every file of protocol/fixtures and protocol/examples/brief goes through the parser its index names, the way the
/// server's validator (protocol/scripts/validate.mjs) checks them against the schemas.
final class FixtureIndexTests: ProtocolTestCase {
    private static let contentTypes: Set = ["text", "quick_replies", "image", "file", "form", "system", "card", "rating"]
    private static let events: Set = ["ready", "message.created", "message.updated", "typing", "read",
                                      "conversation.updated", "unread.changed", "config.changed"]

    func testEveryFileIsListedInItsIndex() throws {
        for folder in Fixtures.folders {
            let directory = Fixtures.protocolDir.appendingPathComponent(folder)
            let files = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".json") && $0 != "index.json" })
            let listed = Set(try Fixtures.entries(folder).map(\.file))
            XCTAssertFalse(files.isEmpty, "\(folder) has no files")
            for file in files.subtracting(listed).sorted() {
                XCTFail("\(folder)/\(file) is not listed in index.json, so nothing would check it")
            }
            for file in listed.subtracting(files).sorted() {
                XCTFail("\(folder)/index.json lists \(file), which does not exist")
            }
        }
    }

    func testEveryEntryParsesByItsSchema() throws {
        var checked = 0
        for folder in Fixtures.folders {
            for entry in try Fixtures.entries(folder) {
                let data = try Fixtures.data(entry.file, in: folder)
                let raw = try Fixtures.json(entry.file, in: folder)
                try check(entry, data: data, raw: raw, label: "\(folder)/\(entry.file)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// A valid entry must come out as the type its JSON names; an invalid one only has to be survived (what each one
    /// turns into is pinned in InvalidFixtureTests).
    private func check(_ entry: Fixtures.Entry, data: Data, raw: JSONValue, label: String) throws {
        let parts = entry.schema.components(separatedBy: "#/$defs/")
        switch (parts[0], parts.count == 2 ? parts[1] : nil) {
        case ("message.json", nil):
            let message = ProtocolJSON.parseMessage(data)
            guard entry.isValid else { return }
            let parsed = try XCTUnwrap(message, label)
            let type = try XCTUnwrap(raw["type"]?.stringValue)
            XCTAssertEqual(parsed.type, type, label)
            XCTAssertEqual(parsed.content.kind, Self.contentTypes.contains(type) ? type : "unknown", label)
            XCTAssertEqual(parsed.id, raw["id"]?.stringValue, label)
            XCTAssertEqual(parsed.seq, raw["seq"]?.intValue, label)
            XCTAssertEqual(parsed.fallbackText, raw["fallback_text"]?.stringValue, label)
        case ("message.json", let definition?):
            // A content object on its own (brief 8 · 5.2), parsed as the type its definition is named after.
            let content = MessageContent(type: definition, json: raw)
            if entry.isValid { XCTAssertEqual(content.kind, definition, label) }
        case ("event.json", nil):
            let event = ProtocolJSON.parseEvent(data)
            guard entry.isValid else { return }
            let parsed = try XCTUnwrap(event, label)
            let name = try XCTUnwrap(raw["event"]?.stringValue)
            XCTAssertEqual(parsed.event, name, label)
            XCTAssertEqual(parsed.data.kind, Self.events.contains(name) ? name : "unknown", label)
        case ("config.json", nil):
            let config = ProtocolJSON.parseConfig(data)
            if entry.isValid { XCTAssertNotNil(config, label) }
        case ("conversation-start.json", nil):
            // A body the SDK sends (ApiClient.createConversation, tested there): opened_from and a client_id of 1 to
            // 64 characters, as the SDK builds it.
            let body = ProtocolJSON.decode(data)?.objectValue
            XCTAssertNotNil(body, label)
            let clientId = body?["client_id"]?.stringValue
            let fits = Set(body?.keys.map { $0 } ?? []).isSubset(of: ["opened_from", "client_id"])
                && (body?["client_id"] == nil || clientId.map { (1...64).contains($0.count) } == true)
            XCTAssertEqual(fits, entry.isValid, label)
        case ("realtime-client.json", nil):
            // What the app may send on the socket: pong (RealtimeClient answers every ping, RealtimeTests), and
            // typing, which this SDK sends over REST instead. Anything else is not the app's to send.
            let frame = ProtocolJSON.decode(data)?.objectValue
            let event = frame?["event"]?.stringValue
            let typing = frame?["data"]?.objectValue
            let fits = event == "pong"
                || event == "typing" && typing?["conversation_id"]?.stringValue?.hasPrefix("conv_") == true
                && ["on", "off"].contains(typing?["state"]?.stringValue ?? "")
            XCTAssertEqual(fits, entry.isValid, label)
        case ("appearance.json", nil):
            // The panel's document; the SDK reads only what the server makes of it, config.json.
            XCTAssertNotNil(ProtocolJSON.decode(data), label)
        case ("push.json", nil):
            let push = ProtocolJSON.parsePush(data)
            if entry.isValid { XCTAssertNotNil(push, label) }
        case ("client-message.json", nil):
            let message = ProtocolJSON.parseClientMessage(data)
            guard entry.isValid else { return }
            let parsed = try XCTUnwrap(message, label)
            XCTAssertEqual(ProtocolJSON.decode(ProtocolJSON.encode(parsed)), raw, "\(label) changes on a round trip")
        default:
            XCTFail("\(label): no parser for schema \(entry.schema)")
        }
    }
}

/// What each `"valid": false` fixture turns into: never a crash, and never a silently wrong message.
final class InvalidFixtureTests: ProtocolTestCase {
    func testQuickRepliesWithoutButtonsFallsBackToItsText() throws {
        let message = try Fixtures.message("90-invalid-quick-replies-empty.json")
        guard case .unknown(type: "quick_replies", raw: _) = message.content else {
            return XCTFail("expected unknown content, got \(message.content)")
        }
        XCTAssertEqual(message.fallbackText, "Seçin")
        XCTAssertTrue(log.contains("msg_x90: quick_replies.buttons: expected at least one item"), "\(log.lines)")
    }

    func testMessageWithoutSeqIsDropped() throws {
        XCTAssertNil(ProtocolJSON.parseMessage(try Fixtures.data("91-invalid-missing-seq.json")))
        XCTAssertTrue(log.contains("message.seq: expected an integer"), "\(log.lines)")
    }

    func testOverlongPushBodyIsKeptForTheNotificationToCut() throws {
        let push = try XCTUnwrap(ProtocolJSON.parsePush(try Fixtures.data("92-invalid-push-body-too-long.json")))
        XCTAssertEqual(push.body.count, 181)
    }

    func testEmptyClientTextReadsBack() throws {
        // The composer never sends one; reading it back must still not fail.
        let message = try XCTUnwrap(ProtocolJSON.parseClientMessage(try Fixtures.data("93-invalid-client-text-empty.json")))
        XCTAssertEqual(message.content, .text(""))
    }

    func testSelectWithoutOptionsFallsBack() throws {
        let content = MessageContent(type: "form", json: try Fixtures.json("94-invalid-select-without-options.json"))
        XCTAssertEqual(content.kind, "unknown")
        XCTAssertTrue(log.contains("form.fields[0].options: expected an array"), "\(log.lines)")
    }

    func testUnsupportedLanguageStillShows() throws {
        XCTAssertEqual(try Fixtures.message("95-invalid-lang.json").lang, "de")
    }

    func testInvalidBrandColorTakesTheDefault() throws {
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data("96-invalid-config-color.json")))
        XCTAssertEqual(config.brand.primaryColor, MessengerConfig.Brand.defaultPrimaryColor)
    }

    func testReadyWithoutDataIsIgnored() throws {
        let event = try Fixtures.event("97-invalid-event-ready-without-data.json")
        XCTAssertEqual(event.data, .unknown(name: "ready"))
        XCTAssertTrue(log.contains("ready: ready.data: expected an object; event ignored"), "\(log.lines)")
    }

    func testCardButtonWithPayloadAndUrlKeepsBoth() throws {
        let content = MessageContent(type: "card", json: try Fixtures.json("98-invalid-card-button-both.json"))
        let button = try XCTUnwrap(content.cards?.first?.buttons.first)
        XCTAssertEqual(button.payload, "node:T")
        XCTAssertEqual(button.url?.absoluteString, "https://apar.az")
    }
}
