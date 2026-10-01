import Foundation
import XCTest
@testable import ClomniPresentation

final class TypefaceTests: XCTestCase {
    private func family(_ names: [String]) -> Typeface? {
        Typeface(family: "Montserrat", faces: names.map { Typeface.Face(name: $0, weight: Typeface.weight(name: $0, trait: nil)) })
    }

    func testEveryWeightHasAFace() throws {
        let full = try XCTUnwrap(family(["Montserrat-Regular", "Montserrat-Medium", "Montserrat-SemiBold", "Montserrat-Bold",
                                         "Montserrat-Italic", "Montserrat-BoldItalic"]))
        XCTAssertEqual(full.faces.map(\.name), ["Montserrat-Regular", "Montserrat-Medium", "Montserrat-SemiBold",
                                                "Montserrat-Bold"], "no italics")
        XCTAssertEqual(full.face(for: 400), "Montserrat-Regular")
        XCTAssertEqual(full.face(for: 500), "Montserrat-Medium")
        XCTAssertEqual(full.face(for: 600), "Montserrat-SemiBold")
        XCTAssertEqual(full.face(for: 700), "Montserrat-Bold")
    }

    /// A weight the family lacks takes the nearest face of the family, not the system font.
    func testMissingWeightsTakeTheNearestFace() throws {
        let two = try XCTUnwrap(family(["Brand-Regular", "Brand-Bold"]))
        XCTAssertEqual(two.face(for: 500), "Brand-Regular")
        XCTAssertEqual(two.face(for: 600), "Brand-Bold")
        XCTAssertEqual(two.face(for: 900), "Brand-Bold")
        XCTAssertEqual(two.face(for: 100), "Brand-Regular")

        let one = try XCTUnwrap(family(["Brand-Book"]))
        XCTAssertEqual(one.face(for: 700), "Brand-Book")

        // Equal distance: semibold goes heavier, medium lighter.
        let lightAndBlack = try XCTUnwrap(family(["Brand-Light", "Brand-Black", "Brand-Medium"]))
        XCTAssertEqual(lightAndBlack.face(for: 700), "Brand-Black", "200 to both Medium and Black: heavier")
        let regularAndSemibold = try XCTUnwrap(family(["Brand-Regular", "Brand-SemiBold"]))
        XCTAssertEqual(regularAndSemibold.face(for: 500), "Brand-Regular", "100 to both: lighter")
    }

    func testAFamilyWithoutUprightFacesIsNone() {
        XCTAssertNil(family([]))
        XCTAssertNil(family(["Brand-Italic", "Brand-BoldOblique"]))
    }

    func testWeightsFromNamesAndTraits() {
        let names: [(String, Int?)] = [
            ("Montserrat-Thin", 100), ("Inter-ExtraLight", 200), ("Inter-UltraLight", 200), ("Inter-Light", 300),
            ("Inter-Regular", 400), ("Avenir-Book", 400), ("Helvetica-Roman", 400), ("HelveticaNeue-Medium", 500),
            ("AvenirNext-DemiBold", 600), ("Montserrat-SemiBold", 600), ("Montserrat-SemiBoldItalic", 600),
            ("Inter-Bold", 700), ("Inter-ExtraBold", 800), ("Gilroy-UltraBold", 800), ("Inter-Heavy", 800),
            ("Inter-Black", 900), ("Brand", nil), ("Brand-Display", nil),
        ]
        for (name, weight) in names {
            XCTAssertEqual(Typeface.weight(name: name), weight, name)
        }
        XCTAssertEqual(Typeface.weight(name: "Brand-Display", trait: 0.4), 700, "the trait when the name says nothing")
        XCTAssertEqual(Typeface.weight(name: "Brand-Bold", trait: 0), 700, "the name first")
        XCTAssertEqual(Typeface.weight(name: "Brand", trait: nil), 400)
        let traits: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600),
                                       (0.4, 700), (0.56, 800), (0.62, 900), (0.35, 600), (1, 900), (-1, 100)]
        for (trait, weight) in traits {
            XCTAssertEqual(Typeface.weight(trait: trait), weight, "\(trait)")
        }
        XCTAssertTrue(Typeface.isItalic("Brand-LightItalic"))
        XCTAssertFalse(Typeface.isItalic("Italiana"), "a family name is not a style")
    }
}
