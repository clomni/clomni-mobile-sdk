package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ChatAvatar
import ai.clomni.messenger.presentation.ChatComposer
import ai.clomni.messenger.presentation.ChatController
import ai.clomni.messenger.presentation.ChatHeader
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ChatScreen
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.FormCard
import ai.clomni.messenger.presentation.RatingCard
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.toward
import ai.clomni.messenger.protocol.MessengerConfig
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The conversation (brief 8·7.4), kept current by [controller]: header, the transcript scrolled to its end, the
 * composer. Back and close come out as callbacks; presenting the screen is CM-074.
 */
@Composable
internal fun ClomniChat(
    controller: ChatController,
    back: () -> Unit,
    close: () -> Unit,
) {
    var screen by remember { mutableStateOf(controller.screen) }
    var config by remember { mutableStateOf(controller.config) }
    DisposableEffect(controller) {
        controller.onChange = {
            screen = controller.screen
            config = controller.config
        }
        controller.load()
        onDispose {
            controller.onChange = null
            controller.stop()
        }
    }
    val theme = rememberTheme(config)
    val context = LocalContext.current
    var draft by rememberSaveable { mutableStateOf("") }
    var writeAnyway by rememberSaveable { mutableStateOf(false) }
    var fullScreen by rememberSaveable { mutableStateOf<String?>(null) }
    val refused: (String?) -> Unit = { text -> if (text != null) Toast.makeText(context, text, Toast.LENGTH_LONG).show() }
    val resolver = context.contentResolver
    // A picked file waits over the field, with its preview and ×, and goes with the next send (its text the caption).
    var picked by rememberSaveable { mutableStateOf<Uri?>(null) }
    val photo = rememberResultLauncher(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) picked = uri }
    val document = rememberResultLauncher(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) picked = uri }
    // The camera (G-10): a photo, or a video up to the file limit, written to a file of the messenger's own and then
    // picked like any other. Kept across the activity being recreated while the camera app is in front.
    var shot by rememberSaveable { mutableStateOf<Uri?>(null) }
    val limit = (config?.limits?.fileMb ?: 25).coerceAtLeast(config?.limits?.imageMb ?: 10) * 1_048_576L
    val camera = rememberResultLauncher(ActivityResultContracts.TakePicture()) { taken -> if (taken) picked = shot }
    val video = rememberResultLauncher(CaptureVideoUpTo((config?.limits?.fileMb ?: 25) * 1_048_576L)) { taken -> if (taken) picked = shot }
    val cameraAccess = remember(context) { CameraAccess.of(context) }
    var afterGrant by remember { mutableStateOf<(() -> Unit)?>(null) }
    val permission = rememberResultLauncher(ActivityResultContracts.RequestPermission()) { granted ->
        val next = afterGrant
        afterGrant = null
        if (granted) next?.invoke() else refused(screen.composer.cameraDenied)
    }
    val shoot: (Boolean) -> Unit = { asVideo ->
        val launch = {
            Attachments.cameraTarget(context, asVideo)?.let { target ->
                shot = target
                runCatching { if (asVideo) video?.launch(target) else camera?.launch(target) }
                    .onFailure { refused(screen.composer.cameraDenied) }
            }
            Unit
        }
        val granted = context.checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraAccess == CameraAccess.ASK && !granted && permission != null) {
            afterGrant = launch
            permission.launch(android.Manifest.permission.CAMERA)
        } else {
            launch()
        }
    }
    val preview = picked?.let { uri ->
        remember(uri) {
            val image = resolver.getType(uri)?.startsWith("image/") == true
            PickedPreview(if (image) uri.toString() else null, Attachments.name(resolver, uri))
        }
    }
    var older by remember { mutableStateOf(true) }
    var loadingOlder by remember { mutableStateOf(false) }
    val actions = ChatActions(
        back = back,
        close = close,
        send = {
            val file = picked
            if (file != null) {
                val caption = draft.trim().ifEmpty { null }
                controller.attach(refused) { Attachments.read(resolver, file, limit)?.let { ChatController.PickedFile(it.data, it.fileName, it.mime, caption) } }
                picked = null
                draft = ""
            } else if (controller.send(draft)) {
                draft = ""
            }
        },
        pickImage = {
            photo?.launch(PickVisualMediaRequest.Builder().setMediaType(ActivityResultContracts.PickVisualMedia.ImageAndVideo).build())
        },
        pickCamera = if (cameraAccess != CameraAccess.NONE && camera != null) {
            { shoot(false) }
        } else {
            null
        },
        pickVideo = if (cameraAccess != CameraAccess.NONE && video != null) {
            { shoot(true) }
        } else {
            null
        },
        pickFile = { document?.launch(arrayOf("*/*")) },
        removePicked = { picked = null },
        startNew = {
            writeAnyway = false
            controller.startNewConversation()
        },
        tap = controller::tap,
        submit = controller::submit,
        rate = controller::rate,
        retry = controller::retrySending,
        retryLoad = controller::retry,
        openImage = { fullScreen = it },
        reply = controller::replyTo,
        cancelReply = { controller.replyTo(null) },
        reachedTop = {
            if (older && !loadingOlder) {
                loadingOlder = true
                controller.loadOlder {
                    older = it
                    loadingOlder = false
                }
            }
        },
    )
    ChatScreenView(
        screen,
        theme,
        actions,
        draft = draft,
        changeDraft = {
            draft = it
            controller.textChanged(it)
        },
        writeAnyway = writeAnyway,
        setWriteAnyway = { writeAnyway = true },
        loadingOlder = loadingOlder,
        picked = preview,
    )
    fullScreen?.let { url -> FullScreenImage(url, screen.header.closeLabel) { fullScreen = null } }
}

@Composable
internal fun rememberTheme(config: MessengerConfig?): ClomniTheme {
    val systemIsDark = isSystemInDarkTheme()
    val override = AppTheme.override
    val target = remember(config, systemIsDark, override) { ClomniTheme.resolve(config, systemIsDark, override) }
    return animateTheme(target)
}

/**
 * A new look (config.changed, `Clomni.setTheme`) fades in over 250 ms on the open screen (APPEARANCE-CONTRACT 4):
 * every colour moves from what is on screen to the new one.
 */
@Composable
private fun animateTheme(target: ClomniTheme): ClomniTheme {
    val progress = remember { Animatable(1f) }
    var from by remember { mutableStateOf(target) }
    var to by remember { mutableStateOf(target) }
    LaunchedEffect(target) {
        if (target == to) return@LaunchedEffect
        from = from.toward(to, progress.value.toDouble())
        to = target
        progress.snapTo(0f)
        progress.animateTo(1f, tween(250))
    }
    return from.toward(to, progress.value.toDouble())
}

/**
 * Header, transcript (or the skeleton, or the error) and composer, drawn from [screen]. [lazy] false lays every item
 * out at once, for screenshots of a whole conversation.
 */
@Composable
internal fun ChatScreenView(
    screen: ChatScreen,
    theme: ClomniTheme,
    actions: ChatActions,
    draft: String = "",
    changeDraft: (String) -> Unit = {},
    writeAnyway: Boolean = false,
    setWriteAnyway: () -> Unit = {},
    lazy: Boolean = true,
    /** Older messages are on their way: a small indicator at the top of the list. */
    loadingOlder: Boolean = false,
    /** A picked file waiting over the field. */
    picked: PickedPreview? = null,
    /** The transcript's hold while a choice folds away; tests hand one in to draw that moment. */
    fold: ChoiceFold = remember { ChoiceFold() },
) {
    WithOfflineCapsule(screen.offline, screen.connected, theme) { bar ->
        // G4: the whole screen stands on the keyboard, frame by frame with its animation; the composer keeps the
        // navigation bar's room only while the keyboard is down.
        Column((if (lazy) Modifier.fillMaxSize() else Modifier.fillMaxWidth()).background(theme.colors.background.color).imePadding()) {
            // The bar's line shows once the transcript has something above what is on screen.
            var scrolled by remember { mutableStateOf(false) }
            // The composer has the cursor: the keyboard takes the transcript's end up with it.
            var typing by remember { mutableStateOf(false) }
            Box(bar) { ChatHeaderView(screen.header, theme, actions, scrolled) }
            val body = if (lazy) Modifier.weight(1f).fillMaxWidth() else Modifier.fillMaxWidth()
            val inner = if (lazy) Modifier.fillMaxSize() else Modifier.fillMaxWidth()
            // What is not known yet shows nothing; once it is, all of it comes in one frame, fading in over 200 ms
            // (DESIGN-PASS-3 C5). From the cache it is there in the first frame.
            Crossfade(screen.phase, body, tween(200), label = "chat") { phase ->
                when (phase) {
                    // Nothing cached: the indicator in the middle (after 300 ms); cached messages show at once instead.
                    HomeScreen.Phase.LOADING -> Box(inner, Alignment.Center) {
                        LoadingSpinner(true, theme.colors.primary, screen.loadingLabel)
                    }
                    HomeScreen.Phase.FAILED -> Column(inner.padding(ClomniTheme.Space.xl.dp)) {
                        screen.failure?.let { FailureView(it, theme, actions.retryLoad) }
                    }
                    HomeScreen.Phase.READY -> if (lazy) {
                        LazyTranscript(screen, theme, actions, inner, fold, loadingOlder, typing) { scrolled = it }
                    } else {
                        Column(
                            inner.padding(start = ClomniTheme.Space.xl.dp, end = ClomniTheme.Space.xl.dp, top = ClomniTheme.Space.xl.dp, bottom = ClomniTheme.Space.s.dp),
                            verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xxs.dp),
                        ) {
                            for (item in screen.items) ChatItemView(item, theme, actions)
                        }
                    }
                }
            }
            // While a step waits for a button nothing is under the conversation; the composer comes back for free text, at
            // the flow's end or when an operator joins (operator, 2026-10-04). M7: its height and its opacity, 220 ms.
            val composing = screen.composer.mode != ChatComposer.Mode.Hidden
            val still = reduceMotion()
            AnimatedVisibility(
                composing,
                enter = if (still) fadeIn(tween(150)) else expandVertically(tween(220, easing = Motion.EmphasizedDecelerate)) + fadeIn(tween(220)),
                exit = if (still) fadeOut(tween(150)) else shrinkVertically(tween(220, easing = Motion.EmphasizedDecelerate)) + fadeOut(tween(220)),
            ) {
                Box(Modifier.onFocusChanged { typing = it.hasFocus }) {
                    ComposerView(screen.composer, theme, draft, changeDraft, writeAnyway, setWriteAnyway, actions, picked)
                }
            }
            if (!composing) Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
            Announcer(screen.announcement?.id, screen.announcement?.text)
        }
    }
}

/**
 * A choice's way out (operator, 2026-10-06): from the tap until its capsules have faded and folded away
 * ([CHOICE_FOLD_MS]) the transcript stays as it was, so the user's message then comes in at the end, under nothing
 * and over nothing.
 */
@Stable
internal class ChoiceFold {
    /** The transcript as it was at the tap, while the choices fold. */
    var held by mutableStateOf<List<ChatItem>?>(null)
        private set

    /** The choices folding or folded: they stay folded should they still be there after the hold. */
    var folding by mutableStateOf<String?>(null)
        private set

    fun start(items: List<ChatItem>, repliesId: String) {
        held = items
        folding = repliesId
    }

    fun release() {
        held = null
    }

    /** What the transcript shows: what it held, or [live]. */
    fun shown(live: List<ChatItem>): List<ChatItem> = held ?: live
}

/**
 * The transcript, scrolled to its end when it opens and when a new item arrives (H2): always for the user's own
 * message, choices and a form, otherwise only while the user is at the end; reading further up, "Yeni mesaj ↓" shows
 * over it instead. Items that arrive while it is open rise 6 dp and fade in. One that goes is gone in that frame: nothing fades out over what takes its place.
 * Reaching the top asks for older messages.
 */
@Composable
private fun LazyTranscript(
    screen: ChatScreen,
    theme: ClomniTheme,
    actions: ChatActions,
    modifier: Modifier,
    fold: ChoiceFold,
    loadingOlder: Boolean = false,
    typing: Boolean = false,
    scrolled: (Boolean) -> Unit = {},
) {
    val items = fold.shown(screen.items)
    // Previews hold what they were given.
    val inspecting = LocalInspectionMode.current
    LaunchedEffect(fold.held) {
        if (fold.held == null || inspecting) return@LaunchedEffect
        delay(CHOICE_FOLD_MS.toLong())
        fold.release()
    }
    val loadingLabel = screen.loadingLabel
    // While older messages load, item 0 is their indicator and the messages follow it.
    val last = items.size - 1 + if (loadingOlder) 1 else 0
    val state = rememberLazyListState(initialFirstVisibleItemIndex = last.coerceAtLeast(0))
    val known = remember { items.mapTo(HashSet()) { it.id } }
    val still = reduceMotion()
    val lastId = items.lastOrNull()?.id
    // The first messages are placed at the end at once (the list opens at its bottom, then stays); only later ones
    // scroll there, and without motion they too are simply there.
    var placed by remember { mutableStateOf(items.isNotEmpty()) }
    val density = LocalDensity.current
    // H2: the user reads further up: more than 120 dp from the end, by their own scrolling (or ours), not because
    // something arrived under them.
    var away by remember { mutableStateOf(false) }
    // Something arrived while the user was away: "Yeni mesaj ↓".
    var unseen by remember { mutableStateOf(false) }
    // Our own way to the end is on: where it passes says nothing about the user (a second message cutting it short
    // must not find the user "away").
    val auto = remember { booleanArrayOf(false) }
    LaunchedEffect(state) {
        val far = with(density) { FOLLOW_DISTANCE.roundToPx() }
        var moving = false
        snapshotFlow { state.isScrollInProgress to state.distanceToEnd() }.collect { (scrolling, distance) ->
            if (auto[0]) {
                moving = false
                return@collect
            }
            // The frame a fling stops in counts too: it is where the user left the list.
            if (scrolling || moving) away = distance > far
            moving = scrolling
            if (!away) unseen = false
        }
    }
    val toEnd: suspend () -> Unit = {
        away = false
        unseen = false
        auto[0] = true
        try {
            if (still) state.scrollToItem(last) else state.animateScrollToItem(last)
        } finally {
            auto[0] = false
        }
    }
    LaunchedEffect(lastId) {
        val newest = items.lastOrNull() ?: return@LaunchedEffect
        when {
            !placed -> state.scrollToItem(last)
            newest.takesToEnd() || !away -> toEnd()
            newest !is ChatItem.TypingItem -> unseen = true
        }
        placed = true
    }
    // The end stays in view while the user is at it and something takes room from under it, frame by frame: a picked
    // file's preview or a quote over the field, a status line under the last bubble (test report: the preview covered
    // the last messages, and "Göndərilmədi" was cut under the field). Reading further up, nothing moves; a new item
    // is the arrival's own business (above).
    val lastIndex by rememberUpdatedState(last)
    LaunchedEffect(state) {
        val slop = with(density) { 2.dp.roundToPx() }
        var was = state.distanceToEnd()
        var count = state.layoutInfo.totalItemsCount
        snapshotFlow { Triple(state.isScrollInProgress, state.distanceToEnd(), state.layoutInfo.totalItemsCount) }
            .collect { (scrolling, distance, items) ->
                val atEnd = was <= slop && items == count
                was = distance
                count = items
                if (scrolling || auto[0] || !atEnd || distance <= slop) return@collect
                auto[0] = true
                try {
                    state.keepEnd(lastIndex)
                } finally {
                    auto[0] = false
                }
                was = state.distanceToEnd()
            }
    }
    // G4/H1: while the composer has the cursor, the transcript rises with the keyboard, frame by frame with its own
    // animation: what stood just over it stays there, the last message too, however tall. A form field brings itself
    // into view instead (FormCardView).
    // The transcript's bottom edge: the keyboard, or the navigation bar while the keyboard is lower than it.
    val ime = WindowInsets.ime.union(WindowInsets.navigationBars)
    val follow by rememberUpdatedState(typing)
    LaunchedEffect(state) {
        var was = ime.getBottom(density)
        snapshotFlow { ime.getBottom(density) }.collect { now ->
            val rise = now - was
            was = now
            if (follow && rise > 0) state.scrollBy(rise.toFloat())
        }
    }
    // A tap on a quote: the quoted message is scrolled to (a third down the screen) and lit for a second.
    val scope = rememberCoroutineScope()
    var lit by remember { mutableStateOf<String?>(null) }
    val links = TranscriptLinks(screen.replyLabel, screen.copyLabel, lit) { messageId ->
        val index = items.indexOfFirst { (it as? ChatItem.BubbleItem)?.bubble?.messageId == messageId }
        if (index >= 0) {
            scope.launch {
                val target = index + if (loadingOlder) 1 else 0
                val offset = -state.layoutInfo.viewportSize.height / 3
                if (still) state.scrollToItem(target, offset) else state.animateScrollToItem(target, offset)
                lit = items[index].id
                delay(1_000)
                lit = null
            }
        }
    }
    val reachedTop by rememberUpdatedState(actions.reachedTop)
    val report by rememberUpdatedState(scrolled)
    LaunchedEffect(state) { snapshotFlow { state.canScrollBackward }.collect { report(it) } }
    LaunchedEffect(state) {
        snapshotFlow { state.firstVisibleItemIndex == 0 && state.layoutInfo.totalItemsCount > 0 }
            .collect { atTop -> if (atTop) reachedTop() }
    }
    Box(modifier) {
        LazyColumn(
            Modifier.fillMaxSize(),
            state = state,
            contentPadding = PaddingValues(
                start = ClomniTheme.Space.xl.dp,
                end = ClomniTheme.Space.xl.dp,
                top = ClomniTheme.Space.xl.dp,
                bottom = ClomniTheme.Space.s.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xxs.dp),
        ) {
            if (loadingOlder) {
                item(key = "older") {
                    Box(Modifier.fillMaxWidth(), Alignment.Center) {
                        LoadingSpinner(true, theme.colors.primary, loadingLabel, Modifier.padding(vertical = ClomniTheme.Space.s.dp), 20.dp)
                    }
                }
            }
            items(items, key = { it.id }) { item ->
                // Fades in the first time it is ever shown only: not again when it scrolls back into view.
                val fresh = remember(item.id) { known.add(item.id) }
                // M3: a new item comes in its own way (ChatItemView); one that moves slides to its place.
                CompositionLocalProvider(LocalTranscript provides links, LocalArriving provides fresh) {
                    Box(
                        Modifier.animateItem(
                            fadeInSpec = null,
                            placementSpec = if (still) null else Motion.sheet(IntOffset.VisibilityThreshold),
                            fadeOutSpec = null,
                        ).arriving(fresh, item.arrival),
                    ) {
                        if (item is ChatItem.RepliesItem) {
                            QuickRepliesView(item.block, theme, folded = fold.folding == item.id) { buttonId ->
                                fold.start(items, item.id)
                                actions.tap(buttonId, item.block.messageId)
                            }
                        } else {
                            ChatItemView(item, theme, actions)
                        }
                    }
                }
            }
        }
        NewMessageCapsule(unseen, screen.newMessageLabel, theme, Modifier.align(Alignment.BottomCenter)) {
            scope.launch { toEnd() }
        }
    }
}

/** H2: the user's own message, choices and a form take the transcript to its end wherever the user was reading. */
private fun ChatItem.takesToEnd(): Boolean = when (this) {
    is ChatItem.RepliesItem -> true
    is ChatItem.BubbleItem -> bubble.side == Bubble.Side.OUTGOING || bubble.body is FormCard || bubble.body is RatingCard
    else -> false
}

/** Scrolls so the transcript's end is at the screen's bottom, at once: a tall last item shows its end. */
private suspend fun LazyListState.keepEnd(lastIndex: Int) {
    if (lastIndex < 0) return
    if (distanceToEnd() == Int.MAX_VALUE) scrollToItem(lastIndex)
    val left = distanceToEnd()
    if (left in 1 until Int.MAX_VALUE) scrollBy(left.toFloat())
}

/** How far the transcript's end is under the screen's bottom, in px; the end not laid out yet counts as far. */
private fun LazyListState.distanceToEnd(): Int {
    val info = layoutInfo
    val last = info.visibleItemsInfo.lastOrNull() ?: return 0
    if (last.index < info.totalItemsCount - 1) return Int.MAX_VALUE
    return (last.offset + last.size + info.afterContentPadding - info.viewportEndOffset).coerceAtLeast(0)
}

/** H2: further up than this from the end, the user is reading the history and new messages leave them there. */
private val FOLLOW_DISTANCE = 120.dp

/**
 * H2: "Yeni mesaj ↓" over the transcript's end while something new is under the screen: the brand colour, 32 high,
 * radius 16, 13 medium with a 14 chevron after it, 12 over the composer. It rises 8 as it fades in (the offline
 * capsule's spring); a tap takes the transcript to its end.
 */
@Composable
internal fun NewMessageCapsule(shown: Boolean, label: String, theme: ClomniTheme, modifier: Modifier, open: () -> Unit) {
    val still = reduceMotion()
    val rise = with(LocalDensity.current) { 8.dp.roundToPx() }
    AnimatedVisibility(
        shown,
        modifier.padding(bottom = ClomniTheme.Space.m.dp),
        enter = if (still) fadeIn(tween(150)) else slideInVertically(Motion.capsule()) { rise } + fadeIn(Motion.capsule()),
        exit = if (still) fadeOut(tween(150)) else slideOutVertically(Motion.capsule()) { rise } + fadeOut(Motion.capsule()),
    ) {
        // A 48 dp target that lays out like the 32 dp pill; the press shows on the pill only.
        val press = remember { MutableInteractionSource() }
        Row(
            Modifier.bleed(vertical = 8.dp)
                .clickable(press, indication = null, role = Role.Button, onClick = open)
                .clearAndSetSemantics { contentDescription = label }
                .padding(vertical = 8.dp)
                .indication(press, ShapedIndication(RoundedCornerShape(16.dp)))
                .softShadow(16.dp, theme.colors.primary.color, ClomniTheme.Shadow.capsule)
                .heightIn(min = 32.dp)
                .padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicText(label, style = clomniText(13f, theme.colors.onPrimary, FontWeight.Medium), maxLines = 1)
            Icon(R.drawable.clomni_ic_chevron_down, theme.colors.onPrimary, 14.dp)
        }
    }
}

/**
 * TalkBack reads a new incoming message out; the one there when the screen opened is not news. Once read, the words
 * leave this node ([ANNOUNCED_MS]): kept, TalkBack found the last bot message twice when moving through the screen,
 * the bubble and this (test report).
 */
@Composable
private fun Announcer(id: String?, text: String?) {
    var first by remember { mutableStateOf(id) }
    // Null until the first news: no node at all.
    var spoken by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(id) {
        val news = id != null && id != first && text != null
        first = null
        if (news) {
            spoken = text
            delay(ANNOUNCED_MS)
            spoken = ""
        }
    }
    spoken?.let { words ->
        Box(
            Modifier.size(1.dp).semantics {
                liveRegion = LiveRegionMode.Polite
                if (words.isNotEmpty()) contentDescription = words
            },
        )
    }
}

/** Long enough for TalkBack to take the words of a polite announcement. */
internal const val ANNOUNCED_MS = 3_000L

/**
 * The conversation's [TopBar], its middle 4 under the sheet's handle: 8 after back's circle who answers (the
 * company's logo cut to a 32 circle, filled and centred, or the operator's 32 avatar with the green dot while online),
 * the name 16 semibold and the subtitle 13 under it, the block at the start and cut with "…" before ✕ (DESIGN-PASS-3 B3).
 */
@Composable
internal fun ChatHeaderView(header: ChatHeader, theme: ClomniTheme, actions: ChatActions, scrolled: Boolean = false) {
    // One height whatever comes and goes in it (a subtitle, typing, the operator's dot, the team's faces): one line
    // each, so only the user's font size changes it (DESIGN-PASS-2 10).
    TopBar(header.backLabel, actions.back, header.closeLabel, actions.close, theme, scrolled, leading = true) {
        // The company until an operator joins, then the operator: a 200 ms crossfade between the two.
        Crossfade(header, animationSpec = tween(200), label = "header") { shown -> HeaderLead(shown, theme) }
    }
}

@Composable
private fun HeaderLead(header: ChatHeader, theme: ClomniTheme) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box {
            when (val lead = header.lead) {
                is ChatHeader.Lead.Brand -> BrandLogo(lead.logo, theme)
                is ChatHeader.Lead.Person -> ChatAvatarView(lead.avatar, 32f, theme)
            }
            if ((header.lead as? ChatHeader.Lead.Person)?.online == true) {
                Box(
                    Modifier.align(Alignment.BottomEnd).offset(2.dp, 2.dp)
                        .size(12.dp).clip(CircleShape)
                        .background(theme.colors.background.color).padding(2.dp)
                        .clip(CircleShape).background(theme.colors.online.color),
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f, fill = false).semantics(mergeDescendants = true) { heading() }) {
            BasicText(
                header.title,
                style = clomniText(16f, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.25f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            BasicText(
                header.subtitle,
                style = clomniText(13f, theme.colors.textSecondary, lineHeight = 1.3f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** The company's logo in a circle, cropped to fill it from the centre; its initial on the brand colour without one. */
@Composable
private fun BrandLogo(logo: ChatAvatar, theme: ClomniTheme) {
    val size = ClomniTheme.Size.logo
    val url = logo.url
    if (url != null) {
        RemoteImage(
            url,
            ImageSizing.Kind.ICON,
            size,
            Color.Transparent,
            Modifier.size(size.dp).clip(CircleShape).clearAndSetSemantics {},
        )
        return
    }
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(theme.colors.primary.color)
            .clearAndSetSemantics {},
        Alignment.Center,
    ) {
        BasicText(logo.initial, style = clomniText(15f, theme.colors.onPrimary, FontWeight.Bold))
    }
}

/** An image on black, fitted to the screen, with ✕; black until it loads (no spinner). */
@Composable
private fun FullScreenImage(url: String, closeLabel: String, close: () -> Unit) {
    Dialog(close, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (!LocalInspectionMode.current) {
                AsyncImage(url, null, ClomniImages.loader(LocalContext.current), Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            }
            Box(Modifier.align(Alignment.TopEnd).windowInsetsPadding(WindowInsets.statusBars).closeButtonPlace()) {
                CloseButton(closeLabel, CloseStyle.ON_MEDIA, ai.clomni.messenger.presentation.ClomniTheme.make(null, true), close)
            }
        }
    }
}

/**
 * An activity-result launcher without activity-compose: registered with the hosting activity's registry for as long
 * as the screen is shown. Null where there is no activity (previews, screenshot tests).
 */
@Composable
private fun <I, O> rememberResultLauncher(contract: ActivityResultContract<I, O>, result: (O) -> Unit): ActivityResultLauncher<I>? {
    val owner = LocalContext.current.registryOwner() ?: return null
    val key = rememberSaveable { UUID.randomUUID().toString() }
    val current by rememberUpdatedState(result)
    val launcher = remember(owner, key) { owner.activityResultRegistry.register(key, contract) { current(it) } }
    DisposableEffect(launcher) { onDispose { launcher.unregister() } }
    return launcher
}

private tailrec fun Context.registryOwner(): ActivityResultRegistryOwner? = when (this) {
    is ActivityResultRegistryOwner -> this
    is ContextWrapper -> baseContext.registryOwner()
    else -> null
}
