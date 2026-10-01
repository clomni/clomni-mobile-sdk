package ai.clomni.messenger.realtime

import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.RealtimeEvent
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class RealtimeConnectionTest {

    private val server = MockWebServer()
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private val events = LinkedBlockingQueue<RealtimeEvent>()
    private val disconnects = LinkedBlockingQueue<Unit>()
    private val attempts = Collections.synchronizedList(mutableListOf<Int>())
    private var token = "st_1"
    private var onUnauthorized: () -> Unit = {}
    private val opened = LinkedBlockingQueue<WebSocket>()
    private val received = LinkedBlockingQueue<String>()

    private fun connection(secondMs: Long = 1_000) = RealtimeConnection(
        http = OkHttpClient(),
        protocol = ProtocolJson(),
        executor = executor,
        sdkHeader = "android/1.0.0",
        listener = object : RealtimeConnection.Listener {
            override fun onEvent(event: RealtimeEvent) {
                events.put(event)
            }

            override fun onUnauthorized() = onUnauthorized.invoke()

            override fun onDisconnected() {
                disconnects.put(Unit)
            }
        },
        timing = RealtimeConnection.Timing(reconnectDelayMs = { attempts += it; 20L }, secondMs = secondMs),
    )

    /** The server side of the next connection. */
    private fun acceptSocket() {
        server.enqueue(
            MockResponse().withWebSocketUpgrade(
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        opened.put(webSocket)
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        received.put(text)
                    }

                    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                        webSocket.close(1000, null)
                    }
                },
            ),
        )
    }

    private fun RealtimeConnection.startOn() = executor.submit {
        start { RealtimeConnection.Endpoint(server.url("/v1/realtime").toString().replace("http://", "ws://"), token) }
    }.get()

    private fun <T> LinkedBlockingQueue<T>.next(): T = poll(5, TimeUnit.SECONDS) ?: throw AssertionError("nothing arrived")

    @After
    fun stop() {
        executor.shutdownNow()
        server.shutdown()
    }

    @Test
    fun deliversEventsAndAnswersPings() {
        acceptSocket()
        val connection = connection()
        connection.startOn()
        val socket = opened.next()
        val request = server.takeRequest()
        assertEquals("/v1/realtime?token=st_1&protocol=v1", request.path)
        assertEquals("android/1.0.0", request.getHeader("X-Clomni-SDK"))

        socket.send("""{"event":"ready","data":{"user_id":"usr_1","heartbeat_sec":25},"ts":"2026-10-01T10:30:01Z"}""")
        assertEquals(RealtimeEvent.Payload.Ready("usr_1", 25), events.next().data)
        socket.send("""{"event":"ping","ts":"2026-10-01T10:30:26Z"}""")
        assertTrue(received.next().startsWith("""{"event":"pong","ts":"""))
        socket.send("""{"event":"unread.changed","data":{"total":2},"ts":"2026-10-01T10:30:27Z"}""")
        assertEquals(RealtimeEvent.Payload.UnreadChanged(2), events.next().data)
        socket.send("not json")
        socket.send("""{"event":"conversation.rated","data":{}}""")
        assertEquals(RealtimeEvent.Payload.Unknown("conversation.rated"), events.next().data)
        assertEquals(RealtimeConnection.State.OPEN, executor.submit<RealtimeConnection.State> { connection.state }.get())
    }

    @Test
    fun reconnectsWithGrowingDelaysThatStartAgainAfterReady() {
        repeat(4) { acceptSocket() }
        connection().startOn()
        opened.next().close(1000, null)
        disconnects.next()
        opened.next().close(1001, null)
        disconnects.next()
        val third = opened.next()
        third.send("""{"event":"ready","data":{"user_id":"usr_1","heartbeat_sec":25}}""")
        events.next()
        third.close(1000, null)
        opened.next()
        assertEquals(listOf(0, 1, 0), attempts)
        assertEquals(4, server.requestCount)
    }

    @Test
    fun twoMissedPingsMeanTheConnectionIsGone() {
        acceptSocket()
        acceptSocket()
        // heartbeat_sec 1 = 100 ms here: silence for 250 ms gives the connection up.
        connection(secondMs = 100).startOn()
        val first = opened.next()
        first.send("""{"event":"ready","data":{"user_id":"usr_1","heartbeat_sec":1}}""")
        events.next()
        // Pings keep it alive.
        repeat(6) {
            Thread.sleep(100)
            first.send("""{"event":"ping"}""")
        }
        assertEquals(1, server.requestCount)
        // Then the server goes quiet.
        disconnects.next()
        opened.next()
        assertEquals(2, server.requestCount)
    }

    @Test
    fun refusedHandshakeRefreshesTheTokenFirst() {
        server.enqueue(MockResponse().setResponseCode(401).setBody("""{"error":{"code":"token_expired","message":"m","request_id":"r"}}"""))
        acceptSocket()
        onUnauthorized = { token = "st_2" }
        connection().startOn()
        opened.next()
        assertEquals("/v1/realtime?token=st_1&protocol=v1", server.takeRequest().path)
        assertEquals("/v1/realtime?token=st_2&protocol=v1", server.takeRequest().path)
    }

    @Test
    fun stoppedMeansStopped() {
        acceptSocket()
        acceptSocket()
        val connection = connection()
        connection.startOn()
        val socket = opened.next()
        executor.submit { connection.stop() }.get()
        socket.send("""{"event":"unread.changed","data":{"total":2}}""")
        Thread.sleep(200)
        assertEquals(1, server.requestCount)
        assertTrue(events.isEmpty())
        assertEquals(RealtimeConnection.State.STOPPED, connection.state)

        // No session: nothing to connect to.
        executor.submit { connection.start { null } }.get()
        assertEquals(RealtimeConnection.State.STOPPED, connection.state)
        executor.submit { connection.start { RealtimeConnection.Endpoint("not a url", "st_1") } }.get()
        assertEquals(RealtimeConnection.State.STOPPED, connection.state)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun retryNowSkipsTheWait() {
        acceptSocket()
        acceptSocket()
        val connection = RealtimeConnection(
            OkHttpClient(),
            ProtocolJson(),
            executor,
            "android/1.0.0",
            object : RealtimeConnection.Listener {
                override fun onEvent(event: RealtimeEvent) = Unit
                override fun onUnauthorized() = Unit
                override fun onDisconnected() {
                    disconnects.put(Unit)
                }
            },
            RealtimeConnection.Timing(reconnectDelayMs = { 60_000L }),
        )
        connection.startOn()
        opened.next().close(1000, null)
        disconnects.next()
        assertEquals(RealtimeConnection.State.WAITING, executor.submit<RealtimeConnection.State> { connection.state }.get())
        executor.submit { connection.retryNow() }.get()
        opened.next()
        assertEquals(2, server.requestCount)
    }

    @Test
    fun delays() {
        assertEquals(
            listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L, 30_000L),
            (0..7).map(RealtimeConnection::reconnectDelayMs),
        )
    }
}
