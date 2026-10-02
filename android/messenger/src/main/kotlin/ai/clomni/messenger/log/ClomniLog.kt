package ai.clomni.messenger.log

import android.util.Log

/**
 * The SDK's log (`Clomni.setLogLevel`). Lines up to [level] go to [handler]: logcat by default, tag `Clomni`. A line
 * is only made when its level is written. The same levels as the iOS SDK's ClomniLog.
 */
internal object ClomniLog {
    enum class Level {
        /** The integration is wrong (api key, user_hash, initialize missing), or what the app asked for failed. */
        ERROR,

        /** Something was dropped or could not be done; the SDK carries on. */
        WARNING,

        /** Expected, but worth knowing: a session opened again, a newer server's message shown as its fallback. */
        INFO,

        /** Everything else, for a bug report. */
        DEBUG,
    }

    const val TAG = "Clomni"
    val defaultLevel = Level.WARNING

    /** The most detailed level written; null writes nothing. */
    @Volatile
    var level: Level? = defaultLevel

    /** Where the lines go; tests collect them here. */
    @Volatile
    var handler: (Level, String) -> Unit = ::logcat

    fun error(line: () -> String) = write(Level.ERROR, line)

    fun warning(line: () -> String) = write(Level.WARNING, line)

    fun info(line: () -> String) = write(Level.INFO, line)

    fun debug(line: () -> String) = write(Level.DEBUG, line)

    fun write(level: Level, line: () -> String) {
        val limit = this.level ?: return
        if (level <= limit) handler(level, line())
    }

    fun reset() {
        level = defaultLevel
        handler = ::logcat
    }

    private fun logcat(level: Level, line: String) {
        try {
            when (level) {
                Level.ERROR -> Log.e(TAG, line)
                Level.WARNING -> Log.w(TAG, line)
                Level.INFO -> Log.i(TAG, line)
                Level.DEBUG -> Log.d(TAG, line)
            }
        } catch (e: RuntimeException) {
            // android.util.Log is a stub outside Android (JVM unit tests)…
            println("[$TAG] ${level.name.lowercase()}: $line")
        } catch (e: LinkageError) {
            // …or layoutlib's class without its native half (Paparazzi).
            println("[$TAG] ${level.name.lowercase()}: $line")
        }
    }
}
