import Foundation
import XCTest
@testable import ClomniProtocol

/// Broken input: never a crash, and a known type with broken content becomes `.unknown` (brief 8 · 3, 8 · 5.5).
final class RobustnessTests: ProtocolTestCase {
    private func message(_ file: String = "01-text-bot.json", _ edit: (JSONValue) -> JSONValue) throws -> Message? {
        ProtocolJSON.parseMessage(edit(try Fixtures.json(file)))
    }

    private func content(_ type: String, _ json: JSONValue) -> MessageContent {
        MessageContent(type: type, json: json)
    }

    func testEnvelopeFieldsTheClientCannotDoWithout() throws {
        for key in ["id", "conversation_id", "type", "sender", "created_at", "seq", "lang", "content", "fallback_text"] {
            XCTAssertNil(try message { $0.setting(key, nil) }, "without \(key)")
        }
        XCTAssertNil(try message { $0.setting("seq", "1") })
        XCTAssertNil(try message { $0.setting("content", "Salam") })
        XCTAssertNil(try message { $0.setting("type", nil, at: ["sender"]) })
        XCTAssertNil(ProtocolJSON.parseMessage(Data("{".utf8)))
        XCTAssertNil(ProtocolJSON.parseMessage(Data(#""msg_1""#.utf8)))
        XCTAssertTrue(log.contains("message: not JSON, dropped"), "\(log.lines)")
    }

    func testOptionalEnvelopeFieldsAreLenient() throws {
        let noClientId = try XCTUnwrap(try message { $0.setting("client_id", 5).setting("meta", nil) })
        XCTAssertNil(noClientId.clientId)

        let brokenFlow = try XCTUnwrap(try message { $0.setting("interactive", nil, at: ["flow"]) })
        XCTAssertNil(brokenFlow.flow)
        XCTAssertTrue(log.contains("msg_f01: message.flow.interactive: expected a boolean; shown without its flow"))

        let noVersion = try XCTUnwrap(try message { $0.setting("version", nil, at: ["flow"]) })
        XCTAssertNil(noVersion.flow?.version)

        let wholeSeq = try XCTUnwrap(try message { $0.setting("seq", 7.0) })
        XCTAssertEqual(wholeSeq.seq, 7)
        XCTAssertNil(try message { $0.setting("seq", 7.5) })
    }

    func testUnknownSenderType() throws {
        let message = try XCTUnwrap(try message { $0.setting("type", "ai_agent", at: ["sender"]) })
        XCTAssertEqual(message.sender.type, .unknown)
        XCTAssertEqual(message.sender.name, "Clomni")
    }

    func testBrokenContentOfKnownTypesFallsBack() throws {
        let broken: [(String, JSONValue)] = [
            ("text", ["text": 5]),
            ("quick_replies", ["buttons": [["id": "b", "title": "T"]]]),
            ("quick_replies", ["buttons": "b"]),
            ("image", ["url": ""]),
            ("file", ["url": "https://a/f.pdf", "name": "f.pdf", "mime": "application/pdf"]),
            ("form", ["form_id": "frm_1", "fields": [], "submit_title": "OK"]),
            ("form", ["form_id": "frm_1", "fields": [["key": "a", "type": "select", "label": "A",
                                                     "options": [["value": "x"]]]], "submit_title": "OK"]),
            ("system", ["event": "operator_joined"]),
            ("card", ["cards": []]),
            ("card", ["cards": [["title": "T", "buttons": [["id": "b", "title": "B"]]]]]),
            ("rating", ["text": "?", "scale": "number_10"]),
            ("text", "Salam"),
        ]
        for (type, json) in broken {
            XCTAssertEqual(content(type, json), .unknown(type: type, raw: json), "\(type) \(json)")
        }
        XCTAssertEqual(log.lines.count, broken.count, "\(log.lines)")
    }

    func testLenientValuesInsideKnownContent() throws {
        let replies = content("quick_replies", ["buttons": [["id": "b", "title": "T", "payload": "p", "icon": 3]],
                                                "layout": "grid", "input_disabled": "yes"]).quickReplies
        XCTAssertEqual(replies?.layout, .vertical)
        XCTAssertEqual(replies?.inputDisabled, false)
        XCTAssertNil(replies?.buttons.first?.icon)

        guard case .image(let image) = content("image", ["url": "https://a/i.png", "width": 0, "height": -3]) else {
            return XCTFail()
        }
        XCTAssertNil(image.width)
        XCTAssertNil(image.height)

        let field = content("form", ["form_id": "frm_1", "submit_title": "OK", "submitted": "yes",
                                     "fields": [["key": "a", "type": "signature", "label": "A", "options": [1]]]]).form
        XCTAssertEqual(field?.fields.first?.type, .text)
        XCTAssertEqual(field?.fields.first?.options, [])
        XCTAssertNil(field?.submitted)

        for (raw, expected) in [(JSONValue.null, MessageContent.RatingComment.hidden), ("none", .hidden),
                                ("required", .required), ("sometimes", .optional)] {
            guard case .rating(let rating) = content("rating", ["text": "?", "scale": "star_5", "comment": raw]) else {
                return XCTFail()
            }
            XCTAssertEqual(rating.scale, .star5)
            XCTAssertEqual(rating.comment, expected, "\(raw)")
        }

        XCTAssertEqual(content("card", ["cards": [["title": "T"]]]).cards?.first?.buttons, [])
        XCTAssertTrue(log.lines.isEmpty, "\(log.lines)")
    }

    func testUnknownTypeWithAnyContent() {
        XCTAssertEqual(content("video", ["url": "https://a/v.mp4"]), .unknown(type: "video", raw: ["url": "https://a/v.mp4"]))
        XCTAssertEqual(content("video", [1, 2]), .unknown(type: "video", raw: [1, 2]))
    }

    func testNoLogHandlerIsFine() {
        ProtocolJSON.logHandler = nil
        XCTAssertNil(ProtocolJSON.parseMessage(Data("{}".utf8)))
        XCTAssertNil(ProtocolJSON.logHandler)
    }
}

final class JSONValueTests: XCTestCase {
    func testLiteralsAndAccessors() {
        let value: JSONValue = ["s": "a", "i": 5, "d": 1.5, "b": true, "n": nil, "a": [1, "x"], "o": ["k": "v"]]
        XCTAssertEqual(value["s"]?.stringValue, "a")
        XCTAssertEqual(value["i"]?.intValue, 5)
        XCTAssertEqual(value["d"]?.doubleValue, 1.5)
        XCTAssertNil(value["d"]?.intValue)
        XCTAssertEqual(value["b"]?.boolValue, true)
        XCTAssertEqual(value["n"], .null)
        XCTAssertEqual(value["a"]?.arrayValue, [1, "x"])
        XCTAssertEqual(value["o"]?.objectValue, ["k": "v"])
        XCTAssertNil(value["missing"])
        XCTAssertNil(JSONValue.string("a")["k"])
        XCTAssertNil(JSONValue.number(1).stringValue)
        XCTAssertNil(JSONValue.string("1").intValue)
        XCTAssertNil(JSONValue.string("true").boolValue)
        XCTAssertNil(JSONValue.bool(true).doubleValue)
        XCTAssertNil(JSONValue.null.arrayValue)
        XCTAssertNil(JSONValue.null.objectValue)
        XCTAssertNil(JSONValue.number(1e300).intValue)
        XCTAssertEqual(JSONValue(dictionaryLiteral: ("k", 1), ("k", 2)), ["k": 2])
    }

    func testRoundTrip() throws {
        let text = #"{"a":[1,2.5,-3,true,false,null,"x\"y"],"b":{"c":{}},"d":"https://a/b","e":1e3}"#
        let value = try XCTUnwrap(ProtocolJSON.decode(Data(text.utf8)))
        XCTAssertEqual(value["e"]?.intValue, 1000)
        XCTAssertEqual(value["a"]?.arrayValue?[3], true)
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(ProtocolJSON.decode(encoded), value)
    }

    func testEncodesWholeNumbersAsIntegersAndNonFiniteAsNull() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let value: JSONValue = ["a": 5, "b": 2.5, "c": .number(.infinity), "d": .number(.nan)]
        XCTAssertEqual(String(decoding: try encoder.encode(value), as: UTF8.self), #"{"a":5,"b":2.5,"c":null,"d":null}"#)
    }

    func testAppValues() {
        let nothing: String? = nil
        let value = JSONValue(any: ["ride_id": "R-1923", "minutes": 18, "amount": 12.5, "late": true, "none": nothing,
                                    "tags": ["a", 1] as [Any], "nested": ["ok": false], "null": NSNull(),
                                    "float": Float(0.5)] as [String: Any?])
        XCTAssertEqual(value, ["ride_id": "R-1923", "minutes": 18, "amount": 12.5, "late": true, "none": nil,
                               "tags": ["a", 1], "nested": ["ok": false], "null": nil, "float": 0.5])
        XCTAssertNil(JSONValue(any: ["when": Date()] as [String: Any]))
        XCTAssertNil(JSONValue(any: [Date()] as [Any]))
        XCTAssertEqual(JSONValue(any: JSONValue.string("x")), "x")
        XCTAssertEqual(JSONValue(any: nil), .null)
    }

    func testDecodeRejectsWhatIsNotJSON() {
        XCTAssertNil(ProtocolJSON.decode(Data()))
        XCTAssertNil(ProtocolJSON.decode(Data("{\"a\":}".utf8)))
        XCTAssertNil(ProtocolJSON.decode(Data([0xff, 0xfe])))
    }
}
