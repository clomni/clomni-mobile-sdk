package ai.clomni.messenger.presentation

/**
 * When the loading indicator shows (DESIGN-PASS 5): only once a load has lasted [delayMs] (150, contract 1.0.7b §3),
 * so a quick one never flashes it, and then for at least [minimumMs] (400), so it never blinks. Times are a monotonic
 * clock's, ms.
 */
internal class LoadingGate(private val delayMs: Long = 150, private val minimumMs: Long = 400) {
    private var loadingSince: Long? = null
    private var shownAt: Long? = null

    /** Whether it shows at [now], with the load going on or not. */
    fun visible(loading: Boolean, now: Long): Boolean {
        if (loading) {
            val since = loadingSince ?: now.also { loadingSince = it }
            if (shownAt == null && now - since >= delayMs) shownAt = now
        } else {
            loadingSince = null
            if (shownAt?.let { now - it >= minimumMs } == true) shownAt = null
        }
        return shownAt != null
    }

    /** When [visible] can next change by itself (the delay or the minimum running out); null when it cannot. */
    fun nextChange(loading: Boolean): Long? = when {
        loading && shownAt == null -> loadingSince?.plus(delayMs)
        !loading -> shownAt?.plus(minimumMs)
        else -> null
    }
}
