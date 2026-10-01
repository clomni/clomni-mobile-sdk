import Foundation
import XCTest
@testable import ClomniProtocol

/// Response bodies of protocol/openapi.yaml, and the wire format the SDK keeps on disk.
final class MobileAPITests: ProtocolTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testEveryMessageFixtureSurvivesTheDiskFormat() throws {
        var checked = 0
        for folder in Fixtures.folders {
            for entry in try Fixtures.entries(folder) where entry.schema == "message.json" && entry.isValid {
                let message = try Fixtures.message(entry.file, in: folder)
                let stored = try JSONEncoder().encode(message)
                XCTAssertEqual(try JSONDecoder().decode(Message.self, from: stored), message, entry.file)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 30)
    }

    func testUnknownTypesKeepTheirRawContentOnDisk() throws {
        let message = try Fixtures.message("29-unknown-type.json")
        let stored = try XCTUnwrap(ProtocolJSON.decode(try JSONEncoder().encode(message)))
        XCTAssertEqual(stored["content"], try Fixtures.json("29-unknown-type.json")["content"])
        XCTAssertThrowsError(try JSONDecoder().decode(Message.self, from: data(#"{"id":"msg_1"}"#)))
    }

    func testClientMessagesOnDisk() throws {
        for file in ["45-client-text.json", "48-client-form-submit.json", "52-client-rating.json"] {
            let message = try XCTUnwrap(ProtocolJSON.parseClientMessage(try Fixtures.data(file)))
            XCTAssertEqual(try JSONDecoder().decode(ClientMessage.self, from: try JSONEncoder().encode(message)), message)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: data(#"{"type":"text"}"#)))
    }

    func testSelectNeedsAnOption() {
        let form: JSONValue = ["form_id": "frm_1", "submit_title": "OK",
                               "fields": [["key": "city", "type": "select", "label": "Şəhər", "options": []]]]
        XCTAssertEqual(MessageContent(type: "form", json: form).kind, "unknown")
    }

    func testSession() throws {
        let session = try XCTUnwrap(ProtocolJSON.parseSession(data(#"""
        {"session_token":"st_9d2f","expires_at":"2026-10-02T10:30:00Z","refresh_token":"rt_4c1e",
         "user":{"id":"usr_12345","anonymous":false,"language":"az"},"ws_url":"wss://app.clomni.ai/v1/realtime","extra":1}
        """#)))
        XCTAssertEqual(session.sessionToken, "st_9d2f")
        XCTAssertEqual(session.refreshToken, "rt_4c1e")
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 1_790_850_600 + 86_400))
        XCTAssertEqual(session.userId, "usr_12345")
        XCTAssertFalse(session.anonymous)
        XCTAssertEqual(session.language, "az")
        XCTAssertEqual(session.wsUrl.absoluteString, "wss://app.clomni.ai/v1/realtime")
        XCTAssertEqual(try JSONDecoder().decode(MobileSession.self, from: try JSONEncoder().encode(session)), session)
        XCTAssertNil(ProtocolJSON.parseSession(data(#"{"session_token":"st_1"}"#)))
    }

    func testConversationAndPages() throws {
        let message = String(decoding: try Fixtures.data("02-text-operator-markdown.json"), as: UTF8.self)
        let conversation = #"""
        {"id":"conv_5521","status":"open","assignee":{"name":"Leyla","avatar_url":null,"online":true},"unread_count":1,
         "last_message":\#(message),"flow":{"flow_id":"flw_apar_az","node_id":"S"},"opened_from":"profile_support",
         "created_at":"2026-10-01T10:30:00Z"}
        """#
        let parsed = try XCTUnwrap(ProtocolJSON.parseConversation(data(conversation)))
        XCTAssertEqual(parsed.id, "conv_5521")
        XCTAssertEqual(parsed.status, .open)
        XCTAssertEqual(parsed.assignee?.name, "Leyla")
        XCTAssertEqual(parsed.assignee?.online, true)
        XCTAssertEqual(parsed.unreadCount, 1)
        XCTAssertEqual(parsed.lastMessage?.id, "msg_f02")
        XCTAssertEqual(parsed.flow, Conversation.FlowStep(flowId: "flw_apar_az", nodeId: "S"))
        XCTAssertEqual(parsed.openedFrom, "profile_support")
        XCTAssertEqual(try JSONDecoder().decode(Conversation.self, from: try JSONEncoder().encode(parsed)), parsed)

        let bare = try XCTUnwrap(ProtocolJSON.parseConversation(data(
            #"{"id":"conv_1","status":"resolved","assignee":null,"last_message":null,"created_at":"2026-10-01T10:30:00Z"}"#)))
        XCTAssertEqual(bare.status, .unknown)
        XCTAssertEqual(bare.unreadCount, 0)
        XCTAssertNil(bare.assignee)
        XCTAssertNil(bare.flow)

        let page = try XCTUnwrap(ProtocolJSON.parseConversationPage(data(
            #"{"conversations":[\#(conversation),{"id":"conv_broken"}],"next_cursor":"c2"}"#)))
        XCTAssertEqual(page.conversations.map(\.id), ["conv_5521"])
        XCTAssertEqual(page.nextCursor, "c2")
        XCTAssertTrue(log.contains("conversations.conversations[1].status: expected a string; item dropped"), "\(log.lines)")

        let messages = try XCTUnwrap(ProtocolJSON.parseMessagePage(data(#"{"messages":[\#(message),{"id":"x"}],"has_more":true}"#)))
        XCTAssertEqual(messages.messages.map(\.id), ["msg_f02"])
        XCTAssertTrue(messages.hasMore)
        XCTAssertNil(ProtocolJSON.parseMessagePage(data(#"{"has_more":false}"#)))

        let created = try XCTUnwrap(ProtocolJSON.parseConversationWithMessages(data(
            #"{"conversation":\#(conversation),"messages":[\#(message)]}"#)))
        XCTAssertEqual(created.conversation, parsed)
        XCTAssertEqual(created.messages.count, 1)

        let started = try XCTUnwrap(ProtocolJSON.parseFlowTrigger(data(
            #"{"started":true,"conversation":{"conversation":\#(conversation),"messages":[]}}"#)))
        XCTAssertTrue(started.started)
        XCTAssertEqual(started.conversation?.conversation.id, "conv_5521")
        XCTAssertEqual(ProtocolJSON.parseFlowTrigger(data(#"{"started":false,"conversation":null}"#)),
                       FlowTriggerResult(started: false, conversation: nil))
    }

    func testUserUploadAndError() throws {
        let user = try XCTUnwrap(ProtocolJSON.parseUser(data(
            #"{"id":"usr_1","anonymous":false,"name":"Aysel","email":null,"language":"az","custom_attributes":{"plan":"premium"}}"#)))
        XCTAssertEqual(user, MobileUser(id: "usr_1", anonymous: false, name: "Aysel", email: nil, phone: nil, language: "az",
                                        customAttributes: ["plan": "premium"]))

        let upload = try XCTUnwrap(ProtocolJSON.parseUpload(data(
            #"{"upload_id":"upl_77ab","url":"https://app.clomni.ai/f/velo.jpg","name":"velo.jpg","size":482113,"mime":"image/jpeg"}"#)))
        XCTAssertEqual(upload.uploadId, "upl_77ab")
        XCTAssertEqual(upload.size, 482_113)

        let error = try XCTUnwrap(ProtocolJSON.parseServerError(data(
            #"{"error":{"code":"validation_failed","message":"phone is invalid","request_id":"req_5f2a","fields":{"phone":"invalid","n":1}}}"#)))
        XCTAssertEqual(error, ServerError(code: "validation_failed", message: "phone is invalid", requestId: "req_5f2a",
                                          fields: ["phone": "invalid"]))
        XCTAssertNil(ProtocolJSON.parseServerError(data("<html>Bad gateway</html>")))
        XCTAssertNil(ProtocolJSON.parseServerError(data(#"{"error":"nope"}"#)))
    }

    func testEventFromDecodedJSON() throws {
        let event = ProtocolJSON.parseEvent(try Fixtures.json("39-event-unread-changed.json"))
        XCTAssertEqual(event?.data, .unreadChanged(total: 2))
        XCTAssertEqual(String(decoding: ProtocolJSON.encode(["b": 1, "a": "x/y"]), as: UTF8.self), #"{"a":"x/y","b":1}"#)
    }
}
