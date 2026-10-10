package ai.clomni.messenger.ui

import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.presentation.ChatController
import ai.clomni.messenger.presentation.ChatDataSource
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.MicInput
import ai.clomni.messenger.presentation.VoicePlayer
import ai.clomni.messenger.presentation.VoiceRecorderController
import ai.clomni.messenger.presentation.VoiceRecording
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.store.PendingMessage
import ai.clomni.messenger.store.PendingUpload
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.json.JsonElement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.Future
import java.util.concurrent.FutureTask

/**
 * CM-130 on a device: the composer's round button is the microphone; held for a second and a half and let go, the
 * recording (a double: CI's emulator has no microphone to rely on) goes to the outbox as a voice message, with its
 * length and waveform, and stands in the conversation as a voice bubble with its clock.
 */
@RunWith(AndroidJUnit4::class)
class VoiceComposerTest {
    @get:Rule
    val compose = createComposeRule()

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    /**
     * Comes a third of a second after the press, as a device's microphone does (CM-131), writes a few bytes where it
     * records and measures by the clock.
     */
    private class Mic : MicInput {
        private var startedAt = 0L

        override fun start(file: File, ready: (Boolean) -> Unit) {
            Handler(Looper.getMainLooper()).postDelayed({
                file.writeText("m4a")
                startedAt = SystemClock.elapsedRealtime()
                ready(true)
            }, 300)
        }

        override fun level(): Float = 0.6f
        override fun stop(): Long = SystemClock.elapsedRealtime() - startedAt
        override fun cancel() {}
    }

    @Test
    fun holdingTheMicrophoneSendsAVoiceMessageThroughTheOutbox() {
        val source = Outbox(context.cacheDir)
        val direct = Executor { it.run() }
        val controller = ChatController(source, "conv_1", "az", direct, direct, VoiceAudio.scheduler, timeZone = TimeZone.getTimeZone("UTC"))
        val recorder = VoiceRecorder(
            VoiceRecorderController(
                Mic(), { VoiceRecording.Permission.GRANTED }, {}, { File(context.cacheDir, "voice-test.m4a") }, VoiceAudio.scheduler,
                SystemClock::elapsedRealtime, 300_000, { clip -> controller.sendVoice(clip) },
            ),
            300,
        )
        val playback = VoicePlayback(VoicePlayer({ _, done -> done(null) }, MediaPlayerOutput(context), VoiceAudio.scheduler))
        compose.setContent {
            var screen by remember { mutableStateOf(controller.screen) }
            DisposableEffect(controller) {
                controller.onChange = { screen = controller.screen }
                controller.load()
                onDispose { controller.onChange = null }
            }
            CompositionLocalProvider(LocalVoiceRecorder provides recorder, LocalVoicePlayback provides playback) {
                ChatScreenView(screen, ClomniTheme.make(null, false), ChatActions())
            }
        }

        val mic = compose.onNodeWithContentDescription("Səsli mesaj yaz")
        mic.assertIsDisplayed()
        mic.performTouchInput { down(center) }
        Thread.sleep(1_500)
        mic.performTouchInput { up() }

        compose.waitUntil(5_000) { source.sent.isNotEmpty() }
        val sent = source.sent.single()
        assertEquals("audio/mp4", sent.upload?.mime)
        val voice = sent.message as ClientMessage.Attachment
        assertTrue("recorded about a second and a half: ${voice.durationMs}", (voice.durationMs ?: 0) in 1_000..5_000)
        assertEquals(64, voice.waveform?.size)
        compose.waitUntil(5_000) { compose.onAllNodesWithContentDescription("Səsli mesaj", substring = true).fetchSemanticsNodes().isNotEmpty() }
    }

    /** The outbox and nothing else: it keeps what is sent and shows it as pending. */
    private class Outbox(private val dir: File) : ChatDataSource {
        val sent = mutableListOf<PendingMessage>()
        private var handler: ((ClomniChange) -> Unit)? = null
        private fun <T> done(value: T): Future<T> = FutureTask { value }.apply { run() }
        private fun refused(): Future<PendingMessage> = FutureTask<PendingMessage> { throw UnsupportedOperationException() }.apply { run() }

        override val config: MessengerConfig? = null
        override val isLive = true
        override fun conversation(id: String): Conversation? = null
        override fun refreshConversation(id: String) = done(Unit)
        override fun messages(conversationId: String): List<Message> = emptyList()
        override fun pending(conversationId: String): List<PendingMessage> = sent.toList()
        override fun canAnswer(message: Message) = false
        override fun readByOperator(conversationId: String): Long? = null
        override fun localFile(pending: PendingMessage): File? = pending.upload?.let { File(dir, it.storedAs) }
        override fun loadMessages(conversationId: String) = done(Unit)
        override fun loadOlder(conversationId: String) = done(false)
        override fun markRead(conversationId: String) = done(Unit)
        override fun setTyping(isTyping: Boolean, conversationId: String) = done(Unit)
        override fun sendText(text: String, conversationId: String, replyTo: String?) = refused()
        override fun reply(message: Message, button: MessageContent.Button) = refused()
        override fun goBack(message: Message) = refused()
        override fun submitForm(message: Message, values: Map<String, JsonElement>) = refused()
        override fun submitRating(message: Message, score: Int, comment: String?) = refused()

        override fun sendFile(
            data: ByteArray,
            fileName: String,
            mime: String,
            caption: String?,
            conversationId: String,
            replyTo: String?,
            durationMs: Long?,
            waveform: List<Int>?,
        ): Future<PendingMessage> {
            val message = ClientMessage.Attachment("", caption, replyTo = replyTo, durationMs = durationMs, waveform = waveform)
            File(dir, "staged-${message.clientId}").writeBytes(data)
            val entry = PendingMessage(conversationId, message, caption, System.currentTimeMillis(),
                upload = PendingUpload(fileName, mime, data.size.toLong(), "staged-${message.clientId}"))
            sent += entry
            handler?.invoke(ClomniChange.Messages(conversationId))
            return done(entry)
        }

        override fun retry(clientId: String) = done(Unit)
        override fun draft(openedFrom: String?) = "conv_1"

        override fun observe(handler: (ClomniChange) -> Unit): UUID {
            this.handler = handler
            return UUID.randomUUID()
        }

        override fun stopObserving(token: UUID) {
            handler = null
        }
    }
}
