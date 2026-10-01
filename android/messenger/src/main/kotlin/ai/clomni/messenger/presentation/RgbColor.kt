package ai.clomni.messenger.presentation

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** Hue 0…360, saturation and lightness 0…1. */
internal data class Hsl(val hue: Double, val saturation: Double, val lightness: Double)

/** An sRGB colour, with the arithmetic the theme derives its tokens with (the same as the iOS SDK's `RGBColor`). */
internal class RgbColor(red: Double, green: Double, blue: Double) {
    /** 0…1. */
    val red: Double = red.coerceIn(0.0, 1.0)
    val green: Double = green.coerceIn(0.0, 1.0)
    val blue: Double = blue.coerceIn(0.0, 1.0)

    /** "#RRGGBB". */
    val hex: String
        get() = String.format(Locale.ROOT, "#%02X%02X%02X", channel(red), channel(green), channel(blue))

    /** For Compose and Android: opaque ARGB. */
    val argb: Int
        get() = (0xFF shl 24) or (channel(red) shl 16) or (channel(green) shl 8) or channel(blue)

    /** WCAG 2 relative luminance. */
    val luminance: Double
        get() {
            fun linear(channel: Double) = if (channel <= 0.04045) channel / 12.92 else ((channel + 0.055) / 1.055).pow(2.4)
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

    /** WCAG 2 contrast ratio, 1…21. */
    fun contrast(other: RgbColor): Double {
        val light = max(luminance, other.luminance)
        val dark = min(luminance, other.luminance)
        return (light + 0.05) / (dark + 0.05)
    }

    /**
     * One step of the brand palette is 10 points of HSL lightness: `steps(-1)` is the darker tone of the header,
     * `steps(1)` the lighter one dark mode uses.
     */
    fun steps(count: Int): RgbColor {
        val (hue, saturation, lightness) = hsl
        return fromHsl(hue, saturation, lightness + 0.1 * count)
    }

    /** This colour at [opacity] over [background]. */
    fun over(background: RgbColor, opacity: Double) = RgbColor(
        red * opacity + background.red * (1 - opacity),
        green * opacity + background.green * (1 - opacity),
        blue * opacity + background.blue * (1 - opacity),
    )

    val hsl: Hsl
        get() {
            val high = maxOf(red, green, blue)
            val low = minOf(red, green, blue)
            val lightness = (high + low) / 2
            if (high <= low) return Hsl(0.0, 0.0, lightness)
            val delta = high - low
            val saturation = if (lightness > 0.5) delta / (2 - high - low) else delta / (high + low)
            val hue = when (high) {
                red -> (green - blue) / delta + if (green < blue) 6 else 0
                green -> (blue - red) / delta + 2
                else -> (red - green) / delta + 4
            }
            return Hsl(hue * 60, saturation, lightness)
        }

    override fun equals(other: Any?) =
        other is RgbColor && red == other.red && green == other.green && blue == other.blue

    override fun hashCode() = (red.hashCode() * 31 + green.hashCode()) * 31 + blue.hashCode()

    override fun toString() = hex

    companion object {
        val WHITE = RgbColor(1.0, 1.0, 1.0)
        val BLACK = RgbColor(0.0, 0.0, 0.0)

        /** "#RRGGBB", or null for anything else. */
        fun parse(hex: String): RgbColor? {
            if (hex.length != 7 || hex[0] != '#' || !hex.substring(1).all { it in HEX_DIGITS }) return null
            val value = hex.substring(1).toInt(16)
            return RgbColor(((value shr 16) and 0xFF) / 255.0, ((value shr 8) and 0xFF) / 255.0, (value and 0xFF) / 255.0)
        }

        fun fromHsl(hue: Double, saturation: Double, lightness: Double): RgbColor {
            val s = saturation.coerceIn(0.0, 1.0)
            val l = lightness.coerceIn(0.0, 1.0)
            val chroma = (1 - abs(2 * l - 1)) * s
            val sector = (hue % 360 + 360) % 360 / 60
            val second = chroma * (1 - abs(sector % 2 - 1))
            val (r, g, b) = when {
                sector < 1 -> Triple(chroma, second, 0.0)
                sector < 2 -> Triple(second, chroma, 0.0)
                sector < 3 -> Triple(0.0, chroma, second)
                sector < 4 -> Triple(0.0, second, chroma)
                sector < 5 -> Triple(second, 0.0, chroma)
                else -> Triple(chroma, 0.0, second)
            }
            val match = l - chroma / 2
            return RgbColor(r + match, g + match, b + match)
        }

        private const val HEX_DIGITS = "0123456789abcdefABCDEF"

        private fun channel(value: Double) = (value * 255).roundToInt()
    }
}
