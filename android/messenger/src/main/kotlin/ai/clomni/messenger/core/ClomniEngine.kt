package ai.clomni.messenger.core

import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.api.ConfigResponse
import ai.clomni.messenger.api.Credentials
import ai.clomni.messenger.api.NewsResponse
import ai.clomni.messenger.api.PushRegistration
import ai.clomni.messenger.api.SessionIdentity
import ai.clomni.messenger.api.UserIdentity
import ai.clomni.messenger.api.samePerson
import ai.clomni.messenger.log.ClomniLog
import ai.clomni.messenger.presentation.ChatDataSource
import ai.clomni.messenger.presentation.MessengerDataSource
import ai.clomni.messenger.presentation.MessengerSession
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.ConversationWithMessages
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.MobileUser
import ai.clomni.messenger.protocol.NewsItem
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.RealtimeEvent
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.protocol.speaks
import ai.clomni.messenger.protocol.UploadedFile
import ai.clomni.messenger.realtime.RealtimeClient
import ai.clomni.messenger.store.Drafts
import ai.clomni.messenger.store.MessageStore
import ai.clomni.messenger.store.PendingMessage
import ai.clomni.messenger.store.PendingUpload
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import java.io.File
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * The SDK below the screens (brief 8·9: Api, Realtime, Store): the session, the socket, the cache and the outbox, with
 * the same names and rules as the iOS SDK's engine.
 *
 * Everything runs on one worker thread; each action answers a [Future] (its failure a [ClomniError]), the reads answer
 * at once from the store, and every [observe]r hears what changed (on the worker thread).
 *
 * Messages are sent through the outbox: each one is on disk until the server has it, and is repeated with the same
 * `client_id` until then (after 1 s, then 2 s), so a message written offline or lost with the connection arrives
 * once. Three failed attempts mark it failed; [retry] sends it again. A message the server refuses (4xx) fails at once
 * with its reason; a 409 drops it and reloads the message it answered. An attached file goes the same way: it is kept on
 * the device, uploaded (repeated like a message), and then sent with its `upload_id`, which is kept too, so a restart
 * after the upload does not upload it again.
 */
internal class ClomniEngine(
    private val api: ApiClient,
    private val credentials: Credentials,
    private val store: MessageStore,
    protocol: ProtocolJson,
    http: Lazy<OkHttpClient>,
    private val executor: ScheduledExecutorService = newWorker(),
    timing: Timing = Timing(),
    private val clock: () -> Long = System::currentTimeMillis,
) : RealtimeClient.Listener, MessengerDataSource, ChatDataSource, MessengerSession {

    data class Timing(
        val realtime: RealtimeClient.Timing = RealtimeClient.Timing(),
        /** The pause before the next attempt of a message with no answer, after [attempts] failed ones: 1 s, 2 s. */
        val outboxRetryMs: (attempts: Int) -> Long = { attempts -> 1_000L shl (attempts - 1) },
    )

    private val realtime = RealtimeClient(http, protocol, executor, api.sdkHeader, this, timing.realtime)
    private val outboxRetryMs = timing.outboxRetryMs
    private val uploads: ExecutorService =
        Executors.newCachedThreadPool { Thread(it, "clomni-upload").apply { isDaemon = true } }
    private val observers = ConcurrentHashMap<UUID, (ClomniChange) -> Unit>()
    private var wantsSocket = false
    private var inForeground = true
    private var nextAttempt: ScheduledFuture<*>? = null
    private val readSent = HashMap<String, Long>()
    private val typingSentAt = HashMap<String, Long>()

    /** The inbox is switched off in Clomni: the messenger must not open. */
    @Volatile
    override var isAppDisabled: Boolean = false
        private set

    init {
        // The previous run's state, on screen before the network answers.
        executor.execute {
            store.load()
            publish()
        }
    }

    /**
     * [handler] hears every change, on the worker thread, until [stopObserving] is called with the returned token. Any
     * number of screens can listen at once (Home, a conversation, the unread badge).
     */
    override fun observe(handler: (ClomniChange) -> Unit): UUID = UUID.randomUUID().also { observers[it] = handler }

    override fun stopObserving(token: UUID) {
        observers.remove(token)
    }

    override val isLoggedIn: Boolean get() = credentials.session != null

    // Session

    /** An anonymous visitor; the same one again on this device until logout. */
    override fun loginUnidentifiedUser(): Future<Unit> = login(SessionIdentity.Anonymous)

    /**
     * [userHash] = hex(HMAC-SHA256(identity_secret, user_id)), computed on the customer's server. An anonymous user's
     * conversations move to this user.
     */
    fun loginUser(user: UserIdentity, userHash: String?): Future<Unit> = login(SessionIdentity.User(user, userHash))

    /**
     * The stored session is reused for the same person: an expired one is refreshed on its first call, and a refused
     * refresh opens a new one then. Only another identity (or none stored) opens a new session here.
     */
    private fun login(identity: SessionIdentity): Future<Unit> = submit {
        val previous = credentials.session
        if (previous != null && identity.samePerson(credentials.identity)) {
            // A new hash, name or phone for the same person is kept for the next login.
            credentials.identity = identity
        } else {
            val session = try {
                api.open(identity)
            } catch (e: ClomniError) {
                noteDisabled(e)
                throw e
            }
            isAppDisabled = false
            // Another identified user's conversations are not this one's.
            if (previous != null && !previous.anonymous && previous.userId != session.userId) clearLocalData()
        }
        registerPush()
        notify(ClomniChange.Session)
        if (wantsSocket && inForeground) {
            realtime.stop()
            realtime.start(::endpoint)
        }
        executor.execute(::deliver)
    }

    /** Ends the session and deletes everything kept on this device for the user, unsent messages included. */
    fun logout(): Future<Unit> = submit {
        wantsSocket = false
        realtime.stop()
        nextAttempt?.cancel(false)
        api.logout()
        // The server dropped this device's token with the session; the next login registers it again.
        credentials.pushRegistration?.let { credentials.pushRegistration = it.copy(registeredFor = null) }
        clearLocalData()
        notify(ClomniChange.Session)
    }

    // Socket

    /** Opens the socket (and keeps it open, reconnecting) while the app is in the foreground. */
    override fun connect(): Future<Unit> = submit {
        wantsSocket = true
        if (inForeground) realtime.start(::endpoint)
        deliver()
        registerPush()
    }

    fun disconnect(): Future<Unit> = submit {
        wantsSocket = false
        realtime.stop()
    }

    /** In the background the socket is closed and replies arrive as push notifications. */
    fun applicationDidEnterBackground(): Future<Unit> = submit {
        inForeground = false
        realtime.stop()
    }

    fun applicationWillEnterForeground(): Future<Unit> = submit {
        inForeground = true
        if (wantsSocket) realtime.start(::endpoint)
        deliver()
        registerPush()
    }

    // Reading (from the store, at once)

    override val config: MessengerConfig? get() = store.config

    /** [config], read from disk on the calling thread if the worker has not got to it yet: for the first frame. */
    override fun cachedConfig(): MessengerConfig? = store.cachedConfig()

    override val unreadTotal: Int get() = store.unreadTotal

    override fun conversations(): List<Conversation> = store.conversations()

    /** One conversation as the store knows it. */
    override fun conversation(id: String): Conversation? = store.conversation(id)

    override fun messages(conversationId: String): List<Message> = store.messages(conversationId)

    /** The user's messages not yet confirmed by the server, oldest first; shown after [messages]. */
    override fun pending(conversationId: String): List<PendingMessage> = store.pending(conversationId)

    /** Whether a message's buttons (or form) are live: the latest interactive one, until answered. */
    override fun canAnswer(message: Message): Boolean = store.canAnswer(message)

    /** The highest `seq` the operator has read ("Oxundu"). */
    override fun readByOperator(conversationId: String): Long? = store.readByOperator(conversationId)

    /** The file of a pending attachment, to show it before the server has it. */
    override fun localFile(pending: PendingMessage): File? = pending.upload?.let(store.outbox::stagedFile)

    // Loading

    /** The config kept from last time, checked with its ETag. */
    override fun refreshConfig(language: String?): Future<MessengerConfig?> = submit {
        loadConfig(language)
        store.config
    }

    override fun refreshConversations(): Future<Unit> = submit { loadConversations() }

    /** The conversation from the server, e.g. one opened from a push before the list knew it. */
    override fun refreshConversation(id: String): Future<Unit> = submit {
        if (Drafts.isDraft(id)) return@submit
        store.putConversation(authed { api.getConversation(id) })
    }

    /**
     * A new conversation to write in, created on the server only by its first message ([Drafts]): opening the
     * messenger and closing it again leaves nothing behind. When the inbox starts new conversations with a flow
     * (`conversation.starts_with_flow`) it is created right away, with the draft's `client_id`, so the flow's first
     * messages arrive without the user writing first. Any thread.
     */
    override fun draft(openedFrom: String?): String {
        val draft = Drafts.new()
        if (openedFrom != null) draftSources[draft] = openedFrom
        if (store.config?.startsWithFlow == true) {
            submit { if (!createdDrafts.containsKey(draft)) create(draft, openedFrom) }
        }
        return draft
    }

    private val draftSources = ConcurrentHashMap<String, String>()

    /** Drafts already created, for a message sent to one before its screen moved on: it goes to the same conversation. */
    private val createdDrafts = ConcurrentHashMap<String, String>()

    private fun target(conversationId: String) = createdDrafts[conversationId] ?: conversationId

    /** Starts the inbox's new-conversation flow; its first messages come with it. */
    fun startConversation(openedFrom: String?): Future<Conversation> = submit {
        val created = authed { api.createConversation(openedFrom) }
        apply(created)
        created.conversation
    }

    /** Brings a conversation up to date: the latest page the first time, what is newer than the cache after that. */
    override fun loadMessages(conversationId: String): Future<Unit> = submit { update(conversationId) }

    /** One page further back; false when the beginning is reached. */
    override fun loadOlder(conversationId: String): Future<Boolean> = submit {
        if (Drafts.isDraft(conversationId)) return@submit false
        val oldest = store.messages(conversationId).firstOrNull()?.seq
        when {
            oldest == null -> {
                update(conversationId)
                true
            }
            oldest <= 1 -> false
            else -> {
                val page = authed { api.listMessages(conversationId, beforeSeq = oldest) }
                store.putMessages(conversationId, page.messages, syncedThrough = null)
                page.hasMore
            }
        }
    }

    /** Up to the newest message; sent once per new `seq`. */
    override fun markRead(conversationId: String): Future<Unit> = submit {
        val newest = store.messages(conversationId).lastOrNull()?.seq ?: return@submit
        if (newest <= (readSent[conversationId] ?: 0)) return@submit
        readSent[conversationId] = newest
        store.markSeen(conversationId)
        publish()
        try {
            authed { api.markRead(conversationId, newest) }
        } catch (e: ClomniError) {
            readSent.remove(conversationId)
        }
    }

    /** `on` at most every 3 seconds while typing, `off` once when the user stops. */
    override fun setTyping(isTyping: Boolean, conversationId: String): Future<Unit> = submit {
        if (Drafts.isDraft(conversationId)) return@submit
        if (isTyping) {
            val last = typingSentAt[conversationId]
            if (last != null && clock() - last < TYPING_INTERVAL_MS) return@submit
            typingSentAt[conversationId] = clock()
        } else if (typingSentAt.remove(conversationId) == null) {
            return@submit
        }
        try {
            authed { api.setTyping(conversationId, isTyping) }
        } catch (e: ClomniError) {
            ClomniLog.debug { "typing: ${e.message}" }
        }
    }

    // Sending

    /** Trimmed; an empty text, or one over the config's limit, is refused. */
    override fun sendText(text: String, conversationId: String, replyTo: String?): Future<PendingMessage> = submit {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) throw ClomniError.Rejected("empty text")
        if (trimmed.codePointCount(0, trimmed.length) > (store.config?.limits?.textChars ?: 4_000)) {
            throw ClomniError.Rejected("text over the limit")
        }
        enqueue(ClientMessage.Text(trimmed, replyTo = replyTo), conversationId, trimmed)
    }

    /** A flow button. The message's buttons go dead at once, so a second tap sends nothing. */
    override fun reply(message: Message, button: MessageContent.Button): Future<PendingMessage> = submit {
        answer(message)
        enqueue(ClientMessage.ButtonReply(message.id, button.id, button.payload), message.conversationId, button.title)
    }

    /** "← Geri" under quick replies with `allowBack`. */
    override fun goBack(message: Message): Future<PendingMessage> = submit {
        val replies = message.content as? MessageContent.QuickReplies
        if (replies?.allowBack != true) throw ClomniError.Rejected("no back button")
        answer(message)
        enqueue(ClientMessage.back(message.id), message.conversationId, null)
    }

    override fun submitForm(message: Message, values: Map<String, JsonElement>): Future<PendingMessage> = submit {
        val form = message.content as? MessageContent.Form ?: throw ClomniError.Rejected("not a form")
        answer(message)
        enqueue(ClientMessage.FormSubmit(message.id, form.formId, values), message.conversationId, null)
    }

    override fun submitRating(message: Message, score: Int, comment: String?): Future<PendingMessage> = submit {
        val rating = message.content as? MessageContent.Rating
        // A rating the outbox gave up on is open again: the new answer takes the failed one's place.
        val failed = store.outbox.entries(message.conversationId).filter {
            it.state == PendingMessage.State.FAILED && (it.message as? ClientMessage.RatingSubmit)?.replyTo == message.id
        }
        if (rating == null || rating.submitted != null || score !in 1..5 || (store.isAnswered(message.id) && failed.isEmpty())) {
            throw ClomniError.Rejected("rating not open")
        }
        failed.forEach { store.outbox.remove(it.id) }
        store.markAnswered(message.id)
        enqueue(ClientMessage.RatingSubmit(message.id, score, comment), message.conversationId, null)
    }

    /**
     * An image (already scaled to at most 2048 px) or a file, up to the config's limits (10 MB and 25 MB unless it
     * says otherwise). It is kept on this device until the server has the message, so neither a lost connection nor a
     * restart loses it: the outbox uploads it, then sends it.
     */
    override fun sendFile(
        data: ByteArray,
        fileName: String,
        mime: String,
        caption: String?,
        conversationId: String,
        replyTo: String?,
    ): Future<PendingMessage> = submit {
        val limits = store.config?.limits
        val megabytes = if (mime.startsWith("image/")) limits?.imageMb ?: 10 else limits?.fileMb ?: 25
        if (data.size > megabytes * 1_048_576L) throw ClomniError.Rejected("file over $megabytes MB")
        val message = ClientMessage.Attachment(uploadId = "", caption = caption, replyTo = replyTo)
        val stored = store.outbox.stage(message.clientId, data) ?: throw ClomniError.Rejected("file not stored")
        val upload = PendingUpload(fileName, mime, data.size.toLong(), stored)
        val entry = PendingMessage(target(conversationId), message, caption, clock(), upload = upload, openedFrom = draftSources[conversationId])
        store.outbox.add(entry)
        store.changed(ClomniChange.Messages(conversationId))
        executor.execute(::deliver)
        entry
    }

    /** [uploadId] from [upload], for an app that uploads by itself; [sendFile] does both through the outbox. */
    fun sendAttachment(uploadId: String, caption: String?, conversationId: String): Future<PendingMessage> = submit {
        enqueue(ClientMessage.Attachment(uploadId, caption), conversationId, caption)
    }

    /** On its own thread: a large file does not hold up the messages. */
    fun upload(file: File, fileName: String, mime: String): Future<UploadedFile> =
        uploads.submit(Callable { authed { api.upload(file, fileName, mime) } })

    /** Sends a failed message again, with its original client id. */
    override fun retry(clientId: String): Future<Unit> = submit {
        if (!store.outbox.retry(clientId)) throw ClomniError.Rejected("nothing to retry")
        store.outbox.entry(clientId)?.let { store.changed(ClomniChange.Messages(it.conversationId)) }
        publish()
        deliver()
    }

    fun discard(clientId: String): Future<Unit> = submit {
        store.outbox.remove(clientId)?.let { store.changed(ClomniChange.Messages(it.conversationId)) }
    }

    // User, push, flows

    /** Only the fields given change; `custom_attributes` are merged on the server. */
    fun updateUser(fields: JsonObject): Future<MobileUser> = submit { authed { api.updateUser(fields) } }

    /**
     * `Clomni.setDeviceToken`: the FCM token (FirebaseMessagingService.onNewToken). It is kept on this device and
     * registered for whoever is logged in: now, at the next login, and again when another user logs in. A new token
     * replaces the old one. A registration that fails is repeated at the next connect or return to the foreground.
     * Calls run one at a time on the worker, so a token or a logout that comes while a registration is out waits for
     * it and then wins.
     */
    fun setDeviceToken(token: String): Future<Unit> = submit {
        if (credentials.pushRegistration?.token != token) credentials.pushRegistration = PushRegistration(token)
        registerPush()
    }
    /** `Clomni.startFlow`: the flow bound to an app event, in a new conversation; null when none is bound. */
    override fun startFlow(event: String, data: JsonObject?, openMessenger: Boolean, openedFrom: String?): Future<Conversation?> = submit {
        val created = authed { api.triggerFlow(event, data, openMessenger, openedFrom) }.conversation ?: return@submit null
        apply(created)
        created.conversation
    }

    fun track(event: String, data: JsonObject?): Future<Unit> = submit { authed { api.trackEvent(event, data) } }

    /** Waits until everything queued so far has run. */
    fun awaitIdle() {
        executor.submit {}.get(30, TimeUnit.SECONDS)
    }

    /** Stops the worker (the SDK is torn down); a new engine can take over the same files. */
    fun shutdown() {
        if (executor.isShutdown) return
        executor.execute {
            realtime.stop()
            nextAttempt?.cancel(false)
        }
        executor.shutdown()
        uploads.shutdown()
    }

    // Realtime

    override fun onEvent(event: RealtimeEvent) {
        try {
            when (val data = event.data) {
                is RealtimeEvent.Payload.Ready -> {
                    live = true
                    catchUp()
                }
                is RealtimeEvent.Payload.MessageCreated -> {
                    receive(data.message)
                    val message = data.message
                    if (message.sender.type != SenderType.USER) store.changed(ClomniChange.Arrived(message.conversationId, message.sender))
                }
                is RealtimeEvent.Payload.MessageUpdated -> receive(data.message)
                is RealtimeEvent.Payload.Typing ->
                    notify(ClomniChange.Typing(data.conversationId, data.sender, data.isTyping))
                is RealtimeEvent.Payload.Read ->
                    if (data.by == SenderType.OPERATOR) store.markReadByOperator(data.conversationId, data.upToSeq)
                is RealtimeEvent.Payload.ConversationUpdated ->
                    if (!store.apply(data.update)) store.putConversation(authed { api.getConversation(data.update.id) })
                is RealtimeEvent.Payload.UnreadChanged -> store.setUnreadTotal(data.total)
                is RealtimeEvent.Payload.ConfigChanged -> loadConfig(null)
                is RealtimeEvent.Payload.Unknown, RealtimeEvent.Payload.Ping -> Unit
            }
        } catch (e: Exception) {
            ClomniLog.warning { "${event.event}: ${e.message}" }
        }
        publish()
    }

    override fun onUnauthorized() {
        try {
            api.refreshSession()
        } catch (e: ClomniError.Server) {
            relogin()
        } catch (e: ClomniError) {
            ClomniLog.info { "refresh: ${e.message}" }
        }
    }

    override fun onDisconnected() {
        live = false
    }

    /** `ready` came and the socket has not dropped since. */
    @Volatile
    private var live = false

    override val isLive: Boolean get() = live && realtime.state == RealtimeClient.State.OPEN

    // On the worker thread

    /** Runs [work] on the worker, then tells the change handler what it changed. */
    private fun <T> submit(work: () -> T): Future<T> = executor.submit(
        Callable {
            try {
                work()
            } finally {
                publish()
            }
        },
    )

    private fun publish() {
        store.commit().forEach(::notify)
    }

    private fun notify(change: ClomniChange) {
        for (observer in observers.values) {
            try {
                observer(change)
            } catch (e: Exception) {
                ClomniLog.warning { "a screen's change handler failed: ${e.message}" }
            }
        }
    }

    private fun clearLocalData() {
        store.clear()
        readSent.clear()
        typingSentAt.clear()
    }

    private fun noteDisabled(error: ClomniError) {
        if (error.code == "app_disabled") isAppDisabled = true
    }

    /** The session is gone for good (refresh refused): log in again as the same person. */
    private fun relogin(): Boolean {
        val identity = credentials.identity ?: return false
        return try {
            api.open(identity)
            true
        } catch (e: ClomniError) {
            noteDisabled(e)
            ClomniLog.warning { "login again failed: ${e.message}" }
            false
        }
    }

    /** A call that finds no usable session logs in again with the stored identity and is repeated once. */
    private fun <T> authed(call: () -> T): T = try {
        call()
    } catch (e: ClomniError) {
        val lost = e is ClomniError.NotLoggedIn || (e is ClomniError.Server && e.status == 401)
        if (!lost || !relogin()) {
            noteDisabled(e)
            throw e
        }
        call()
    }

    private fun endpoint(): RealtimeClient.Endpoint? =
        credentials.session?.let { RealtimeClient.Endpoint(it.wsUrl, it.sessionToken) }

    /** After `ready`: the conversation list, what each conversation missed since its synced `seq`, and the outbox. */
    private fun catchUp() {
        try {
            loadConversations()
        } catch (e: ClomniError) {
            ClomniLog.info { "conversations not refreshed: ${e.message}" }
        }
        for (conversation in store.conversations()) {
            val synced = store.syncedSeq(conversation.id) ?: continue
            if ((conversation.lastMessage?.seq ?: 0) <= synced) continue
            try {
                fetchAfter(conversation.id, synced)
            } catch (e: ClomniError) {
                ClomniLog.info { "catch up ${conversation.id}: ${e.message}" }
            }
        }
        deliver()
    }

    /** The language of the last config asked for: its texts are that language's, and config.changed keeps it. */
    private var configLanguage: String? = null

    /** The published news, in the config's language; kept with its ETag. */
    override fun refreshNews(language: String?): Future<List<NewsItem>> = submit {
        try {
            when (val response = authed { api.getNews(language ?: configLanguage ?: store.config.speaks(null), store.newsEtag) }) {
                NewsResponse.NotModified -> Unit
                is NewsResponse.Changed -> store.setNews(response.items, response.body, response.etag)
            }
        } catch (e: ClomniError) {
            ClomniLog.info { "news not refreshed: ${e.message}" }
        }
        store.news
    }

    override val news: List<NewsItem> get() = store.news

    /** A news item opened: the app event news_opened, with its id. */
    override fun newsOpened(id: String) {
        submit {
            runCatching { authed { api.trackEvent("news_opened", buildJsonObject { put("news_id", id) }) } }
                .onFailure { ClomniLog.info { "news_opened not sent: ${it.message}" } }
        }
    }

    /**
     * Always in a language of the SDK's choosing (the one asked for last, else the one it would speak now), never the
     * server's guess from the session: the texts kept are then known to be that language's
     * ([MessengerConfig.stringsLanguage]).
     */
    private fun loadConfig(requested: String?) {
        val language = requested ?: configLanguage ?: store.config.speaks(null)
        configLanguage = language
        try {
            when (val response = authed { api.getConfig(language, store.configEtag) }) {
                ConfigResponse.NotModified -> Unit
                is ConfigResponse.Changed -> {
                    ClomniLog.debug { "config: version ${response.config.version}, language $language" }
                    store.setConfig(response.config.answeredIn(language), response.body, response.etag, language)
                }
            }
        } catch (e: ClomniError) {
            ClomniLog.info { "config not refreshed: ${e.message}" }
        }
    }

    private fun loadConversations() {
        store.putConversations(authed { api.listConversations() }.conversations)
    }

    private fun update(conversationId: String) {
        if (Drafts.isDraft(conversationId)) return
        if (store.conversation(conversationId) == null) {
            store.putConversation(authed { api.getConversation(conversationId) })
        }
        val synced = store.syncedSeq(conversationId)
        if (synced != null) {
            fetchAfter(conversationId, synced)
        } else {
            val page = authed { api.listMessages(conversationId) }
            store.putMessages(conversationId, page.messages, syncedThrough = page.messages.maxOfOrNull { it.seq } ?: 0)
        }
    }

    private fun apply(created: ConversationWithMessages) {
        store.putConversation(created.conversation)
        val top = created.messages.maxOfOrNull { it.seq } ?: 0
        store.putMessages(created.conversation.id, created.messages, syncedThrough = top)
    }

    /** Every message after [afterSeq], page by page. */
    private fun fetchAfter(conversationId: String, afterSeq: Long) {
        var from = afterSeq
        while (true) {
            val page = authed { api.listMessages(conversationId, afterSeq = from, limit = PAGE_SIZE) }
            val top = maxOf(from, page.messages.maxOfOrNull { it.seq } ?: from)
            store.putMessages(conversationId, page.messages, syncedThrough = top)
            if (!page.hasMore || top == from) return
            from = top
        }
    }

    /** A message from the socket or an answer: kept once, its conversation fetched if new, a gap filled. */
    private fun receive(message: Message) {
        val gap = store.putMessage(message)
        if (store.conversation(message.conversationId) == null) {
            store.putConversation(authed { api.getConversation(message.conversationId) })
        }
        if (gap != null) fetchAfter(message.conversationId, gap)
    }

    private fun answer(message: Message) {
        if (!store.canAnswer(message)) throw ClomniError.Rejected("already answered")
        store.markAnswered(message.id)
    }

    private fun enqueue(message: ClientMessage, conversationId: String, preview: String?): PendingMessage {
        val entry = PendingMessage(target(conversationId), message, preview, clock(), openedFrom = draftSources[conversationId])
        store.outbox.add(entry)
        store.changed(ClomniChange.Messages(conversationId))
        // The bubble shows first; the sending follows on the worker.
        executor.execute(::deliver)
        return entry
    }

    /** Works through the outbox in order, one message at a time. */
    private fun deliver() {
        nextAttempt?.cancel(false)
        while (credentials.session != null) {
            val entry = store.outbox.next() ?: break
            if (!attempt(entry)) break
        }
        publish()
    }

    /** False when the message waits for its next attempt, which holds up the ones after it. */
    private fun attempt(entry: PendingMessage): Boolean {
        store.changed(ClomniChange.Messages(entry.conversationId))
        val status = try {
            val ready = uploaded(started(entry)) ?: return true
            val message = authed { api.sendMessage(ready.conversationId, ready.message) }
            store.outbox.remove(entry.id)
            receive(message)
            return true
        } catch (e: ClomniError.Server) {
            when {
                e.status == 409 -> {
                    // already_answered / stale_interaction: the server has moved on; show its copy of the message.
                    store.outbox.remove(entry.id)
                    entry.message.replyTo?.let(::reloadAnswered)
                    ClomniLog.info { "${entry.id}: ${e.code ?: "409"}, dropped" }
                    return true
                }
                e.status in 400..499 && e.status != 401 && e.status != 429 -> {
                    store.outbox.refuse(entry.id, e.error)
                    return true
                }
                else -> e.status
            }
        } catch (e: Exception) {
            ClomniLog.debug { "send ${entry.id}: ${e.message}" }
            null
        }
        // No answer (or a 5xx, 401, 429 the client already repeated): another attempt after a pause.
        val failed = store.outbox.recordFailure(entry.id) ?: return true
        if (failed.state == PendingMessage.State.FAILED) return true
        ClomniLog.info { "send ${entry.id}: attempt ${failed.attempts} failed${status?.let { " ($it)" }.orEmpty()}" }
        nextAttempt = executor.schedule(::deliver, outboxRetryMs(failed.attempts), TimeUnit.MILLISECONDS)
        return false
    }

    /**
     * The entry in a real conversation: a draft's first message creates it (POST /conversations, once: the outbox keeps
     * the new id before anything else is sent), and every message of the draft moves there.
     */
    private fun started(entry: PendingMessage): PendingMessage {
        val draft = entry.conversationId
        if (!Drafts.isDraft(draft)) return entry
        val id = createdDrafts[draft] ?: create(draft, entry.openedFrom)
        return store.outbox.entry(entry.id) ?: entry.copy(conversationId = id)
    }

    /** POST /conversations for [draft] (its `client_id` makes a repeat answer the same one); the outbox moves over. */
    private fun create(draft: String, openedFrom: String?): String {
        val created = authed { api.createConversation(openedFrom, Drafts.startId(draft)) }
        store.outbox.moveConversation(draft, created.conversation.id)
        createdDrafts[draft] = created.conversation.id
        apply(created)
        draftSources.remove(draft)
        store.changed(ClomniChange.Started(draft, created.conversation.id))
        store.changed(ClomniChange.Messages(draft))
        return created.conversation.id
    }

    /**
     * The entry with its file uploaded: as it is when there is none or it already went, otherwise after POST /uploads.
     * Null when it cannot be sent at all (its staged file is gone) or was discarded meanwhile.
     */
    private fun uploaded(entry: PendingMessage): PendingMessage? {
        val upload = entry.upload?.takeIf { it.uploadId == null } ?: return entry
        val file = store.outbox.stagedFile(upload)?.takeIf { it.isFile }
        if (file == null) {
            store.outbox.fail(entry.id, "file_missing")
            ClomniLog.warning { "${entry.id}: its file is gone, the message is not sent" }
            return null
        }
        val uploadId = authed { api.upload(file, upload.fileName, upload.mime) }.uploadId
        return store.outbox.uploaded(entry.id, uploadId)
    }

    /** Sends the kept token unless the server already has it for the logged-in user. On the worker. */
    private fun registerPush() {
        val registration = credentials.pushRegistration ?: return
        val user = credentials.session?.userId ?: return
        if (registration.registeredFor == user) return
        try {
            authed { api.registerDevice(registration.token) }
        } catch (e: ClomniError) {
            // Repeated at the next connect or foreground.
            return ClomniLog.warning { "push token not registered: ${e.message}" }
        }
        // A login again inside authed may have made the session someone else's.
        if (credentials.session?.userId == user) credentials.pushRegistration = registration.copy(registeredFor = user)
    }

    private fun reloadAnswered(messageId: String) {
        store.markAnswered(messageId)
        val message = store.message(messageId) ?: return
        try {
            fetchAfter(message.conversationId, maxOf(0, message.seq - 1))
        } catch (e: ClomniError) {
            ClomniLog.debug { "reload $messageId: ${e.message}" }
        }
    }

    /** The message a button reply, form or rating answers. */
    private val ClientMessage.replyTo: String?
        get() = when (this) {
            is ClientMessage.ButtonReply -> replyTo
            is ClientMessage.FormSubmit -> replyTo
            is ClientMessage.RatingSubmit -> replyTo
            else -> null
        }

    internal companion object {
        const val PAGE_SIZE = 100
        private const val TYPING_INTERVAL_MS = 3_000L

        fun newWorker(): ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "clomni-messenger").apply { isDaemon = true }
        }
    }
}
