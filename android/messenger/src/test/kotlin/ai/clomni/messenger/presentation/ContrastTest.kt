package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.ProtocolJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Brief 8·7.6, contrast 4.5:1: every text colour on every background it is drawn on, light and dark, for Apar as the
 * server sends it and for brand colours the SDK derives (a dark blue, a light yellow, a red, a near-white). The
 * header's text is large (the greeting is 22 sp) and takes the contract's 3:1.
 */
class ContrastTest {
    private fun brand(color: String) = ProtocolJson().parseConfig("""{"brand":{"name":"A","primary_color":"$color"}}""")!!.brand

    private val brands = listOf(Fixture.aparConfig.brand, brand("#1F9D63"), brand("#0A66C2"), brand("#FFD400"), brand("#E5484D"), brand("#F4F4F4"))

    /** Text colour, background, what it is, the ratio it needs. */
    private fun pairs(theme: ClomniTheme) = with(theme.colors) {
        val capsule = theme.capsule
        listOf(
            Triple(textPrimary, background, "text on the background"),
            Triple(textPrimary, canvas, "text on Home's canvas"),
            Triple(textPrimary, surface, "text in a bubble"),
            Triple(textSecondary, background, "grey text on the background"),
            Triple(textSecondary, canvas, "\"Powered by Clomni\" on the canvas"),
            Triple(textSecondary, surface, "the composer's placeholder"),
            // CM-077: the offline capsule's 92% over the brand's colour and over the page alike.
            Triple(capsule.text, capsule.fill.over(headerFrom, capsule.opacity), "the offline capsule on the brand"),
            Triple(capsule.text, capsule.fill.over(background, capsule.opacity), "the offline capsule on the page"),
            Triple(onPrimary, primary, "the user's messages, \"Göndər\""),
            Triple(primaryText, background, "a pill, \"Yeni söhbət başlat\""),
            Triple(primaryText, surface, "a link in a bubble"),
            Triple(errorText, background, "\"Göndərilmədi\""),
            Triple(errorText, surface, "a form field's error"),
            Triple(RgbColor.WHITE, badge, "the launcher's count"),
            Triple(ClomniTheme.readableText(textSecondary), textSecondary, "an avatar's initial"),
            Triple(primary.readableOn(listOf(RgbColor.WHITE)), RgbColor.WHITE, "the brand's initial in the logo square"),
        ).map { (text, behind, what) -> Check(text, behind, what, 4.5) } + listOf(
            Check(headerText, headerFrom, "the header's text, top", 3.0),
            Check(headerText, headerTo, "the header's text, bottom", 3.0),
        )
    }

    private data class Check(val text: RgbColor, val behind: RgbColor, val what: String, val needs: Double) {
        val ratio get() = text.contrast(behind)
    }

    @Test
    fun everyTextReads() {
        val failures = mutableListOf<String>()
        var checked = 0
        for (brand in brands) {
            for (dark in listOf(false, true)) {
                for (check in pairs(ClomniTheme.make(brand, dark))) {
                    checked++
                    if (check.ratio < check.needs) {
                        failures += "${brand.primaryColor} ${if (dark) "dark" else "light"}: ${check.what} ${check.text} on ${check.behind} " +
                            "is %.2f:1".format(check.ratio)
                    }
                }
            }
        }
        assertEquals(216, checked)
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    /** The adjusted colours stay as close to the brand as 4.5:1 allows. */
    @Test
    fun brandColoursMoveOnlyAsFarAsNeeded() {
        val light = ClomniTheme.make(Fixture.aparConfig.brand, dark = false).colors
        assertEquals("#1F9D63 is 3.46:1 on white", "#187B4E", light.primaryText.hex)
        assertEquals(light.primaryText.hsl.hue, light.primary.hsl.hue, 1.0)
        val dark = ClomniTheme.make(Fixture.aparConfig.brand, dark = true).colors
        assertEquals("reads as it is", dark.primary, dark.primaryText)
        assertEquals(light.unread.hsl.hue, light.errorText.hsl.hue, 1.0)
        assertEquals("#D61E24", light.errorText.hex)
        assertEquals("#E12D33", light.badge.hex)
    }
}
