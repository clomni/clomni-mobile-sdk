package ai.clomni.messenger.realtime

import ai.clomni.messenger.protocol.Iso8601
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.RealtimeEvent
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * The realtime socket (`wss://…/v1/realtime?token=…&protocol=v1`). It only receives, apart from answering pings.
 *
 * - Lost, or refused, it reconnects after 1, 2, 4, 8, 16, then every 30 seconds; the delays start again after `ready`.
 * - Nothing heard for two pings (`heartbeat_sec` from `ready`, 25 until then) means the connection is gone.
 * - A handshake refused with 401 asks the listener to refresh the session before the next attempt.
 *
 * Every method and every listener call runs on [executor], the SDK's own worker thread.
 */
internal class RealtimeConnection(
    private val http: OkHttpClient,
    private val protocol: ProtocolJson,
    private val executor: ScheduledExecutorService,
    private val sdkHeader: String,
    private val listener: Listener,
    private val timing: Timing = Timing(),
) {
    interface Listener {
        /** A frame other than a ping: known events and [RealtimeEvent.Payload.Unknown] ones alike. */
        fun onEvent(event: RealtimeEvent)

        /** The handshake answered 401: refresh the session; the next attempt asks [Endpoint] again. */
        fun onUnauthorized()

        fun onDisconnected()
    }

    data class Endpoint(val wsUrl: String, val token: String)

    data class Timing(
        val reconnectDelayMs: (attempt: Int) -> Long = ::reconnectDelayMs,
        /** One second of `heartbeat_sec`; tests shorten it. */
        val secondMs: Long = 1_000,
    )

    enum class State { STOPPED, CONNECTING, OPEN, WAITING }

    var state: State = State.STOPPED
        private set

    private var endpoint: (() -> Endpoint?)? = null
    private var socket: WebSocket? = null
    private var generation = 0
    private var attempt = 0
    private var heartbeatSec = DEFAULT_HEARTBEAT_SEC
    private var reconnect: ScheduledFuture<*>? = null
    private var watchdog: ScheduledFuture<*>? = null

    /** Keeps a socket open to what [endpoint] answers (null: no session, so nothing to connect to) until [stop]. */
    fun start(endpoint: () -> Endpoint?) {
        this.endpoint = endpoint
        if (state == State.STOPPED) open()
    }

    /** The app went to the background, or the user logged out: replies come as push notifications now. */
    fun stop() {
        endpoint = null
        generation++
        reconnect?.cancel(false)
        watchdog?.cancel(false)
        socket?.close(1000, null)
        socket = null
        attempt = 0
        state = State.STOPPED
    }

    /** Reconnect now rather than after the current delay (the network came back). */
    fun retryNow() {
        if (state == State.WAITING) {
            reconnect?.cancel(false)
            open()
        }
    }

    private fun open() {
        val target = endpoint?.invoke()
        if (target == null) {
            state = State.STOPPED
            return
        }
        // OkHttp parses the ws(s) scheme as http(s), which is how a socket handshake starts anyway.
        val base = WS_SCHEME.replace(target.wsUrl) { "http${it.groupValues[1]}://" }.toHttpUrlOrNull()
        if (base == null) {
            state = State.STOPPED
            return
        }
        val url = base.newBuilder().addQueryParameter("token", target.token).addQueryParameter("protocol", "v1").build()
        val gen = ++generation
        state = State.CONNECTING
        heartbeatSec = DEFAULT_HEARTBEAT_SEC
        val request = Request.Builder().url(url).header("X-Clomni-SDK", sdkHeader).build()
        socket = http.newWebSocket(
            request,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) = post(gen) {
                    state = State.OPEN
                    armWatchdog()
                }

                override fun onMessage(webSocket: WebSocket, text: String) = post(gen) { frame(webSocket, text) }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(1000, null)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = post(gen) { lost() }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = post(gen) {
                    if (response?.code == 401) listener.onUnauthorized()
                    lost()
                }
            },
        )
    }

    /** Runs [block] on the worker thread, unless the socket it is about has since been replaced or stopped. */
    private fun post(gen: Int, block: () -> Unit) {
        executor.execute { if (gen == generation) block() }
    }

    private fun frame(webSocket: WebSocket, text: String) {
        armWatchdog()
        if (isPing(text)) {
            val pong = buildJsonObject {
                put("event", "pong")
                put("ts", Iso8601.format(System.currentTimeMillis()))
            }
            webSocket.send(pong.toString())
            return
        }
        val event = protocol.parseEvent(text) ?: return
        val ready = event.data as? RealtimeEvent.Payload.Ready
        if (ready != null) {
            attempt = 0
            heartbeatSec = ready.heartbeatSec.takeIf { it > 0 } ?: DEFAULT_HEARTBEAT_SEC
            armWatchdog()
        }
        listener.onEvent(event)
    }

    private fun lost() {
        generation++
        watchdog?.cancel(false)
        socket?.cancel()
        socket = null
        state = State.WAITING
        listener.onDisconnected()
        if (state != State.WAITING) return // the listener stopped or restarted the connection
        val gen = generation
        val delay = timing.reconnectDelayMs(attempt++)
        reconnect = executor.schedule({ if (gen == generation) open() }, delay, TimeUnit.MILLISECONDS)
    }

    /** Two pings' worth of silence (plus half a ping for a late one) and the connection is given up. */
    private fun armWatchdog() {
        watchdog?.cancel(false)
        val heartbeat = heartbeatSec * timing.secondMs
        val gen = generation
        watchdog = executor.schedule({ if (gen == generation) lost() }, heartbeat * 2 + heartbeat / 2, TimeUnit.MILLISECONDS)
    }

    private fun isPing(text: String): Boolean =
        runCatching { ((Json.parseToJsonElement(text) as JsonObject)["event"] as JsonPrimitive).content == "ping" }
            .getOrDefault(false)

    internal companion object {
        const val DEFAULT_HEARTBEAT_SEC = 25
        private val WS_SCHEME = Regex("^ws(s?)://", RegexOption.IGNORE_CASE)

        /** 1, 2, 4, 8, 16, then 30 seconds. */
        fun reconnectDelayMs(attempt: Int): Long = minOf(1_000L shl minOf(attempt, 5), 30_000L)
    }
}
