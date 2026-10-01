import Foundation
import XCTest
@testable import ClomniPresentation

final class SVGPathTests: XCTestCase {
    private typealias P = SVGPath.Point

    private func p(_ x: Double, _ y: Double) -> P { P(x: x, y: y) }

    private func end(_ segment: SVGPath.Segment) -> P? {
        switch segment {
        case .move(let point), .line(let point): return point
        case .cubic(_, _, let point): return point
        case .close: return nil
        }
    }

    func testLinesAbsoluteAndRelative() throws {
        let path = try XCTUnwrap(SVGPath("M1 2L3 4H5V6h1v1l1 1zm2 2 1 0"))
        XCTAssertEqual(path.segments, [.move(p(1, 2)), .line(p(3, 4)), .line(p(5, 4)), .line(p(5, 6)), .line(p(6, 6)),
                                       .line(p(6, 7)), .line(p(7, 8)), .close,
                                       // After z the pen is back at 1,2; "m2 2" moves from there, "1 0" is a line.
                                       .move(p(3, 4)), .line(p(4, 4))])
    }

    func testCompactNumbers() throws {
        let path = try XCTUnwrap(SVGPath("M.5-.5l1.5.5-1e1,2E-1"))
        XCTAssertEqual(path.segments, [.move(p(0.5, -0.5)), .line(p(2, 0)), .line(p(-8, 0.2))])
    }

    func testCurvesAndSmoothCurves() throws {
        let path = try XCTUnwrap(SVGPath("M0 0C1 1 2 1 3 0S5-1 6 0c1 1 2 1 3 0s2-1 3 0"))
        XCTAssertEqual(path.segments[1], .cubic(p(1, 1), p(2, 1), p(3, 0)))
        // S reflects the previous second control point (2,1) about the current point (3,0).
        XCTAssertEqual(path.segments[2], .cubic(p(4, -1), p(5, -1), p(6, 0)))
        XCTAssertEqual(path.segments[3], .cubic(p(7, 1), p(8, 1), p(9, 0)))
        XCTAssertEqual(path.segments[4], .cubic(p(10, -1), p(11, -1), p(12, 0)))
        // S without a curve before it uses the current point.
        XCTAssertEqual(try XCTUnwrap(SVGPath("M0 0L1 1S2 2 3 3")).segments[2], .cubic(p(1, 1), p(2, 2), p(3, 3)))
    }

    func testQuadraticCurves() throws {
        let path = try XCTUnwrap(SVGPath("M0 0Q3 3 6 0T12 0"))
        XCTAssertEqual(path.segments[1], .cubic(p(2, 2), p(4, 2), p(6, 0)))
        // T reflects the control (3,3) about (6,0): (9,-3).
        XCTAssertEqual(path.segments[2], .cubic(p(8, -2), p(10, -2), p(12, 0)))
    }

    func testArcsBecomeCubicsOnTheCircle() throws {
        // Half a circle of radius 10 around (10,0), drawn through y = 10 (sweep 1 in y-down coordinates).
        let path = try XCTUnwrap(SVGPath("M0 0A10 10 0 0 1 20 0"))
        XCTAssertEqual(path.segments.count, 3, "180° in two 90° pieces")
        XCTAssertEqual(end(path.segments[2]), p(20, 0))
        guard case .cubic(let c1, let c2, let mid) = path.segments[1] else { return XCTFail() }
        XCTAssertEqual(mid.x, 10, accuracy: 1e-9)
        XCTAssertEqual(abs(mid.y), 10, accuracy: 1e-9)
        // Points along the first piece stay on the circle (the cubic approximation is good to 0.03%).
        let start = p(0, 0)
        for step in 1..<10 {
            let t = Double(step) / 10
            let u = 1 - t
            let x = u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * mid.x
            let y = u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * mid.y
            XCTAssertEqual(((x - 10) * (x - 10) + y * y).squareRoot(), 10, accuracy: 0.01)
        }
        // Compact flags, as icon sets write them; a zero radius is a straight line.
        let compact = try XCTUnwrap(SVGPath("M2 2a1 1 0 011 1a0 1 0 011 1"))
        XCTAssertEqual(end(compact.segments[compact.segments.count - 2]), p(3, 3))
        XCTAssertEqual(compact.segments.last, .line(p(4, 4)))
        // Radii too small for the distance grow until the arc fits: still ends at the target.
        let small = try XCTUnwrap(SVGPath("M0 0A1 1 0 1 0 10 0"))
        XCTAssertEqual(end(small.segments.last!)!.x, 10, accuracy: 1e-9)
        // A rotated ellipse.
        let rotated = try XCTUnwrap(SVGPath("M0 0A5 10 45 1 1 4 4"))
        XCTAssertEqual(end(rotated.segments.last!), p(4, 4))
        XCTAssertGreaterThan(rotated.segments.count, 2, "the long way round")
    }

    func testInvalidPaths() {
        for data in ["", "   ", "L1 1", "M1", "M1 2 3", "M1 2X3 4", "M0 0A1 1 0 2 1 1 1", "M0 0z 1 1", "M0 0C1 1 2"] {
            XCTAssertNil(SVGPath(data), data)
        }
    }

    /// Every brand mark parses and fills its 24×24 box.
    func testBrandMarks() throws {
        XCTAssertEqual(Set(BrandMarks.paths.keys), Set(BrandMarks.styles.keys))
        for slug in BrandMarks.paths.keys.sorted() {
            let mark = try XCTUnwrap(BrandMarks.mark(for: slug), slug)
            let box = mark.path.bounds
            XCTAssertGreaterThanOrEqual(box.minX, -0.6, slug)
            XCTAssertGreaterThanOrEqual(box.minY, -0.6, slug)
            XCTAssertLessThanOrEqual(box.maxX, 24.6, slug)
            XCTAssertLessThanOrEqual(box.maxY, 24.6, slug)
            XCTAssertGreaterThan(max(box.maxX - box.minX, box.maxY - box.minY), 20, "\(slug) fills the box")
            guard case .move? = mark.path.segments.first else { return XCTFail("\(slug) starts with a move") }
            XCTAssertNotNil(RGBColor(hex: mark.color), slug)
        }
        XCTAssertEqual(BrandMarks.mark(for: "twitter")?.name, "X")
        XCTAssertNil(BrandMarks.mark(for: "mastodon"))
    }

    func testChannelItems() throws {
        let strings = ClomniStrings(language: "az")
        func item(_ type: String, _ url: String) -> ChannelItem {
            ChannelItem(type: type, url: URL(string: url)!, strings: strings)
        }
        let instagram = item("instagram", "https://instagram.com/apar.az")
        guard case .brand(let path, let color) = instagram.glyph else { return XCTFail("\(instagram.glyph)") }
        XCTAssertEqual(color.hex, "#FF0069")
        XCTAssertEqual(path, BrandMarks.mark(for: "instagram")?.path)
        XCTAssertEqual(instagram.accessibilityLabel, "Instagram")
        XCTAssertEqual(item("LinkedIn", "https://linkedin.com/company/apar").accessibilityLabel, "LinkedIn")
        XCTAssertEqual(item("email", "mailto:support@apar.az").glyph, .symbol("envelope"))
        XCTAssertEqual(item("support", "mailto:a@b.az").accessibilityLabel, "E-poçt", "a mailto: link is email")
        XCTAssertEqual(item("call", "tel:+994501234567").glyph, .symbol("phone"))
        XCTAssertEqual(item("call", "tel:+994501234567").accessibilityLabel, "Telefon")
        let unknown = item("mastodon", "https://social.az/@apar")
        XCTAssertEqual(unknown.glyph, .symbol("link"))
        XCTAssertEqual(unknown.accessibilityLabel, "social.az")
        XCTAssertNotEqual(item("instagram", "https://a").id, item("instagram", "https://b").id)
    }
}
