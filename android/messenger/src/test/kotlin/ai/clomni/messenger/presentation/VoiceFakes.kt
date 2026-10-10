package ai.clomni.messenger.presentation

import java.io.File

/** A clock and its timers, moved by hand: [advance] runs whatever falls due, in order, at its own time. */
internal class FakeTime : Scheduler {
    var now = 0L
        private set

    private class Timer(val due: Long, val order: Int, val action: () -> Unit)

    private val timers = mutableListOf<Timer>()
    private var order = 0

    override fun after(delayMs: Long, action: () -> Unit): () -> Unit {
        val timer = Timer(now + delayMs, order++, action)
        timers += timer
        return { timers.remove(timer) }
    }

    fun advance(ms: Long) {
        val end = now + ms
        while (true) {
            val next = timers.filter { it.due <= end }.minWithOrNull(compareBy({ it.due }, { it.order })) ?: break
            timers.remove(next)
            now = next.due
            next.action()
        }
        now = end
    }

    val pending: Int get() = timers.size
}

/**
 * The microphone's test double (CI has none): writes a few bytes where it records, measures by [time], and says how
 * loud it is from [level].
 */
internal class FakeMic(private val time: FakeTime) : MicInput {
    var starts = true
    var stopsEmpty = false
    var level = 0.5f
    val started = mutableListOf<File>()
    var stops = 0
    var cancels = 0
    private var file: File? = null
    private var startedAt = 0L

    override fun start(file: File): Boolean {
        if (!starts) return false
        file.writeText("m4a")
        started += file
        this.file = file
        startedAt = time.now
        return true
    }

    override fun level(): Float = level

    override fun stop(): Long? {
        stops++
        if (stopsEmpty) {
            file?.delete()
            return null
        }
        return time.now - startedAt
    }

    override fun cancel() {
        cancels++
        file?.delete()
    }
}

/** The speaker's double: what was asked of it, in order; the test answers through [listener]. */
internal class FakeOutput : AudioOutput {
    val calls = mutableListOf<String>()
    var listener: AudioOutput.Listener? = null
    var position = 0L
    val lengths = HashMap<File, Long>()

    override fun open(file: File, listener: AudioOutput.Listener) {
        calls += "open ${file.name}"
        this.listener = listener
    }

    override fun play(rate: Float) {
        calls += "play $rate"
    }

    override fun pause() {
        calls += "pause"
    }

    override fun seek(positionMs: Long) {
        position = positionMs
        calls += "seek $positionMs"
    }

    override fun setRate(rate: Float) {
        calls += "rate $rate"
    }

    override val positionMs: Long get() = position

    override fun close() {
        calls += "close"
    }

    override fun duration(file: File): Long? = lengths[file]
}

/** Fetches that wait for the test to answer them. */
internal class FakeFiles : VoiceFiles {
    val asked = mutableListOf<Pair<String, (File?) -> Unit>>()

    override fun fetch(url: String, done: (File?) -> Unit) {
        asked += url to done
    }

    fun answer(index: Int, file: File?) = asked[index].second(file)
}
