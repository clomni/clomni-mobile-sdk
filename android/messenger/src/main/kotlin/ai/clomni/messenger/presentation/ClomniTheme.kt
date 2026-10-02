package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.MessengerConfig

/**
 * The design tokens of brief 8·7.1, with the iOS SDK's names. One accent colour comes from the config; everything
 * else is neutral grey. Sizes are dp (= pt on iOS), font sizes sp.
 */
internal data class ClomniTheme(val colors: Colors, val isDark: Boolean) {

    data class Colors(
        /** User messages, pill text, send, active icons. One step lighter in dark mode. */
        val primary: RgbColor,
        /** The Home header's top and bottom: light to dark (both [primary] for a solid header). */
        val headerFrom: RgbColor,
        val headerTo: RgbColor,
        /** [primary] at 10% over the background: image placeholders, soft backgrounds. */
        val primarySoft: RgbColor,
        /** [primary] at 22% over the background: pill borders. */
        val primaryLine: RgbColor,
        /** Text on [primary]: the config's colour, or white or black, whichever reaches 4.5:1. */
        val onPrimary: RgbColor,
        val background: RgbColor,
        /** Behind the Home cards. */
        val canvas: RgbColor,
        /** Bot and operator messages, the composer field, skeleton blocks. */
        val surface: RgbColor,
        val textPrimary: RgbColor,
        val textSecondary: RgbColor,
        val border: RgbColor,
        val unread: RgbColor,
        /** The operator's online dot in the conversation header. */
        val online: RgbColor,
        /** The thin yellow "no internet" strip (brief 8·7.5) and its text. */
        val warning: RgbColor,
        val onWarning: RgbColor,
    )

    object Radius {
        val message = 16f

        /** The corner where messages of one group meet. */
        val messageJoined = 5f
        val pill = 18f
        val card = 12f
        val input = 20f
        val logo = 6f
        val channel = 8f
    }

    object FontSize {
        val greeting = 22f
        val brand = 17f
        val title = 14.5f
        val text = 14f
        val preview = 13f
        val secondary = 12.5f
        val label = 12f
        val meta = 11f
    }

    object Space {
        val xxs = 3f
        val xs = 6f
        val s = 8f
        val m = 10f
        val l = 12f
        val xl = 14f
        val xxl = 18f
    }

    object Size {
        val logo = 22f
        val headerAvatar = 24f

        /** Header avatars overlap by this much. */
        val headerAvatarOverlap = 7f
        val avatar = 28f
        val channel = 30f
        val unreadDot = 7f
        val tabDot = 8f
        val tabIcon = 22f

        /** The cards ride up over the header by this much. */
        val cardOverlap = 40f

        /** No tap target is smaller, whatever it looks like (Android's 48 dp; iOS uses 44 pt). */
        val touchTarget = 48f
    }

    /** shadow.card: two soft layers in light mode; dark mode draws a 1 dp border instead. */
    data class Shadow(val opacity: Double, val radius: Double, val y: Double) {
        companion object {
            val card = listOf(Shadow(0.06, 2.0, 1.0), Shadow(0.05, 10.0, 2.0))
        }
    }

    companion object {
        /** Clomni's own colour, for a config that has none. */
        val defaultPrimary: RgbColor = RgbColor.parse(MessengerConfig.Brand.DEFAULT_PRIMARY_COLOR) ?: RgbColor.BLACK

        /**
         * The look for [config] (null: Clomni's own) on a system that is or is not dark; `Clomni.setTheme` wins over the
         * panel for the colour and the mode.
         */
        fun resolve(config: MessengerConfig?, systemIsDark: Boolean, overrides: ThemeOverrides = ThemeOverrides.Companion): ClomniTheme {
            val dark = isDark(overrides.mode ?: config?.theme?.mode, systemIsDark)
            return make(config?.brand, dark, overrides.primaryColor)
        }

        /**
         * The server's colours for the brand when it sent them (APPEARANCE-CONTRACT 1), otherwise the same rules here:
         * the brand, one step lighter in dark mode; text on it white or black by contrast; soft 10% and line 22% over
         * the background; the header light to dark ([primaryOverride] is always derived here).
         */
        fun make(brand: MessengerConfig.Brand?, dark: Boolean, primaryOverride: RgbColor? = null): ClomniTheme {
            val background = if (dark) hex("#121316") else RgbColor.WHITE
            val palette = if (primaryOverride == null) brand?.colors?.let { if (dark) it.dark else it.light } else null
            val brandColors = palette?.let(::fromPalette)
                ?: derive(primaryOverride ?: brand?.let { RgbColor.parse(it.primaryColor) } ?: defaultPrimary, dark, background)
            val solid = brand?.headerStyle == MessengerConfig.HeaderStyle.SOLID
            val colors = Colors(
                primary = brandColors.primary,
                headerFrom = if (solid) brandColors.primary else brandColors.headerFrom,
                headerTo = if (solid) brandColors.primary else brandColors.headerTo,
                primarySoft = brandColors.primarySoft,
                primaryLine = brandColors.primaryLine,
                onPrimary = brandColors.onPrimary,
                background = background,
                canvas = hex(if (dark) "#0B0C0E" else "#F5F6F8"),
                surface = hex(if (dark) "#22242A" else "#F1F2F4"),
                textPrimary = hex(if (dark) "#F2F3F5" else "#1B1D21"),
                // The brief's #737780 is 4.49:1 on white, just short of WCAG AA; #707480 reaches 4.67.
                textSecondary = hex(if (dark) "#9A9DA6" else "#707480"),
                border = hex(if (dark) "#2A2C32" else "#E7E8EB"),
                unread = hex("#E5484D"),
                online = hex("#30C26B"),
                warning = hex(if (dark) "#3D3415" else "#FFF4CC"),
                onWarning = hex(if (dark) "#F2DC8B" else "#5C4400"),
            )
            return ClomniTheme(colors, dark)
        }

        /** The brand's own colours, from the server or derived here. */
        data class BrandColors(
            val primary: RgbColor,
            val onPrimary: RgbColor,
            val primarySoft: RgbColor,
            val primaryLine: RgbColor,
            val headerFrom: RgbColor,
            val headerTo: RgbColor,
        )

        /** The server's rules (APPEARANCE-CONTRACT 1), for a config without colours or a colour set in the app. */
        fun derive(base: RgbColor, dark: Boolean, background: RgbColor): BrandColors {
            val primary = if (dark) base.steps(1) else base
            // Light: one step lighter at the top, one darker at the bottom; dark: both one step darker than that.
            val shade = if (dark) -1 else 0
            return BrandColors(
                primary = primary,
                onPrimary = readableText(primary),
                primarySoft = primary.over(background, 0.10),
                primaryLine = primary.over(background, 0.22),
                headerFrom = base.steps(1 + shade),
                headerTo = base.steps(-1 + shade),
            )
        }

        private fun fromPalette(palette: MessengerConfig.Palette) = BrandColors(
            primary = hex(palette.primary),
            onPrimary = hex(palette.onPrimary),
            primarySoft = hex(palette.primarySoft),
            primaryLine = hex(palette.primaryLine),
            headerFrom = hex(palette.headerFrom),
            headerTo = hex(palette.headerTo),
        )

        /** `Clomni.setTheme`'s mode, else the panel's `theme.mode`; `system` follows the device. */
        fun isDark(mode: MessengerConfig.ThemeMode?, systemIsDark: Boolean): Boolean = when (mode) {
            MessengerConfig.ThemeMode.DARK -> true
            MessengerConfig.ThemeMode.LIGHT -> false
            else -> systemIsDark
        }

        /**
         * White when it reaches 4.5:1 (WCAG AA for body text) on [background], otherwise black, which then always
         * does: one of the two reaches at least 4.58:1 on any colour.
         */
        fun readableText(background: RgbColor): RgbColor =
            if (background.contrast(RgbColor.WHITE) >= 4.5) RgbColor.WHITE else RgbColor.BLACK

        private fun hex(value: String) = RgbColor.parse(value) ?: RgbColor.BLACK
    }
}

/** What the app set with `Clomni.setTheme`: it wins over the panel. The companion is the app's own. */
internal open class ThemeOverrides {
    @Volatile
    var primaryColor: RgbColor? = null

    @Volatile
    var mode: MessengerConfig.ThemeMode? = null

    companion object : ThemeOverrides()
}
