package ai.clomni.messenger.presentation

import org.junit.Assert.assertEquals
import org.junit.Test

/** APPEARANCE-CONTRACT 1: the smallest width that covers the picture on this screen, as WebP. */
class ImageSizingTest {
    private val logo = "https://app.clomni.ai/v1/images/AbC"

    @Test
    fun theSmallestWidthThatCoversThePicture() {
        // A 28 dp logo: mdpi 28 → 48, xhdpi 56 → 96, xxhdpi 84 → 96, xxxhdpi 112 → 144.
        assertEquals("https://app.clomni.ai/v1/images/AbC?w=48&format=webp", ImageSizing.url(logo, ImageSizing.Kind.ICON, 28f, 1f))
        assertEquals("$logo?w=96&format=webp", ImageSizing.url(logo, ImageSizing.Kind.ICON, 28f, 2f))
        assertEquals("$logo?w=96&format=webp", ImageSizing.url(logo, ImageSizing.Kind.ICON, 28f, 3f))
        assertEquals("$logo?w=144&format=webp", ImageSizing.url(logo, ImageSizing.Kind.ICON, 28f, 4f))
        assertEquals("larger than the largest: the largest", "$logo?w=144&format=webp", ImageSizing.url(logo, ImageSizing.Kind.ICON, 48f, 3.5f))
        // A 411 dp wide header: 2.625x 1079 → 1080, 1.5x 617 → 720, 300 dp at 1x → 360.
        assertEquals("$logo?w=1080&format=webp", ImageSizing.url(logo, ImageSizing.Kind.HEADER, 411f, 2.625f))
        assertEquals("$logo?w=720&format=webp", ImageSizing.url(logo, ImageSizing.Kind.HEADER, 411f, 1.5f))
        assertEquals("$logo?w=360&format=webp", ImageSizing.url(logo, ImageSizing.Kind.HEADER, 300f, 1f))
    }

    @Test
    fun theUrlsOwnQueryStays() {
        assertEquals(
            "$logo?sig=x1&w=48&format=webp",
            ImageSizing.url("$logo?sig=x1&w=1080&format=png", ImageSizing.Kind.ICON, 24f, 2f),
        )
        assertEquals("not an http URL: as it is", "file:///a.png", ImageSizing.url("file:///a.png", ImageSizing.Kind.ICON, 24f, 2f))
    }
}
