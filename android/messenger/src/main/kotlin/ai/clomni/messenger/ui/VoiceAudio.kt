package ai.clomni.messenger.ui

import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.log.ClomniLog
import ai.clomni.messenger.presentation.AudioOutput
import ai.clomni.messenger.presentation.MicInput
import ai.clomni.messenger.presentation.Scheduler
import ai.clomni.messenger.presentation.VoiceFiles
import ai.clomni.messenger.presentation.VoiceRecording
import ai.clomni.messenger.presentation.Waveform
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * The platform's side of voice messages (CM-130), with nothing but Android's own audio: MediaRecorder writes AAC in
 * MP4 (.m4a, mono, 22.05 kHz, 32 kbit/s: about 240 KB a minute), MediaPlayer plays, OkHttp fetches into the cache.
 */
internal object VoiceAudio {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { Thread(it, "clomni-voice").apply { isDaemon = true } }

    /** The UI thread's timer. */
    val scheduler = Scheduler { delayMs, action ->
        val runnable = Runnable(action)
        main.postDelayed(runnable, delayMs)
        return@Scheduler { main.removeCallbacks(runnable) }
    }

    /** Recordings being made and fetched; logout clears it with the pictures. */
    fun directory(context: Context): File = context.cacheDir.resolve("clomni_voice")

    /** A new file for the next recording. */
    fun newRecording(context: Context): File =
        File(directory(context).apply { mkdirs() }, "voice-${SystemClock.elapsedRealtimeNanos()}.m4a")

    fun clear(context: Context) {
        io.execute { directory(context).deleteRecursively() }
    }

    /** Recordings from the server: fetched once into [directory], then from there. */
    fun files(context: Context, client: Lazy<OkHttpClient> = lazy { ApiClient.defaultClient() }): VoiceFiles = VoiceFiles { url, done ->
        io.execute {
            val file = runCatching { fetch(directory(context), client.value, url) }
                .onFailure { ClomniLog.warning { "voice message not fetched: ${it.message}" } }
                .getOrNull()
            main.post { done(file) }
        }
    }

    private fun fetch(directory: File, client: OkHttpClient, url: String): File {
        val name = MessageDigest.getInstance("SHA-256").digest(url.toByteArray()).joinToString("") { "%02x".format(it) }.take(32)
        val file = File(directory.apply { mkdirs() }, name)
        if (file.length() > 0) return file
        client.newCall(Request.Builder().url(url).build()).execute().use { response ->
            check(response.isSuccessful) { "HTTP ${response.code}" }
            val partial = File(directory, "$name.part")
            partial.outputStream().use { out -> response.body!!.byteStream().copyTo(out) }
            check(partial.renameTo(file)) { "could not keep $name" }
        }
        return file
    }

    /**
     * The microphone permission the app declares (the SDK's manifest does not add it, so an app without voice messages
     * asks for no microphone). Without it there is no microphone button, and the log says why once.
     */
    fun declared(context: Context): Boolean {
        val declared = runCatching {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions
                ?.contains(Manifest.permission.RECORD_AUDIO) == true
        }.getOrDefault(false)
        if (!declared && !loggedUndeclared) {
            loggedUndeclared = true
            ClomniLog.warning { "voice messages are off: the app's manifest has no android.permission.RECORD_AUDIO" }
        }
        return declared
    }

    private var loggedUndeclared = false

    /** Granted; never asked or asked again allowed; or refused for good (only the settings can give it now). */
    fun permission(activity: Activity?, context: Context): VoiceRecording.Permission {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            return VoiceRecording.Permission.GRANTED
        }
        val asked = prefs(context).getBoolean(ASKED, false)
        val rationale = activity?.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) == true
        return if (asked && !rationale) VoiceRecording.Permission.DENIED else VoiceRecording.Permission.UNDECIDED
    }

    /** The system asked once: a later refusal without the rationale is for good. */
    fun markAsked(context: Context) = prefs(context).edit().putBoolean(ASKED, true).apply()

    private fun prefs(context: Context) = context.getSharedPreferences("clomni_voice", Context.MODE_PRIVATE)
    private const val ASKED = "mic_asked"

    /** "Ayarlara keç": the app's page in the system settings, where the microphone is allowed. */
    fun openSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }
}

/**
 * [MicInput] on MediaRecorder. Its prepare and start run on a thread of their own: they can take a good part of a
 * second on a device, and on the UI thread they held back the press's overlay and haptic tick (CM-131). The rest runs
 * on the UI thread once the start came back.
 */
internal class MediaRecorderMic(private val context: Context) : MicInput {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L

    /** The start on its way; a stop or a cancel before it comes back clears it, and what it began is thrown away. */
    private var starting: Any? = null

    override fun start(file: File, ready: (Boolean) -> Unit) {
        val ticket = Any()
        starting = ticket
        worker.execute {
            val recorder = record(file)
            val at = SystemClock.elapsedRealtime()
            main.post {
                if (starting !== ticket) {
                    if (recorder != null) worker.execute { discard(recorder, file) }
                    return@post
                }
                starting = null
                this.recorder = recorder
                this.file = file.takeIf { recorder != null }
                startedAt = at
                ready(recorder != null)
            }
        }
    }

    /** A MediaRecorder recording into [file], or null when the microphone cannot be had. On [worker]. */
    private fun record(file: File): MediaRecorder? {
        val recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        return try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioChannels(1)
            recorder.setAudioSamplingRate(SAMPLE_RATE)
            recorder.setAudioEncodingBitRate(BIT_RATE)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
            recorder.start()
            recorder
        } catch (e: Exception) {
            ClomniLog.warning { "the microphone did not start: ${e.message}" }
            recorder.release()
            file.delete()
            null
        }
    }

    override fun level(): Float = Waveform.levelOfAmplitude(runCatching { recorder?.maxAmplitude ?: 0 }.getOrDefault(0))

    override fun stop(): Long? {
        starting = null
        val recorder = recorder ?: return null
        val duration = SystemClock.elapsedRealtime() - startedAt
        // stop() throws when nothing was recorded yet; the file is then useless.
        val ok = runCatching { recorder.stop() }.isSuccess
        recorder.release()
        this.recorder = null
        if (!ok) file?.delete()
        return duration.takeIf { ok }
    }

    override fun cancel() {
        starting = null
        recorder?.let { discard(it, null) }
        recorder = null
        file?.delete()
        file = null
    }

    private fun discard(recorder: MediaRecorder, file: File?) {
        runCatching { recorder.stop() }
        recorder.release()
        file?.delete()
    }

    private companion object {
        const val SAMPLE_RATE = 22_050
        const val BIT_RATE = 32_000
        val main = Handler(Looper.getMainLooper())
        val worker = Executors.newSingleThreadExecutor { Thread(it, "clomni-microphone").apply { isDaemon = true } }
    }
}

/** [AudioOutput] on MediaPlayer, with the speech attributes and the audio focus a voice message asks for. */
internal class MediaPlayerOutput(context: Context) : AudioOutput {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var player: MediaPlayer? = null
    private var listener: AudioOutput.Listener? = null
    private var rate = 1f
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val focusChange = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0 && player?.isPlaying == true) {
            player?.pause()
            listener?.interrupted()
        }
    }
    private val focus: Any? = if (Build.VERSION.SDK_INT >= 26) {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(focusChange).build()
    } else {
        null
    }

    override fun open(file: File, listener: AudioOutput.Listener) {
        close()
        this.listener = listener
        val player = MediaPlayer()
        this.player = player
        try {
            player.setAudioAttributes(attributes)
            player.setDataSource(file.absolutePath)
            player.setOnPreparedListener { if (this.player === it) listener.ready(it.duration.toLong()) }
            player.setOnCompletionListener {
                if (this.player === it) {
                    abandonFocus()
                    listener.finished()
                }
            }
            player.setOnErrorListener { failed, _, _ ->
                if (this.player === failed) fail()
                true
            }
            player.prepareAsync()
        } catch (e: Exception) {
            ClomniLog.warning { "voice message cannot play: ${e.message}" }
            fail()
        }
    }

    private fun fail() {
        val listener = listener
        close()
        listener?.failed()
    }

    override fun play(rate: Float) {
        val player = player ?: return
        this.rate = rate
        requestFocus()
        runCatching {
            // On a paused player a new speed starts it by itself; set before start, it is simply the speed.
            player.playbackParams = player.playbackParams.setSpeed(rate)
            player.start()
        }.onFailure { fail() }
    }

    override fun pause() {
        runCatching { player?.pause() }
        abandonFocus()
    }

    override fun seek(positionMs: Long) {
        runCatching { player?.seekTo(positionMs.toInt()) }
    }

    override fun setRate(rate: Float) {
        this.rate = rate
        val player = player ?: return
        if (player.isPlaying) runCatching { player.playbackParams = player.playbackParams.setSpeed(rate) }
    }

    override val positionMs: Long get() = runCatching { player?.currentPosition?.toLong() }.getOrNull() ?: 0

    override fun close() {
        player?.let { runCatching { it.release() } }
        player = null
        listener = null
        abandonFocus()
    }

    override fun duration(file: File): Long? = runCatching {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } finally {
            retriever.release()
        }
    }.getOrNull()?.takeIf { it > 0 }

    private fun requestFocus() {
        if (Build.VERSION.SDK_INT >= 26) {
            audio.requestAudioFocus(focus as AudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(focusChange, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) {
            audio.abandonAudioFocusRequest(focus as AudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(focusChange)
        }
    }
}
