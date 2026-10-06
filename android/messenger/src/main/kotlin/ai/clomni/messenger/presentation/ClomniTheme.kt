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
        /** The Home header's top and bottom: the brand to darker (both [primary] for a solid header). */
        val headerFrom: RgbColor,
        val headerTo: RgbColor,
        /** Text and icons on the header: white where it reaches 3:1 on both header colours, else dark; white on a picture. */
        val headerText: RgbColor,
        /** Home's first greeting line, drawn at about 70%: the server's primary_strong. */
        val primaryStrong: RgbColor,
        /** [primary] as text (pills, links, "Yeni söhbət başlat"): itself, or as much darker as 4.5:1 needs. */
        val primaryText: RgbColor,
        /** [primary] at 10% over the background: image placeholders, soft backgrounds. */
        val primarySoft: RgbColor,
        /** [primary] at 22% over the background: pill borders. */
        val primaryLine: RgbColor,
        /** Text on [primary]: the server's colour, or white or black, whichever reaches 4.5:1. Not on the header. */
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
        /** Errors as text ("Göndərilmədi", a form field's error): [unread], darker where 4.5:1 needs it. */
        val errorText: RgbColor,
        /** The launcher's count badge: [unread] dark enough for its white number. */
        val badge: RgbColor,
        /** The operator's online dot in the conversation header. */
        val online: RgbColor,
        /** The thin yellow "no internet" strip (brief 8·7.5) and its text. */
        val warning: RgbColor,
        val onWarning: RgbColor,
    )

    object Radius {
        /** M9: soft, 20; 6 where bubbles of one run meet. */
        val message = 20f

        /** The corner where messages of one group meet. */
        val messageJoined = 6f
        val pill = 18f
        val card = 12f
        val input = 20f
        val logo = 8f
        val channel = 8f
    }

    object FontSize {
        val greeting = 22f
        val brand = 17f
        val title = 14.5f
        val text = 14f

        /** A message bubble's text. */
        val message = 16f
        val preview = 13f
        val secondary = 12.5f
        val label = 12f
        val meta = 11f
    }

    /** Multiples of 4 only: 4 · 8 · 12 · 16 · 20 · 24 · 32 (coordinator's scale, the same on iOS). */
    object Space {
        val xxs = 4f
        val xs = 8f
        val s = 8f
        val m = 12f
        val l = 12f
        val xl = 16f
        val xxl = 20f
    }

    object Size {
        val logo = 32f
        val headerAvatar = 24f

        /** Header avatars overlap by this much. */
        val headerAvatarOverlap = 7f
        val avatar = 28f
        val channel = 30f
        val unreadDot = 7f

        /** No tap target is smaller, whatever it looks like (Android's 48 dp; iOS uses 44 pt). */
        val touchTarget = 48f
    }

    /** shadow.card: two soft layers in light mode; dark mode draws a 1 dp border instead. */
    data class Shadow(val opacity: Double, val radius: Double, val y: Double) {
        companion object {
            /** M9: very light, y 2, blur 8, 6%. */
            val card = listOf(Shadow(0.06, 8.0, 2.0))

            /** The offline capsule: y 2, blur 8, 12%. */
            val capsule = Shadow(0.12, 8.0, 2.0)
        }
    }

    /**
     * The offline capsule's colours (CM-077): a dark neutral at 92% under white text, the other way round in dark mode.
     * Neither comes from the brand, so it reads the same on the brand's colour, a picture or the page.
     */
    val capsule: Capsule get() = if (isDark) Capsule.DARK else Capsule.LIGHT

    data class Capsule(val fill: RgbColor, val opacity: Double, val text: RgbColor) {
        companion object {
            val LIGHT = Capsule(RgbColor.parse("#1C1C1E")!!, 0.92, RgbColor.WHITE)
            val DARK = Capsule(RgbColor.parse("#F2F2F7")!!, 0.92, RgbColor.parse("#1C1C1E")!!)
        }
    }

    companion object {
        /** Clomni's own colour, for a config that has none. */
        val defaultPrimary: RgbColor = RgbColor.parse(MessengerConfig.Brand.DEFAULT_PRIMARY_COLOR) ?: RgbColor.BLACK

        /**
         * The look for [config] (null: Clomni's own) on a system that is or is not dark; `Clomni.setTheme` wins over the
         * panel for the colour and the mode.
         */
        fun resolve(config: MessengerConfig?, systemIsDark: Boolean, override: ThemeOverride = ThemeOverride()): ClomniTheme {
            val dark = isDark(override.mode ?: config?.theme?.mode, systemIsDark)
            return make(config?.brand, dark, override.primaryColor)
        }

        /**
         * The server's colours for the brand when it sent them (APPEARANCE-CONTRACT 1), otherwise the same rules here:
         * the brand, one step lighter in dark mode; text on it white or black by contrast; soft 10% and line 22% over
         * the background; the header from the brand to a step darker ([primaryOverride] is always derived here).
         */
        fun make(brand: MessengerConfig.Brand?, dark: Boolean, primaryOverride: RgbColor? = null): ClomniTheme {
            if (brand == null && primaryOverride == null) return neutral(dark)
            val background = if (dark) hex("#121316") else RgbColor.WHITE
            val palette = if (primaryOverride == null) brand?.colors?.let { if (dark) it.dark else it.light } else null
            val brandColors = palette?.let(::fromPalette)
                ?: derive(primaryOverride ?: brand?.let { RgbColor.parse(it.primaryColor) } ?: defaultPrimary, dark, background)
            val solid = brand?.headerStyle == MessengerConfig.HeaderStyle.SOLID
            val headerFrom = if (solid) brandColors.primary else brandColors.headerFrom
            val headerTo = if (solid) brandColors.primary else brandColors.headerTo
            val picture = brand?.headerStyle == MessengerConfig.HeaderStyle.IMAGE && brand.headerImageUrl != null
            val surface = hex(if (dark) "#22242A" else "#F1F2F4")
            // Text sits on the background and in the grey bubbles; it has to read on both.
            val behindText = listOf(background, surface)
            val unread = hex("#E5484D")
            val colors = Colors(
                primary = brandColors.primary,
                primaryText = brandColors.primary.readableOn(behindText),
                headerFrom = headerFrom,
                headerTo = headerTo,
                headerText = when {
                    // The picture has its dark veil.
                    picture -> RgbColor.WHITE
                    else -> brandColors.headerText ?: headerText(headerFrom, headerTo)
                },
                primaryStrong = brandColors.primaryStrong,
                primarySoft = brandColors.primarySoft,
                primaryLine = brandColors.primaryLine,
                onPrimary = brandColors.onPrimary,
                background = background,
                canvas = hex(if (dark) "#0B0C0E" else "#F5F6F8"),
                surface = surface,
                textPrimary = hex(if (dark) "#F2F3F5" else "#1B1D21"),
                // The brief's #737780 is 4.49:1 on white, and less on the grey canvas and bubbles where it also sits
                // (the composer's placeholder, "Powered by Clomni"); #6A6E7A reaches 4.5 on all three.
                textSecondary = hex(if (dark) "#9A9DA6" else "#6A6E7A"),
                // M9: a line is never darker than the text colour at 8%.
                border = hex(if (dark) "#F2F3F5" else "#1B1D21").over(background, 0.08),
                unread = unread,
                errorText = unread.readableOn(behindText),
                badge = unread.readableOn(listOf(RgbColor.WHITE)),
                online = hex("#30C26B"),
                warning = hex(if (dark) "#3D3415" else "#FFF4CC"),
                onWarning = hex(if (dark) "#F2DC8B" else "#5C4400"),
            )
            return ClomniTheme(colors, dark)
        }

        /**
         * No config yet and no `setTheme` colour: grey, never a brand colour that is not the app's. The skeleton
         * shows in it until the config arrives.
         */
        private fun neutral(dark: Boolean): ClomniTheme {
            val grey = make(MessengerConfig.Brand.neutral, dark)
            val c = grey.colors
            return grey.copy(colors = c.copy(headerFrom = c.surface, headerTo = c.surface, headerText = c.textPrimary))
        }

        /** The brand's own colours, from the server or derived here. */
        data class BrandColors(
            val primary: RgbColor,
            val onPrimary: RgbColor,
            val primarySoft: RgbColor,
            val primaryLine: RgbColor,
            val headerFrom: RgbColor,
            val headerTo: RgbColor,
            /** The server's; null: [headerText] of the header's colours. */
            val headerText: RgbColor? = null,
            val primaryStrong: RgbColor = primary,
        )

        /** The server's rules (APPEARANCE-CONTRACT 1), for a config without colours or a colour set in the app. */
        fun derive(base: RgbColor, dark: Boolean, background: RgbColor): BrandColors {
            val primary = if (dark) base.steps(1) else base
            return BrandColors(
                primary = primary,
                onPrimary = readableText(primary),
                primarySoft = primary.over(background, 0.10),
                primaryLine = primary.over(background, 0.22),
                // The brand colour at the top (not dark mode's lighter primary), one step darker at the bottom; two in
                // dark mode.
                headerFrom = base,
                headerTo = base.steps(if (dark) -2 else -1),
                primaryStrong = strong(base),
            )
        }

        /**
         * The server's primary_strong rule, for a config before it or a colour set in the app: two steps darker, or two
         * lighter for a brand so dark that white reads on it at 7:1.
         */
        fun strong(base: RgbColor): RgbColor = if (base.contrast(RgbColor.WHITE) >= 7.0) base.steps(2) else base.steps(-2)

        private fun fromPalette(palette: MessengerConfig.Palette) = BrandColors(
            primary = hex(palette.primary),
            onPrimary = hex(palette.onPrimary),
            primarySoft = hex(palette.primarySoft),
            primaryLine = hex(palette.primaryLine),
            headerFrom = hex(palette.headerFrom),
            headerTo = hex(palette.headerTo),
            headerText = palette.headerText?.let(::hex),
            primaryStrong = palette.primaryStrong?.let(::hex) ?: strong(hex(palette.headerFrom)),
        )

        /** `Clomni.setTheme`'s mode, else the panel's `theme.mode`; `system` follows the device. */
        fun isDark(mode: MessengerConfig.ThemeMode?, systemIsDark: Boolean): Boolean = when (mode) {
            MessengerConfig.ThemeMode.DARK -> true
            MessengerConfig.ThemeMode.LIGHT -> false
            else -> systemIsDark
        }

        /**
         * The header's text and icons (APPEARANCE-CONTRACT 1, header_text): white where it reaches 3:1 on both of the
         * header's colours (the greeting is large text), otherwise #1B1D21.
         */
        fun headerText(from: RgbColor, to: RgbColor): RgbColor =
            if (from.contrast(RgbColor.WHITE) >= 3.0 && to.contrast(RgbColor.WHITE) >= 3.0) RgbColor.WHITE else hex("#1B1D21")

        /**
         * White when it reaches 4.5:1 (WCAG AA for body text) on [background], otherwise black, which then always
         * does: one of the two reaches at least 4.58:1 on any colour.
         */
        fun readableText(background: RgbColor): RgbColor =
            if (background.contrast(RgbColor.WHITE) >= 4.5) RgbColor.WHITE else RgbColor.BLACK

        private fun hex(value: String) = RgbColor.parse(value) ?: RgbColor.BLACK
    }
}

/** What the app set with `Clomni.setTheme`: it wins over the panel; null leaves that one to the panel. */
internal data class ThemeOverride(val primaryColor: RgbColor? = null, val mode: MessengerConfig.ThemeMode? = null)

/**
 * The look [fraction] (0…1) of the way from this one to [target]: a new appearance fades in rather than jumping.
 * The mode is the target's.
 */
internal fun ClomniTheme.toward(target: ClomniTheme, fraction: Double): ClomniTheme {
    if (fraction >= 1.0 || this == target) return target
    val a = colors
    val b = target.colors
    fun mix(from: RgbColor, to: RgbColor) = to.over(from, fraction)
    return ClomniTheme(
        ClomniTheme.Colors(
            primary = mix(a.primary, b.primary),
            primaryText = mix(a.primaryText, b.primaryText),
            headerFrom = mix(a.headerFrom, b.headerFrom),
            headerTo = mix(a.headerTo, b.headerTo),
            headerText = mix(a.headerText, b.headerText),
            primaryStrong = mix(a.primaryStrong, b.primaryStrong),
            primarySoft = mix(a.primarySoft, b.primarySoft),
            primaryLine = mix(a.primaryLine, b.primaryLine),
            onPrimary = mix(a.onPrimary, b.onPrimary),
            background = mix(a.background, b.background),
            canvas = mix(a.canvas, b.canvas),
            surface = mix(a.surface, b.surface),
            textPrimary = mix(a.textPrimary, b.textPrimary),
            textSecondary = mix(a.textSecondary, b.textSecondary),
            border = mix(a.border, b.border),
            unread = mix(a.unread, b.unread),
            errorText = mix(a.errorText, b.errorText),
            badge = mix(a.badge, b.badge),
            online = mix(a.online, b.online),
            warning = mix(a.warning, b.warning),
            onWarning = mix(a.onWarning, b.onWarning),
        ),
        target.isDark,
    )
}
