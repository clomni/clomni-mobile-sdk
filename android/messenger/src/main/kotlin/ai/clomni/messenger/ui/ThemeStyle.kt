package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.ThemeOverride
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.offset
import androidx.compose.ui.unit.sp

internal val RgbColor.color: Color get() = Color(argb)

/** `Clomni.setTheme`'s colour and mode: every open screen redraws when it changes; the launcher reads it too. */
internal object AppTheme {
    var override: ThemeOverride by mutableStateOf(ThemeOverride())
}

/**
 * The app's own font (`Clomni.setTypeface`) for every text of the messenger; null is the platform's. A weight the
 * family lacks takes its nearest face: Android picks it from the family (API 28+), or bold for 600 and heavier.
 */
internal object ClomniFonts {
    @Volatile
    var typeface: android.graphics.Typeface? = null
        set(value) {
            field = value
            family = value?.let { FontFamily(it) }
        }

    @Volatile
    var family: FontFamily? = null
        private set
}

/**
 * Roboto (the platform's font) at a token size in sp, so it follows the user's font scale; [lineHeight] is a multiple
 * of the size, as in the reference (14/1.4).
 */
internal fun clomniText(
    size: Float,
    color: RgbColor,
    weight: FontWeight = FontWeight.Normal,
    lineHeight: Float = 1.4f,
    letterSpacing: Float = 0f,
) = TextStyle(
    color = color.color,
    fontSize = size.sp,
    fontWeight = weight,
    lineHeight = (size * lineHeight).sp,
    fontFamily = ClomniFonts.family,
    letterSpacing = letterSpacing.sp,
    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
    // Each text runs the way its own words do: an Azerbaijani message stays left to right in a right-to-left app.
    textDirection = TextDirection.Content,
)

/**
 * A card (DESIGN-PASS-2 5): white (the surface in dark mode), radius 16, padding 20, a very light shadow (M9: y 2,
 * blur 8, 6%) and no border. With [onClick] the whole card is one button read out as [label].
 */
internal fun Modifier.clomniCard(theme: ClomniTheme, label: String = "", onClick: (() -> Unit)? = null): Modifier {
    val shape = RoundedCornerShape(16.dp)
    val lifted = if (theme.isDark) this else softShadow(16.dp, theme.colors.background.color)
    val clipped = lifted.clip(shape)
    // A tappable card is a 48 dp target even with one line in it.
    return (if (onClick != null) clipped.heightIn(min = ClomniTheme.Size.touchTarget.dp).button(label, shape, onClick = onClick) else clipped)
        .background(if (theme.isDark) theme.colors.surface.color else theme.colors.background.color)
        .padding(20.dp)
}

/** [clomniCard], Home's name for it. */
internal fun Modifier.homeCard(theme: ClomniTheme, label: String = "", onClick: (() -> Unit)? = null): Modifier =
    clomniCard(theme, label, onClick)

/**
 * Like the symmetric [bleed], with each side its own: a target at a screen edge reaches inwards instead of past it.
 * Start and end follow the layout direction.
 */
internal fun Modifier.bleed(start: Dp, top: Dp, end: Dp, bottom: Dp): Modifier = layout { measurable, constraints ->
    val s = start.roundToPx()
    val e = end.roundToPx()
    val t = top.roundToPx()
    val b = bottom.roundToPx()
    val placeable = measurable.measure(constraints.offset(s + e, t + b))
    layout((placeable.width - s - e).coerceAtLeast(0), (placeable.height - t - b).coerceAtLeast(0)) { placeable.placeRelative(-s, -t) }
}

/**
 * Takes [horizontal] and [vertical] less room on each side than the content measures: a 48 dp touch target that lays
 * out like the smaller thing it surrounds.
 */
internal fun Modifier.bleed(horizontal: Dp = 0.dp, vertical: Dp = 0.dp): Modifier = layout { measurable, constraints ->
    val h = horizontal.roundToPx()
    val v = vertical.roundToPx()
    val placeable = measurable.measure(constraints.offset(2 * h, 2 * v))
    val width = (placeable.width - 2 * h).coerceAtLeast(0)
    val height = (placeable.height - 2 * v).coerceAtLeast(0)
    layout(width, height) { placeable.place(-h, -v) }
}

/**
 * [token] (the card's by default) under a rounded rectangle of [radius] filled with [fill]: drawn with a shadow layer,
 * which the GPU draws for shapes from Android 9; before that an elevation shadow of about the same weight.
 */
internal fun Modifier.softShadow(radius: Dp, fill: Color, token: ClomniTheme.Shadow = ClomniTheme.Shadow.card.first()): Modifier {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
        val spot = Color.Black.copy(alpha = token.opacity.toFloat())
        return shadow(1.dp, RoundedCornerShape(radius), ambientColor = spot.copy(alpha = spot.alpha / 2), spotColor = spot)
            .background(fill, RoundedCornerShape(radius))
    }
    return drawWithCache {
        // A CSS blur of 8 is a shadow layer of radius 6 (the layer's radius is about 0.75 of the blur).
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = fill.toArgb()
            setShadowLayer((token.radius * 0.75).toFloat().dp.toPx(), 0f, token.y.toFloat().dp.toPx(), Color.Black.copy(alpha = token.opacity.toFloat()).toArgb())
        }
        val corner = radius.toPx()
        onDrawBehind {
            drawIntoCanvas { it.nativeCanvas.drawRoundRect(0f, 0f, size.width, size.height, corner, corner, paint) }
        }
    }
}
