package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LimitedMarkdownTest {
    @Test
    fun operatorMarkdown() {
        // Fixture 02.
        val runs = LimitedMarkdown.parse(
            "**Gedişinizi yoxladıq.** Balansınıza *2 AZN* qaytarıldı.\nƏtraflı: [şərtlər](https://apar.az/sertler)",
        )
        assertEquals(
            listOf(
                TextRun("Gedişinizi yoxladıq.", bold = true),
                TextRun(" Balansınıza "),
                TextRun("2 AZN", italic = true),
                TextRun(" qaytarıldı.\nƏtraflı: "),
                TextRun("şərtlər", link = "https://apar.az/sertler"),
            ),
            runs,
        )
    }

    @Test
    fun onlySafeLinksSurvive() {
        // Fixture 06: javascript: keeps its text only, tel: works.
        val runs = LimitedMarkdown.parse("Bu linkə basmayın: [oyun](javascript:alert(1)) və [zəng](tel:+994501234567)")
        assertEquals(listOf(TextRun("Bu linkə basmayın: oyun və "), TextRun("zəng", link = "tel:+994501234567")), runs)
        assertNull("http is not allowed", LimitedMarkdown.parse("[sayt](http://apar.az)").first().link)
        assertNull(LimitedMarkdown.parse("[x](data:text/html,hi)").first().link)
        assertNull("not a URI at all", LimitedMarkdown.parse("[x](https://a b)").first().link)
        assertNull(LimitedMarkdown.parse("[x](yer)").first().link)
        assertEquals("mailto:a@b.az", LimitedMarkdown.parse("[poçt](mailto:a@b.az)").first().link)
        assertEquals("HTTPS://APAR.AZ", LimitedMarkdown.parse("[a](HTTPS://APAR.AZ)").first().link)
        assertEquals("a b", LimitedMarkdown.plainText("[a](https://x) **b**"))
    }

    @Test
    fun markersWithoutTheirPairAreText() {
        assertEquals(listOf(TextRun("2*3 və 2 * 3 * 4")), LimitedMarkdown.parse("2*3 və 2 * 3 * 4"))
        assertEquals(listOf(TextRun("**yarım")), LimitedMarkdown.parse("**yarım"))
        assertEquals(listOf(TextRun("**")), LimitedMarkdown.parse("**"))
        assertEquals(listOf(TextRun("[yarım](https://x")), LimitedMarkdown.parse("[yarım](https://x"))
        assertEquals(listOf(TextRun("[](https://x)")), LimitedMarkdown.parse("[](https://x)"))
        assertEquals(listOf(TextRun("[a]\n(https://x)")), LimitedMarkdown.parse("[a]\n(https://x)"))
        assertEquals(listOf(TextRun("[a](https://x\n)")), LimitedMarkdown.parse("[a](https://x\n)"))
        assertEquals(listOf(TextRun("[a] (x) [b")), LimitedMarkdown.parse("[a] (x) [b"))
        assertEquals(listOf(TextRun("👍🙏")), LimitedMarkdown.parse("👍🙏"))
        assertEquals(emptyList<TextRun>(), LimitedMarkdown.parse(""))
    }

    @Test
    fun nesting() {
        assertEquals(
            listOf(
                TextRun("kursiv ", italic = true),
                TextRun("qalın", bold = true, italic = true),
                TextRun(" kursiv", italic = true),
            ),
            LimitedMarkdown.parse("*kursiv **qalın** kursiv*"),
        )
        assertEquals(
            listOf(TextRun("link", bold = true, link = "https://x")),
            LimitedMarkdown.parse("**[link](https://x)**"),
        )
        assertEquals(
            "balanced parentheses stay in the target",
            "https://az.wikipedia.org/wiki/Bakı_(şəhər)",
            LimitedMarkdown.parse("[Bakı](https://az.wikipedia.org/wiki/Bakı_(şəhər))").single().link,
        )
    }
}

class FormInputTest {
    private val strings = ClomniStrings("az")
    private val protocol = ProtocolJson()

    private fun form(file: String) =
        protocol.parseMessage(ProtocolFiles.read("fixtures/$file"))!!.content as MessageContent.Form

    @Test
    fun errors() {
        val all = form("20-form-all-field-types.json")
        assertEquals(
            "required fields only",
            mapOf("name" to "Bu sahəni doldurun", "phone" to "Bu sahəni doldurun", "city" to "Variantlardan birini seçin"),
            FormInput.errors(all, emptyMap(), strings),
        )
        val wrong = FormInput.errors(
            all,
            mapOf(
                "name" to "Aysel", "details" to "a".repeat(1_001), "phone" to "12", "email" to "aysel@",
                "ride_count" to "iki", "city" to "london", "date" to "1 oktyabr",
            ),
            strings,
        )
        assertEquals(
            mapOf(
                "details" to "Ən çox 1000 simvol", "phone" to "Telefon nömrəsi düzgün deyil", "email" to "E-poçt düzgün deyil",
                "ride_count" to "Rəqəm yazın", "city" to "Variantlardan birini seçin", "date" to "Bu sahəni doldurun",
            ),
            wrong,
        )
        val good = FormInput.errors(
            all,
            mapOf(
                "name" to "Aysel", "phone" to "050 123 45 67", "email" to "aysel@example.com", "ride_count" to "2,5",
                "city" to "baku", "date" to "2026-10-01",
            ),
            strings,
        )
        assertEquals(emptyMap<String, String>(), good)
    }

    @Test
    fun payloadMatchesFixture48() {
        val contact = form("19-form-contact.json")
        assertEquals(
            mapOf("name" to JsonPrimitive("Aysel Məmmədova"), "phone" to JsonPrimitive("+994501234567"), "email" to JsonPrimitive("")),
            FormInput.payload(contact, mapOf("name" to " Aysel Məmmədova ", "phone" to "+994 50 123 45 67")),
        )
        val all = form("20-form-all-field-types.json")
        assertEquals(JsonPrimitive(3L), FormInput.payload(all, mapOf("ride_count" to "3"))["ride_count"])
        assertEquals(JsonPrimitive(2.5), FormInput.payload(all, mapOf("ride_count" to "2,5"))["ride_count"])
        assertEquals(JsonPrimitive("x"), FormInput.payload(all, mapOf("ride_count" to "x"))["ride_count"])
    }

    @Test
    fun phonesAndNumbers() {
        assertEquals("+994501234567", FormInput.phone("+994 50 123 45 67", null))
        assertEquals("+994501234567", FormInput.phone("050 123 45 67", "AZ"))
        assertEquals("+994501234567", FormInput.phone("501234567", "az"))
        assertEquals("+994501234567", FormInput.phone("00994501234567", null))
        assertEquals("+15551234567", FormInput.phone("(555) 123-4567", "US"))
        assertNull("no country to call", FormInput.phone("501234567", null))
        assertNull(FormInput.phone("501234567", "XX"))
        assertNull(FormInput.phone("50 123 abc", "AZ"))
        assertNull(FormInput.phone("+99450", null))
        assertEquals(2.5, FormInput.number("2,5"))
        assertEquals(-1e3, FormInput.number("-1e3"))
        assertEquals(0.5, FormInput.number(".5"))
        assertNull("Kotlin would read these; a form must not", FormInput.number("2f"))
        assertNull(FormInput.number("0x1p3"))
        assertNull(FormInput.number("NaN"))
        assertNull(FormInput.number("1e999"))
        assertTrue(FormInput.isEmail("a@b.az"))
        assertFalse(FormInput.isEmail("a b@c.az"))
        assertTrue(FormInput.isDate("2026-10-01"))
        assertFalse(FormInput.isDate("2026-10-1"))
    }

    @Test
    fun prefillAndSubmitted() {
        val contact = form("19-form-contact.json")
        assertEquals(
            mapOf("name" to "Aysel", "email" to "a@b.az"),
            FormInput.prefill(contact, mapOf("name" to "Aysel", "email" to "a@b.az", "phone" to "")),
        )
        assertEquals(mapOf("phone" to "+994501234567"), FormInput.prefill(contact, mapOf("phone" to "+994501234567")))
        val sent = form("21-form-submitted.json")
        assertEquals(
            listOf("Ad, soyad: Aysel Məmmədova", "Telefon: +994501234567", "Email: aysel@example.com"),
            FormInput.submittedLines(sent).map { "${it.first}: ${it.second}" },
        )
        assertTrue(FormInput.submittedLines(contact).isEmpty())
        val withSelect = protocol.parseMessage(
            """{"id":"m","conversation_id":"c","type":"form","sender":{"type":"bot"},"created_at":"2026-10-01T10:30:00Z",
               "seq":1,"lang":"az","fallback_text":"f","content":{"form_id":"frm_1","submit_title":"OK",
               "submitted":{"city":"baku","count":2,"rate":2.5,"ok":true,"no":false,"x":null,"list":[1]},
               "fields":[{"key":"city","type":"select","label":"Şəhər","options":[{"value":"baku","label":"Bakı"}]},
                         {"key":"count","type":"number","label":"Say"},{"key":"rate","type":"number","label":"Dərəcə"},
                         {"key":"ok","type":"text","label":"OK"},{"key":"no","type":"text","label":"Yox"},
                         {"key":"x","type":"text","label":"X"},{"key":"list","type":"text","label":"L"},
                         {"key":"missing","type":"text","label":"M"}]}}""",
        )!!.content as MessageContent.Form
        assertEquals(listOf("Bakı", "2", "2.5", "✓", "–"), FormInput.submittedLines(withSelect).map { it.second })
    }
}

class MediaTest {
    @Test
    fun imageBox() {
        assertEquals(Media.Box(220.0, 165.0, true), Media.imageBox(1280, 960))
        assertEquals(Media.Box(150.0, 300.0, true), Media.imageBox(600, 1200))
        assertEquals("never larger than the image", Media.Box(100.0, 50.0, true), Media.imageBox(100, 50))
        assertEquals("unknown: a 4:3 placeholder", Media.Box(220.0, 165.0, false), Media.imageBox(null, 960))
        assertEquals(Media.Box(220.0, 165.0, false), Media.imageBox(0, 0))
    }

    @Test
    fun uploadSize() {
        assertEquals(2_048 to 1_536, Media.uploadSize(4_000, 3_000))
        assertEquals(683 to 2_048, Media.uploadSize(1_000, 3_000))
        assertEquals(800 to 600, Media.uploadSize(800, 600))
    }

    @Test
    fun fileLabels() {
        assertEquals("820 B", Media.fileSize(820, "az"))
        assertEquals("182 KB", Media.fileSize(182_340, "az"))
        assertEquals("1,4 MB", Media.fileSize(1_400_000, "az"))
        assertEquals("1.4 MB", Media.fileSize(1_400_000, "en"))
        assertEquals(Media.FileIcon.PDF, Media.fileIcon("application/pdf"))
        assertEquals(Media.FileIcon.IMAGE, Media.fileIcon("image/png"))
        assertEquals(Media.FileIcon.AUDIO, Media.fileIcon("audio/m4a"))
        assertEquals(Media.FileIcon.VIDEO, Media.fileIcon("video/mp4"))
        assertEquals(Media.FileIcon.DOCUMENT, Media.fileIcon("application/zip"))
    }

    @Test
    fun ordinals() {
        val suffixes = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 1000, 21, 36)
            .map { "$it-${ClomniStrings.azerbaijaniOrdinalSuffix(it)}" }
        assertEquals(
            listOf(
                "1-ci", "2-ci", "3-cü", "4-cü", "5-ci", "6-cı", "7-ci", "8-ci", "9-cu", "10-cu", "20-ci", "30-cu", "40-cı", "50-ci",
                "60-cı", "70-ci", "80-ci", "90-cı", "100-cü", "1000-ci", "21-ci", "36-cı",
            ),
            suffixes,
        )
        assertEquals("Azərbaycan dili, 1-ci, cəmi 3", ClomniStrings("az").buttonPosition("Azərbaycan dili", 1, 3))
        assertEquals("English, 2 of 3", ClomniStrings("en").buttonPosition("English", 2, 3))
        assertEquals("Русский, 3 из 3", ClomniStrings("ru").buttonPosition("Русский", 3, 3))
    }

    @Test
    fun awayUntil() {
        assertEquals("Növbəti iş saatı: 09:00", ClomniStrings("az").format(ClomniStrings.Key.AWAY_UNTIL, "09:00"))
        assertEquals("Next working hours: 09:00", ClomniStrings("en").format(ClomniStrings.Key.AWAY_UNTIL, "09:00"))
        assertEquals("Следующее рабочее время: 09:00", ClomniStrings("ru").format(ClomniStrings.Key.AWAY_UNTIL, "09:00"))
        val panel = ClomniStrings("az", mapOf("away_until" to "Səhər %@-da qayıdacağıq"))
        assertEquals("the panel's own text, brief 7.5", "Səhər 09:00-da qayıdacağıq", panel.format(ClomniStrings.Key.AWAY_UNTIL, "09:00"))
    }
}
