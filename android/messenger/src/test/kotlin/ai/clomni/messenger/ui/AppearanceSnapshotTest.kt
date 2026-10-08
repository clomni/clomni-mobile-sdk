package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.presentation.ThemeOverride
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalInspectionMode
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.Density
import com.android.resources.NightMode
import org.junit.Rule
import org.junit.Test
import java.util.TimeZone

/**
 * What the panel publishes (APPEARANCE-CONTRACT 1, 4) as Home draws it, at the reference's size (282×602 dp at
 * 1.5×). The pictures are drawn here and handed over by URL, as the network would; copies of these are in
 * docs/screenshots/appearance/android.
 */
class AppearanceSnapshotTest {
    private val reference = DeviceConfig.PIXEL_5.copy(screenWidth = 423, screenHeight = 903, xdpi = 240, ydpi = 240, density = Density.HIGH)

    private val semantics = SemanticsCapture()

    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = reference, theme = "android:Theme.Material.Light.NoActionBar", renderExtensions = setOf(semantics))

    /** 2026-10-01T10:32Z: two minutes after the fixtures' messages. */
    private val now = 1_790_850_720_000L

    private val fromLeyla: Conversation = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)
    private val fromBot: Conversation = Fixture.conversation("conv_2", "01-text-bot.json")

    private fun config(json: String): MessengerConfig = ProtocolJson().parseConfig(json)!!

    /** Example without the server's colours: the SDK derives them, so the brand and the style alone decide. */
    private fun example(brand: String = "", rest: String = ""): MessengerConfig = config(
        """{"version":12,"brand":{"name":"Example","primary_color":"#1F9D63","logo_url":"$LOGO"$brand},
            "team":{"show":true,"avatars":["$LEYLA","$RAUF","$NIGAR"],"reply_time":"Adətən bir neçə dəqiqəyə cavab veririk"},
            "bot":{"name":"Clomni","avatar_url":"$BOT"},
            "home":{"cards":["send","recent","channels"],
                    "channels":[{"type":"instagram","url":"https://instagram.com/example"},{"type":"whatsapp","url":"https://wa.me/994501234567"},
                                {"type":"linkedin","url":"https://linkedin.com/company/example"},{"type":"email","url":"mailto:support@example.com"}]},
            "languages":["az","en","ru"],"powered_by":true$rest}""",
    )

    private fun snap(
        name: String,
        config: MessengerConfig,
        language: String = "az",
        user: String? = "Aysel Məmmədova",
        conversations: List<Conversation> = listOf(fromLeyla),
        dark: Boolean = false,
        override: ThemeOverride = ThemeOverride(),
    ) {
        if (dark) paparazzi.unsafeUpdateConfig(deviceConfig = reference.copy(nightMode = NightMode.NIGHT))
        val state = MessengerSnapshot(
            config = config,
            configLoad = MessengerSnapshot.Load.LOADED,
            conversations = conversations,
            conversationsLoad = MessengerSnapshot.Load.LOADED,
            userName = user,
        )
        val presenter = HomePresenter(ClomniStrings(language, config.strings), TimeZone.getTimeZone("UTC"), now)
        val theme = ClomniTheme.resolve(config, systemIsDark = dark, override)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true, LocalPreviewImages provides pictures) {
                MessengerScreenAt(presenter.home(state), presenter.messages(state), theme, MessengerActions())
            }
        }
        semantics.assertTouchTargets(name)
    }

    // Logo, bot picture, team

    /** The panel's logo in the white square, the team's pictures, the server's colours. */
    @Test
    fun logo() = snap("logo", Fixture.exampleConfig)

    /** No logo: the brand's initial. */
    @Test
    fun noLogo() = snap("no_logo", example().let { it.copy(brand = it.brand.copy(logoUrl = null)) })

    /** The last message is the bot's: the panel's bot picture. */
    @Test
    fun botPicture() = snap("bot_picture", example(), conversations = listOf(fromBot))

    /** No bot picture in the panel: the brand's logo stands in for it. */
    @Test
    fun botWithoutPicture() = snap("bot_logo_fallback", example().let { it.copy(bot = it.bot.copy(avatarUrl = null)) }, conversations = listOf(fromBot.withoutAvatar()))

    @Test
    fun teamHidden() = snap("team_hidden", example().let { it.copy(team = it.team.copy(show = false)) })

    // Texts

    @Test
    fun textsAz() = snap("texts_az", example())

    @Test
    fun textsEn() = snap(
        "texts_en",
        example().let { it.copy(team = it.team.copy(replyTime = "We usually reply in a few minutes")) },
        language = "en",
    )

    @Test
    fun textsRu() = snap(
        "texts_ru",
        example().let { it.copy(team = it.team.copy(replyTime = "Обычно отвечаем за несколько минут")) },
        language = "ru",
    )

    /** Nobody logged in, or no name: greeting_line1_anonymous. */
    @Test
    fun textsAnonymous() = snap("texts_anonymous", example(), user = null)

    /** The panel's own texts, with {name}. */
    @Test
    fun textsFromThePanel() = snap(
        "texts_custom",
        example(rest = ""","strings":{"greeting_line1":"Xoş gəldiniz, {name}","greeting_line2":"Sualınız var? Yazın","send_card_title":"Operatora yazın"}"""),
    )

    // Cards

    @Test
    fun cardOrder() = snap("card_order", example().fixCards("channels", "recent", "send"))

    /** The social channels turned off in the panel; "Powered by Clomni" off too (a plan that allows it). */
    @Test
    fun channelsOff() = snap("channels_off", example(rest = ""","powered_by":false""").fixCards("send", "recent"))

    // Header

    @Test
    fun headerGradient() = snap("header_gradient", example(brand = ""","header_style":"gradient""""))

    @Test
    fun headerSolid() = snap("header_solid", example(brand = ""","header_style":"solid""""))

    /** The panel's picture under the 35%–55% veil, white text. */
    @Test
    fun headerImage() = snap("header_image", example(brand = ""","header_style":"image","header_image_url":"$HEADER""""))

    @Test
    fun glow() = snap("glow", example(brand = ""","header_style":"solid","glow":true"""))

    @Test
    fun glowDark() = snap("glow_dark", example(brand = ""","header_style":"gradient","glow":true"""), dark = true)

    /** A dark brand colour: white on the header; a light one: dark text, by header_text's 3:1 rule. */
    @Test
    fun darkBrand() = snap("brand_blue", example().colour("#0A66C2"))

    @Test
    fun lightBrand() = snap("brand_yellow", example(brand = ""","header_style":"solid"""").colour("#FFD400"))

    // Dark mode

    /** logo_dark_url in dark mode. */
    @Test
    fun darkLogo() = snap("dark_logo", example(brand = ""","logo_dark_url":"$LOGO_DARK""""), dark = true)

    /** No logo_dark_url: the usual logo in dark mode too. */
    @Test
    fun darkWithoutDarkLogo() = snap("dark_logo_fallback", example(), dark = true)

    /** The written logo in place of the logo and the name (APPEARANCE-CONTRACT 4a), Home only. */
    @Test
    fun wordmark() = snap("wordmark", example(brand = ""","logo_style":"wordmark","wordmark_url":"$WORDMARK""""))

    /** Dark mode without a dark version: the same picture. */
    @Test
    fun wordmarkDark() = snap("wordmark_dark", example(brand = ""","logo_style":"wordmark","wordmark_url":"$WORDMARK""""), dark = true)

    /** The conversation keeps the logo and the name. */
    @Test
    fun wordmarkInAConversation() {
        val config = example(brand = ""","logo_style":"wordmark","wordmark_url":"$WORDMARK"""")
        val screen = ai.clomni.messenger.presentation.ChatPresenter(ClomniStrings("az", config.strings), TimeZone.getTimeZone("UTC"), now)
            .screen(ai.clomni.messenger.presentation.ChatSnapshot(config = config, load = MessengerSnapshot.Load.LOADED))
        paparazzi.snapshot("wordmark_conversation") {
            CompositionLocalProvider(LocalInspectionMode provides true, LocalPreviewImages provides pictures) {
                ChatScreenView(screen, ClomniTheme.make(config.brand, false), ChatActions())
            }
        }
    }

    /** Clomni.setTheme: the app's colour and mode over the panel's. */
    @Test
    fun appsTheme() = snap("app_theme", example(), override = ThemeOverride(primaryColor = BLUE, mode = MessengerConfig.ThemeMode.DARK))

    private fun MessengerConfig.fixCards(vararg cards: String) =
        copy(home = home.copy(cards = cards.map { MessengerConfig.HomeCard.valueOf(it.uppercase()) }))

    private fun MessengerConfig.colour(hex: String) = copy(brand = brand.copy(primaryColor = hex))

    private fun Conversation.withoutAvatar() =
        copy(lastMessage = lastMessage?.let { it.copy(sender = it.sender.copy(avatarUrl = null)) })

    private companion object {
        const val LOGO = "https://app.clomni.ai/v1/images/logo"
        const val LOGO_DARK = "https://app.clomni.ai/v1/images/logo-dark"
        const val BOT = "https://app.clomni.ai/v1/images/bot"
        const val HEADER = "https://app.clomni.ai/v1/images/header"
        const val WORDMARK = "https://app.clomni.ai/v1/images/wordmark"
        const val LEYLA = "https://app.clomni.ai/a/leyla.png"
        const val RAUF = "https://app.clomni.ai/a/rauf.png"
        const val NIGAR = "https://app.clomni.ai/a/nigar.png"
        const val FIXTURE_TEAM = "https://my.clomni.co/rails/active_storage/representations/redirect"
        val BLUE = ai.clomni.messenger.presentation.RgbColor.parse("#0A66C2")

        /** Stand-ins for the panel's uploads: a logo mark, its dark-mode version, faces, a bot, a landscape. */
        val pictures: Map<String, ImageBitmap> by lazy {
            mapOf(
                LOGO to mark(0xFF1F9D63.toInt(), 0xFFFFFFFF.toInt(), "E"),
                // Protocol fixture 42's own pictures.
                "https://app.clomni.ai/v1/images/img_Lq3T8vXw2KpA9mZc4RbN" to mark(0xFF1F9D63.toInt(), 0xFFFFFFFF.toInt(), "E"),
                "$FIXTURE_TEAM/leyla.png" to face(0xFFC2410C.toInt(), "L"),
                "$FIXTURE_TEAM/rauf.png" to face(0xFF7C3AED.toInt(), "R"),
                "$FIXTURE_TEAM/nigar.png" to face(0xFF0E7490.toInt(), "N"),
                LOGO_DARK to mark(0xFF0B0C0E.toInt(), 0xFF34B57A.toInt(), "E"),
                BOT to bot(),
                "https://app.clomni.ai/a/bot.png" to bot(),
                LEYLA to face(0xFFC2410C.toInt(), "L"),
                RAUF to face(0xFF7C3AED.toInt(), "R"),
                NIGAR to face(0xFF0E7490.toInt(), "N"),
                HEADER to landscape(),
                WORDMARK to realWordmark(),
            )
        }

        private fun picture(width: Int, height: Int, draw: Canvas.(Paint) -> Unit): ImageBitmap {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).draw(Paint(Paint.ANTI_ALIAS_FLAG))
            return bitmap.asImageBitmap()
        }

        private fun Canvas.letter(paint: Paint, text: String, color: Int, size: Float, cx: Float, cy: Float) {
            paint.color = color
            paint.textSize = size
            paint.typeface = Typeface.DEFAULT_BOLD
            paint.textAlign = Paint.Align.CENTER
            drawText(text, cx, cy - (paint.descent() + paint.ascent()) / 2, paint)
        }

        private fun mark(background: Int, ink: Int, text: String) = picture(144, 144) { paint ->
            paint.color = background
            drawRoundRect(RectF(8f, 8f, 136f, 136f), 32f, 32f, paint)
            letter(paint, text, ink, 88f, 72f, 72f)
        }

        private fun face(color: Int, text: String) = picture(96, 96) { paint ->
            paint.color = color
            drawRect(0f, 0f, 96f, 96f, paint)
            letter(paint, text, 0xFFFFFFFF.toInt(), 44f, 48f, 48f)
        }

        private fun bot() = picture(96, 96) { paint ->
            paint.color = 0xFF4F46E5.toInt()
            drawRect(0f, 0f, 96f, 96f, paint)
            paint.color = 0xFFFFFFFF.toInt()
            drawRoundRect(RectF(22f, 30f, 74f, 70f), 12f, 12f, paint)
            paint.color = 0xFF4F46E5.toInt()
            drawCircle(38f, 48f, 6f, paint)
            drawCircle(58f, 48f, 6f, paint)
        }

        /**
         * Clomni's own written logo (mobile-sdk/logo/clomni-wordmark-white.png, 14127 px wide) at the server's largest
         * size, 1200 px: a real 3.5:1 picture, a green mark and the name in white on transparency.
         */
        private fun realWordmark(): ImageBitmap {
            val bytes = AppearanceSnapshotTest::class.java.getResourceAsStream("/clomni-wordmark-white-1200.png")!!.use { it.readBytes() }
            return android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size).asImageBitmap()
        }

        private fun landscape() = picture(720, 400) { paint ->
            paint.color = 0xFF7FB8D8.toInt()
            drawRect(0f, 0f, 720f, 400f, paint)
            paint.color = 0xFFF2C36B.toInt()
            drawCircle(560f, 120f, 56f, paint)
            paint.color = 0xFF3E7C59.toInt()
            drawOval(RectF(-200f, 220f, 420f, 640f), paint)
            paint.color = 0xFF2F6046.toInt()
            drawOval(RectF(260f, 260f, 980f, 700f), paint)
        }
    }
}
