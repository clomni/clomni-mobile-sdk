import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

final class LimitedMarkdownTests: XCTestCase {
    func testOperatorMarkdown() {
        // Fixture 02.
        let runs = LimitedMarkdown.parse(
            "**Gedişinizi yoxladıq.** Balansınıza *2 AZN* qaytarıldı.\nƏtraflı: [şərtlər](https://example.com/sertler)")
        XCTAssertEqual(runs, [
            TextRun("Gedişinizi yoxladıq.", bold: true),
            TextRun(" Balansınıza "),
            TextRun("2 AZN", italic: true),
            TextRun(" qaytarıldı.\nƏtraflı: "),
            TextRun("şərtlər", link: URL(string: "https://example.com/sertler")),
        ])
    }

    func testOnlySafeLinksSurvive() {
        // Fixture 06: javascript: keeps its text only, tel: works.
        let runs = LimitedMarkdown.parse("Bu linkə basmayın: [oyun](javascript:alert(1)) və [zəng](tel:+994501234567)")
        XCTAssertEqual(runs, [TextRun("Bu linkə basmayın: oyun və "),
                              TextRun("zəng", link: URL(string: "tel:+994501234567"))])
        XCTAssertNil(LimitedMarkdown.parse("[sayt](http://example.com)").first?.link, "http is not allowed")
        XCTAssertNil(LimitedMarkdown.parse("[x](data:text/html,hi)").first?.link)
        XCTAssertEqual(LimitedMarkdown.parse("[poçt](mailto:a@b.az)").first?.link?.scheme, "mailto")
        XCTAssertEqual(LimitedMarkdown.plainText("[a](https://x) **b**"), "a b")
    }

    func testMarkersWithoutTheirPairAreText() {
        XCTAssertEqual(LimitedMarkdown.parse("2*3 və 2 * 3 * 4"), [TextRun("2*3 və 2 * 3 * 4")])
        XCTAssertEqual(LimitedMarkdown.parse("**yarım"), [TextRun("**yarım")])
        XCTAssertEqual(LimitedMarkdown.parse("[yarım](https://x"), [TextRun("[yarım](https://x")])
        XCTAssertEqual(LimitedMarkdown.parse("[](https://x)"), [TextRun("[](https://x)")])
        XCTAssertEqual(LimitedMarkdown.parse("[a]\n(https://x)"), [TextRun("[a]\n(https://x)")])
        XCTAssertEqual(LimitedMarkdown.parse("👍🙏"), [TextRun("👍🙏")])
        XCTAssertEqual(LimitedMarkdown.parse(""), [])
    }

    func testNesting() {
        XCTAssertEqual(LimitedMarkdown.parse("*kursiv **qalın** kursiv*"), [
            TextRun("kursiv ", italic: true), TextRun("qalın", bold: true, italic: true), TextRun(" kursiv", italic: true),
        ])
        XCTAssertEqual(LimitedMarkdown.parse("**[link](https://x)**"), [TextRun("link", bold: true, link: URL(string: "https://x"))])
    }
}

/// CM-087: addresses, emails and phone numbers written as plain text are links.
final class TextLinksTests: XCTestCase {
    /// What was found, as written and as its URL.
    private func links(_ text: String) -> [String] {
        TextLinks.detect(text).map { "\(text[$0.range]) → \($0.url.absoluteString)" }
    }

    func testAddresses() {
        XCTAssertEqual(links("Sayt: https://example.com/sertler?x=1#y, ətraflı."),
                       ["https://example.com/sertler?x=1#y → https://example.com/sertler?x=1#y"])
        XCTAssertEqual(links("Köhnə http://example.com və www.example.com/qiymet."),
                       ["http://example.com → http://example.com", "www.example.com/qiymet → https://www.example.com/qiymet"])
        XCTAssertEqual(links("(bax: https://example.com) və https://en.wikipedia.org/wiki/Baku_(city)!"),
                       ["https://example.com → https://example.com",
                        "https://en.wikipedia.org/wiki/Baku_(city) → https://en.wikipedia.org/wiki/Baku_(city)"])
        XCTAssertEqual(links("HTTPS://EXAMPLE.COM"), ["HTTPS://EXAMPLE.COM → HTTPS://EXAMPLE.COM"])
        XCTAssertEqual(links("https://example.com/ödəniş"), ["https://example.com/ödəniş → https://example.com/%C3%B6d%C9%99ni%C5%9F"])
        XCTAssertEqual(links("link:https://example.com"), ["https://example.com → https://example.com"])
        XCTAssertEqual(links("https:// www. www.example https://localhost"), [], "no host, or none at all")
    }

    /// A bare domain is a link as an email and a phone number are (the RN test on Android, CM-087), when it ends in a
    /// known top-level domain: numbers, versions, file names and abbreviations are not.
    func testBareDomains() {
        XCTAssertEqual(links("Bizim sayt clomni.ai, ətraflı orada."), ["clomni.ai → https://clomni.ai"])
        XCTAssertEqual(links("(example.com.az/qiymet?x=1) və shop-1.example.co/ödəniş."),
                       ["example.com.az/qiymet?x=1 → https://example.com.az/qiymet?x=1",
                        "shop-1.example.co/ödəniş → https://shop-1.example.co/%C3%B6d%C9%99ni%C5%9F"])
        XCTAssertEqual(links("Qeydiyyat clomni.ai-da, sonra «Clomni.ai»."),
                       ["clomni.ai → https://clomni.ai", "Clomni.ai → https://Clomni.ai"])
        XCTAssertEqual(links("awww.example.com"), ["awww.example.com → https://awww.example.com"])
        XCTAssertEqual(links("Versiya 1.5, v1.0, 3.14.az, fayl.txt, index.html, e.g. və s. Salam.Az qaldı. Ad.Soyad"), [],
                       "numbers, versions, files, abbreviations, a sentence with no space after its dot")
        XCTAssertEqual(links("aysel@clomni.ai https://clomni.ai www.clomni.ai"),
                       ["aysel@clomni.ai → mailto:aysel@clomni.ai", "https://clomni.ai → https://clomni.ai",
                        "www.clomni.ai → https://www.clomni.ai"], "an email or an address stays what it is")
        XCTAssertEqual(links("-clomni.ai clomni-.ai clomni..ai .ai"), [])
    }

    func testEmails() {
        XCTAssertEqual(links("Yazın: info@example.com."), ["info@example.com → mailto:info@example.com"])
        XCTAssertEqual(links("<aysel.m+test@mail.example.com>"), ["aysel.m+test@mail.example.com → mailto:aysel.m+test@mail.example.com"])
        XCTAssertEqual(links("a@b @example.com x@y.1 ödə@example.com x@.az"), [])
    }

    func testPhones() {
        XCTAssertEqual(links("Zəng: +994 50 123 45 67, ya da (012) 555-12-34."),
                       ["+994 50 123 45 67 → tel:+994501234567", "(012) 555-12-34 → tel:0125551234"])
        XCTAssertEqual(links("+994501234567 və 0501234567"),
                       ["+994501234567 → tel:+994501234567", "0501234567 → tel:0501234567"])
        XCTAssertEqual(links("Sifariş 12345678, tarix 2026-10-01, saat 10:30, kod A123456789, 1234567890123456"), [],
                       "8 digits, a date, a time, glued to letters, over 15 digits")
        XCTAssertEqual(links("https://example.com/12345678901 info12345678901@example.com"),
                       ["https://example.com/12345678901 → https://example.com/12345678901",
                        "info12345678901@example.com → mailto:info12345678901@example.com"], "never inside an address")
    }

    func testLinkify() {
        let runs = TextLinks.linkify([TextRun("Bax "), TextRun("www.example.com və 0501234567", bold: true),
                                      TextRun("şərtlər", link: URL(string: "https://example.com/sertler"))])
        XCTAssertEqual(runs, [
            TextRun("Bax "),
            TextRun("www.example.com", bold: true, link: URL(string: "https://www.example.com")),
            TextRun(" və ", bold: true),
            TextRun("0501234567", bold: true, link: URL(string: "tel:0501234567")),
            TextRun("şərtlər", link: URL(string: "https://example.com/sertler")),
        ])
        XCTAssertEqual(TextLinks.linkify([TextRun("Salam 👋")]), [TextRun("Salam 👋")])
        XCTAssertEqual(TextLinks.linkify([]), [])
    }
}

final class FormInputTests: XCTestCase {
    private let strings = ClomniStrings(language: "az")

    private func form(_ file: String) -> MessageContent.Form {
        guard case .form(let form)? = ProtocolJSON.parseMessage(Fixture.data(file))?.content else {
            fatalError("\(file) is not a form")
        }
        return form
    }

    func testErrors() {
        let all = form("20-form-all-field-types.json")
        let empty = FormInput.errors(all, values: [:], strings: strings)
        XCTAssertEqual(empty, ["name": "Bu sahəni doldurun", "phone": "Bu sahəni doldurun",
                               "city": "Variantlardan birini seçin"], "required fields only")
        let wrong = FormInput.errors(all, values: [
            "name": "Aysel", "details": String(repeating: "a", count: 1_001), "phone": "12", "email": "aysel@",
            "ride_count": "iki", "city": "london", "date": "1 oktyabr",
        ], strings: strings)
        XCTAssertEqual(wrong, ["details": "Ən çox 1000 simvol", "phone": "Telefon nömrəsi düzgün deyil",
                               "email": "E-poçt düzgün deyil", "ride_count": "Rəqəm yazın",
                               "city": "Variantlardan birini seçin", "date": "Bu sahəni doldurun"])
        let good = FormInput.errors(all, values: [
            "name": "Aysel", "phone": "050 123 45 67", "email": "aysel@example.com", "ride_count": "2,5",
            "city": "baku", "date": "2026-10-01",
        ], strings: strings)
        XCTAssertEqual(good, [:])
    }

    func testPayloadMatchesFixture48() {
        let contact = form("19-form-contact.json")
        let payload = FormInput.payload(contact, values: ["name": " Aysel Məmmədova ", "phone": "+994 50 123 45 67"])
        XCTAssertEqual(payload, ["name": "Aysel Məmmədova", "phone": "+994501234567", "email": ""])
        let all = form("20-form-all-field-types.json")
        XCTAssertEqual(FormInput.payload(all, values: ["ride_count": "3"])["ride_count"], 3)
        XCTAssertEqual(FormInput.payload(all, values: ["ride_count": "x"])["ride_count"], "x")
    }

    func testPhones() {
        XCTAssertEqual(FormInput.phone("+994 50 123 45 67", defaultCountry: nil), "+994501234567")
        XCTAssertEqual(FormInput.phone("050 123 45 67", defaultCountry: "AZ"), "+994501234567")
        XCTAssertEqual(FormInput.phone("501234567", defaultCountry: "az"), "+994501234567")
        XCTAssertEqual(FormInput.phone("00994501234567", defaultCountry: nil), "+994501234567")
        XCTAssertEqual(FormInput.phone("(555) 123-4567", defaultCountry: "US"), "+15551234567")
        XCTAssertNil(FormInput.phone("501234567", defaultCountry: nil), "no country to call")
        XCTAssertNil(FormInput.phone("50 123 abc", defaultCountry: "AZ"))
        XCTAssertNil(FormInput.phone("+99450", defaultCountry: nil))
    }

    func testPrefillAndSubmitted() {
        let contact = form("19-form-contact.json")
        XCTAssertEqual(FormInput.prefill(contact, known: ["name": "Aysel", "email": "a@b.az", "phone": ""]),
                       ["name": "Aysel", "email": "a@b.az"])
        let sent = form("21-form-submitted.json")
        XCTAssertEqual(FormInput.submittedLines(sent).map { "\($0.label): \($0.value)" },
                       ["Ad, soyad: Aysel Məmmədova", "Telefon: +994501234567", "Email: aysel@example.com"])
        XCTAssertTrue(FormInput.submittedLines(contact).isEmpty)
        let withSelect = MessageContent(type: "form", json: [
            "form_id": "frm_1", "submit_title": "OK", "submitted": ["city": "baku", "count": 2, "ok": true, "x": nil],
            "fields": [["key": "city", "type": "select", "label": "Şəhər", "options": [["value": "baku", "label": "Bakı"]]],
                       ["key": "count", "type": "number", "label": "Say"], ["key": "ok", "type": "text", "label": "OK"],
                       ["key": "x", "type": "text", "label": "X"]],
        ])
        guard case .form(let selectForm) = withSelect else { return XCTFail() }
        XCTAssertEqual(FormInput.submittedLines(selectForm).map(\.value), ["Bakı", "2", "✓"])
    }
}

final class MediaTests: XCTestCase {
    func testImageBox() {
        XCTAssertTrue(Media.imageBox(width: 1280, height: 960) == (220, 165, true))
        XCTAssertTrue(Media.imageBox(width: 600, height: 1200) == (150, 300, true))
        XCTAssertTrue(Media.imageBox(width: 100, height: 50) == (100, 50, true), "never larger than the image")
        XCTAssertTrue(Media.imageBox(width: nil, height: 960) == (220, 165, false), "unknown: a 4:3 placeholder")
        XCTAssertTrue(Media.imageBox(width: 0, height: 0) == (220, 165, false))
    }

    func testUploadSize() {
        XCTAssertTrue(Media.uploadSize(width: 4_000, height: 3_000) == (2_048, 1_536))
        XCTAssertTrue(Media.uploadSize(width: 1_000, height: 3_000) == (683, 2_048))
        XCTAssertTrue(Media.uploadSize(width: 800, height: 600) == (800, 600))
    }

    func testFileLabels() {
        XCTAssertEqual(Media.fileSize(820, language: "az"), "820 B")
        XCTAssertEqual(Media.fileSize(182_340, language: "az"), "182 KB")
        XCTAssertEqual(Media.fileSize(1_400_000, language: "az"), "1,4 MB")
        XCTAssertEqual(Media.fileSize(1_400_000, language: "en"), "1.4 MB")
        XCTAssertEqual(Media.fileSymbol(mime: "application/pdf"), "doc.richtext")
        XCTAssertEqual(Media.fileSymbol(mime: "image/png"), "photo")
        XCTAssertEqual(Media.fileSymbol(mime: "audio/m4a"), "waveform")
        XCTAssertEqual(Media.fileSymbol(mime: "video/mp4"), "film")
        XCTAssertEqual(Media.fileSymbol(mime: "application/zip"), "doc")
    }

    func testOrdinals() {
        let suffixes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 1000, 21, 36]
            .map { "\($0)-\(ClomniStrings.azerbaijaniOrdinalSuffix($0))" }
        XCTAssertEqual(suffixes, ["1-ci", "2-ci", "3-cü", "4-cü", "5-ci", "6-cı", "7-ci", "8-ci", "9-cu", "10-cu",
                                  "20-ci", "30-cu", "40-cı", "50-ci", "60-cı", "70-ci", "80-ci", "90-cı", "100-cü",
                                  "1000-ci", "21-ci", "36-cı"])
        XCTAssertEqual(ClomniStrings(language: "az").buttonPosition(title: "Azərbaycan dili", index: 1, count: 3),
                       "Azərbaycan dili, 1-ci, cəmi 3")
        XCTAssertEqual(ClomniStrings(language: "en").buttonPosition(title: "English", index: 2, count: 3),
                       "English, 2 of 3")
        XCTAssertEqual(ClomniStrings(language: "ru").buttonPosition(title: "Русский", index: 3, count: 3),
                       "Русский, 3 из 3")
    }
}

/// CM-087 (the RN test on Android): the attachment sheet has the camera when the app may use it; without the app's
/// NSCameraUsageDescription iOS would stop the app as it opens, so the row is not there and the log says why, once.
final class CameraOptionTests: XCTestCase {
    override func tearDown() {
        ClomniLog.reset()
        super.tearDown()
    }

    func testTheCameraIsOfferedOnlyWithItsUsageDescription() {
        let lines = Locked<[String]>([])
        ClomniLog.handler = { level, line in lines.write { $0.append(ClomniLog.format(level, line)) } }
        XCTAssertTrue(CameraOption.offered(deviceHasCamera: true, usageDescription: "Söhbətə şəkil çəkib göndərmək üçün."))
        XCTAssertFalse(CameraOption.offered(deviceHasCamera: false, usageDescription: "Şəkil"), "no camera (a simulator)")
        XCTAssertEqual(lines.read { $0 }, [])
        XCTAssertFalse(CameraOption.offered(deviceHasCamera: true, usageDescription: nil))
        XCTAssertFalse(CameraOption.offered(deviceHasCamera: true, usageDescription: "  "), "an empty text is none")
        XCTAssertEqual(lines.read { $0 },
                       ["[Clomni] warning: the camera is not offered: the app's Info.plist has no NSCameraUsageDescription"],
                       "said once")
    }
}
