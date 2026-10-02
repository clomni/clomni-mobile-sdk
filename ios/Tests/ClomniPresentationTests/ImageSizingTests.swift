import Foundation
import XCTest
@testable import ClomniPresentation

final class ImageSizingTests: XCTestCase {
    private let logo = URL(string: "https://app.clomni.ai/v1/images/AbC")!

    func testTheSmallestWidthThatCoversThePicture() {
        // A 28 pt logo: @1x 28 → 48, @2x 56 → 96, @3x 84 → 96.
        XCTAssertEqual(ImageSizing.url(logo, kind: .icon, points: 28, scale: 1).absoluteString,
                       "https://app.clomni.ai/v1/images/AbC?w=48&format=webp")
        XCTAssertEqual(ImageSizing.url(logo, kind: .icon, points: 28, scale: 2).query, "w=96&format=webp")
        XCTAssertEqual(ImageSizing.url(logo, kind: .icon, points: 28, scale: 3).query, "w=96&format=webp")
        XCTAssertEqual(ImageSizing.url(logo, kind: .icon, points: 48, scale: 3).query, "w=144&format=webp",
                       "larger than the largest: the largest")
        // A 390 pt wide header: @2x 780 → 1080, @1x → 720.
        XCTAssertEqual(ImageSizing.url(logo, kind: .header, points: 390, scale: 2).query, "w=1080&format=webp")
        XCTAssertEqual(ImageSizing.url(logo, kind: .header, points: 390, scale: 1).query, "w=720&format=webp")
        XCTAssertEqual(ImageSizing.url(logo, kind: .header, points: 300, scale: 1).query, "w=360&format=webp")
    }

    func testTheURLsOwnQueryStays() {
        let signed = URL(string: "https://app.clomni.ai/v1/images/AbC?sig=x1&w=1080&format=png")!
        XCTAssertEqual(ImageSizing.url(signed, kind: .icon, points: 24, scale: 2).query, "sig=x1&w=48&format=webp")
    }
}
