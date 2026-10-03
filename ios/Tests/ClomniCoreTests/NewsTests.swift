import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

/// DESIGN-PASS-2 "Xəbərlər": the news as protocol/schema/news.json has them, cached like the config.
final class NewsTests: EngineTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/fixtures/\(name)"))
    }

    func testTheFixturesRead() throws {
        let news = try XCTUnwrap(ProtocolJSON.parseNews(try fixture("61-news.json")))
        XCTAssertEqual(news.map(\.id), ["news_12", "news_9"])
        XCTAssertEqual(news[0].title, "Yeni zonalar açıldı")
        XCTAssertEqual(news[0].summary, "Yasamal və Nərimanovda 40 yeni parklanma zonası var.")
        XCTAssertEqual(news[0].imageUrl?.absoluteString, "https://app.clomni.ai/v1/images/img_8f2kQ7pZx1Lm3Nb4Vc5D")
        XCTAssertEqual(news[0].button, NewsItem.Button(text: "Xəritəni aç", url: URL(string: "apar://map/zones")!))
        XCTAssertEqual(news[0].publishedAt, Date(timeIntervalSince1970: 1_790_931_600))
        XCTAssertNil(news[1].summary)
        XCTAssertNil(news[1].bodyMarkdown)
        XCTAssertNil(news[1].button)
        XCTAssertEqual(ProtocolJSON.parseNews(try fixture("62-news-empty.json")), [])
        // A button without its link is no button; the item stays.
        let broken = try XCTUnwrap(ProtocolJSON.parseNews(try fixture("63-invalid-news-button-without-url.json")))
        XCTAssertEqual(broken.map(\.id), ["news_12"])
        XCTAssertNil(broken[0].button)
        // An item without a title is left out, the others stay.
        let partly = try XCTUnwrap(ProtocolJSON.parseNews(Data(##"""
            {"items":[{"id":"news_1","published_at":"2026-10-02T09:00:00Z"},
                      {"id":"news_2","title":"Var","published_at":"2026-10-02T09:00:00Z"}]}
            """##.utf8)))
        XCTAssertEqual(partly.map(\.id), ["news_2"])
    }

    func testNewsAreKeptWithTheirETagAndOpeningIsReported() async throws {
        server.newsBody = try XCTUnwrap(ProtocolJSON.decode(try fixture("61-news.json")))
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let first = await phone.engine.refreshNews()
        XCTAssertEqual(first.count, 2)
        let again = await phone.engine.refreshNews()
        XCTAssertEqual(again.count, 2, "304: the kept ones")
        XCTAssertEqual(server.requests("GET", "/news").last?.headers["If-None-Match"], server.newsETag)

        let relaunched = await device(cache: phone.cache, vault: phone.vault)
        let fromDisk = await relaunched.engine.news
        XCTAssertEqual(fromDisk.map(\.id), ["news_12", "news_9"], "from disk before the server answers")

        await phone.engine.newsOpened("news_12")
        let event = try XCTUnwrap(server.requests("POST", "/events").last)
        XCTAssertEqual(body(event)?["event"], "news_opened")
        XCTAssertEqual(body(event)?["data"]?["news_id"], "news_12")
    }
}
