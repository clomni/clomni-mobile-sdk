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
        /** The top of the Home header's gradient: one step darker than [primary]. */
        val primaryDark: RgbColor,
        /** Pill borders: [primary] at 25% over the background; a muted dark tone of the brand hue in dark mode. */
        val primarySoft: RgbColor,
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

        fun make(brand: MessengerConfig.Brand?, dark: Boolean): ClomniTheme {
            val base = brand?.let { RgbColor.parse(it.primaryColor) } ?: defaultPrimary
            val primary = if (dark) base.steps(1) else base
            val background = if (dark) hex("#121316") else RgbColor.WHITE
            val (hue, saturation, _) = base.hsl
            val colors = Colors(
                primary = primary,
                primaryDark = primary.steps(-1),
                primarySoft = if (dark) RgbColor.fromHsl(hue, saturation / 2, 0.28) else primary.over(background, 0.25),
                onPrimary = brand?.onPrimaryColor?.let(RgbColor::parse) ?: readableText(primary),
                background = background,
                canvas = hex(if (dark) "#0B0C0E" else "#F5F6F8"),
                surface = hex(if (dark) "#22242A" else "#F1F2F4"),
                textPrimary = hex(if (dark) "#F2F3F5" else "#1B1D21"),
                // The brief's #737780 is 4.49:1 on white, just short of WCAG AA; #707480 reaches 4.67.
                textSecondary = hex(if (dark) "#9A9DA6" else "#707480"),
                border = hex(if (dark) "#2A2C32" else "#E7E8EB"),
                unread = hex("#E5484D"),
                warning = hex(if (dark) "#3D3415" else "#FFF4CC"),
                onWarning = hex(if (dark) "#F2DC8B" else "#5C4400"),
            )
            return ClomniTheme(colors, dark)
        }

        /** The config's `brand.theme` wins over the system's appearance unless it says `system`. */
        fun isDark(theme: MessengerConfig.Theme?, systemIsDark: Boolean): Boolean = when (theme) {
            MessengerConfig.Theme.DARK -> true
            MessengerConfig.Theme.LIGHT -> false
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
