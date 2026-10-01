package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatController
import ai.clomni.messenger.presentation.ChatHeader
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ChatScreen
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.protocol.MessengerConfig
import android.content.Context
import android.content.ContextWrapper
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import java.util.UUID

/**
 * The conversation (brief 8·7.4), kept current by [controller]: header, the transcript scrolled to its end, the
 * composer. Back and close come out as callbacks; presenting the screen is CM-074.
 */
@Composable
internal fun ClomniChat(
    controller: ChatController,
    back: () -> Unit,
    close: () -> Unit,
    conversationStarted: (String) -> Unit = {},
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
    val photo = rememberResultLauncher(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) controller.attach(refused) { Attachments.image(resolver, uri) }
    }
    val document = rememberResultLauncher(ActivityResultContracts.OpenDocument()) { uri ->
        val limit = (config?.limits?.fileMb ?: 25).coerceAtLeast(config?.limits?.imageMb ?: 10) * 1_048_576L
        if (uri != null) controller.attach(refused) { Attachments.file(resolver, uri, limit) }
    }
    var older by remember { mutableStateOf(true) }
    var loadingOlder by remember { mutableStateOf(false) }
    val actions = ChatActions(
        back = back,
        close = close,
        send = { if (controller.send(draft)) draft = "" },
        pickImage = {
            photo?.launch(PickVisualMediaRequest.Builder().setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly).build())
        },
        pickFile = { document?.launch(arrayOf("*/*")) },
        startNew = {
            writeAnyway = false
            controller.startNewConversation { id -> id?.let(conversationStarted) }
        },
        tap = controller::tap,
        submit = controller::submit,
        retry = controller::retrySending,
        retryLoad = controller::retry,
        openImage = { fullScreen = it },
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
    )
    fullScreen?.let { url -> FullScreenImage(url, screen.header.closeLabel) { fullScreen = null } }
}

@Composable
internal fun rememberTheme(config: MessengerConfig?): ClomniTheme {
    val brand = config?.brand
    val dark = ClomniTheme.isDark(brand?.theme, isSystemInDarkTheme())
    return remember(brand, dark) { ClomniTheme.make(brand, dark) }
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
) {
    Column((if (lazy) Modifier.fillMaxSize() else Modifier.fillMaxWidth()).background(theme.colors.background.color)) {
        ChatHeaderView(screen.header, theme, actions)
        screen.offline?.let { OfflineStrip(it, theme) }
        val body = if (lazy) Modifier.weight(1f).fillMaxWidth() else Modifier.fillMaxWidth()
        when (screen.phase) {
            HomeScreen.Phase.LOADING -> Column(
                body.padding(ClomniTheme.Space.xl.dp),
                verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.s.dp),
            ) {
                Box(Modifier.width(200.dp)) { SkeletonBlock(38f, theme) }
                Box(Modifier.width(222.dp)) { SkeletonBlock(58f, theme) }
                Box(Modifier.fillMaxWidth(), Alignment.CenterEnd) { Box(Modifier.width(160.dp)) { SkeletonBlock(38f, theme) } }
            }
            HomeScreen.Phase.FAILED -> Column(body.padding(ClomniTheme.Space.xl.dp)) {
                screen.failure?.let { FailureView(it, theme, actions.retryLoad) }
            }
            HomeScreen.Phase.READY -> if (lazy) {
                LazyTranscript(screen.items, theme, actions, body)
            } else {
                Column(
                    body.padding(start = ClomniTheme.Space.xl.dp, end = ClomniTheme.Space.xl.dp, top = ClomniTheme.Space.xl.dp, bottom = ClomniTheme.Space.s.dp),
                    verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xxs.dp),
                ) {
                    for (item in screen.items) ChatItemView(item, theme, actions)
                }
            }
        }
        ComposerView(screen.composer, theme, draft, changeDraft, writeAnyway, setWriteAnyway, actions)
        Announcer(screen.announcement?.id, screen.announcement?.text)
    }
}

/**
 * The transcript, scrolled to its end when it opens and whenever a new item arrives; items that arrive while it is
 * open rise 6 dp and fade in. Reaching the top asks for older messages.
 */
@Composable
private fun LazyTranscript(items: List<ChatItem>, theme: ClomniTheme, actions: ChatActions, modifier: Modifier) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = (items.size - 1).coerceAtLeast(0))
    val known = remember { items.mapTo(HashSet()) { it.id } }
    val still = reduceMotion()
    val lastId = items.lastOrNull()?.id
    LaunchedEffect(lastId) {
        if (items.isNotEmpty()) state.animateScrollToItem(items.size - 1)
    }
    val reachedTop by rememberUpdatedState(actions.reachedTop)
    LaunchedEffect(state) {
        snapshotFlow { state.firstVisibleItemIndex == 0 && state.layoutInfo.totalItemsCount > 0 }
            .collect { atTop -> if (atTop) reachedTop() }
    }
    LazyColumn(
        modifier,
        state = state,
        contentPadding = PaddingValues(
            start = ClomniTheme.Space.xl.dp,
            end = ClomniTheme.Space.xl.dp,
            top = ClomniTheme.Space.xl.dp,
            bottom = ClomniTheme.Space.s.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xxs.dp),
    ) {
        items(items, key = { it.id }) { item ->
            Box(Modifier.appearing(item.id !in known, still)) { ChatItemView(item, theme, actions) }
        }
    }
}

/** TalkBack reads a new incoming message out; the one there when the screen opened is not news. */
@Composable
private fun Announcer(id: String?, text: String?) {
    var first by remember { mutableStateOf(id) }
    var spoken by remember { mutableStateOf("") }
    LaunchedEffect(id) {
        if (id != null && id != first && text != null) spoken = text
        first = null
    }
    if (spoken.isNotEmpty()) {
        Box(
            Modifier.size(1.dp).semantics {
                liveRegion = LiveRegionMode.Polite
                contentDescription = spoken
            },
        )
    }
}

/**
 * White bar with the bottom hairline: the brand-coloured back arrow, who answers (team avatars 24, or the operator
 * 28 with the green dot), title 14.5/600 with the grey line 12 under it, ✕.
 */
@Composable
internal fun ChatHeaderView(header: ChatHeader, theme: ClomniTheme, actions: ChatActions) {
    Column(Modifier.fillMaxWidth().background(theme.colors.background.color).windowInsetsPadding(WindowInsets.statusBars)) {
        Row(
            Modifier.fillMaxWidth().padding(start = ClomniTheme.Space.xl.dp, end = ClomniTheme.Space.xl.dp, bottom = ClomniTheme.Space.m.dp),
            horizontalArrangement = Arrangement.spacedBy(ClomniTheme.Space.m.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val target = ClomniTheme.Size.touchTarget.dp
            Box(
                Modifier.bleed((target - 10.dp) / 2, (target - 17.dp) / 2).size(target).button(header.backLabel, actions.back),
                Alignment.Center,
            ) {
                Icon(R.drawable.clomni_ic_back, theme.colors.primary, 10.dp, Modifier.size(10.dp, 17.dp))
            }
            when (val lead = header.lead) {
                is ChatHeader.Lead.Team -> TeamAvatars(lead.urls, theme.colors.background, theme)
                is ChatHeader.Lead.Person -> Box {
                    ChatAvatarView(lead.avatar, ClomniTheme.Size.avatar, theme)
                    if (lead.online) {
                        Box(
                            Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp)
                                .size(ClomniTheme.Size.tabDot.dp + 4.dp).clip(CircleShape)
                                .background(theme.colors.background.color).padding(2.dp)
                                .clip(CircleShape).background(theme.colors.online.color),
                        )
                    }
                }
            }
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { heading() }) {
                BasicText(
                    header.title,
                    style = clomniText(ClomniTheme.FontSize.title, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.25f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                BasicText(
                    header.subtitle,
                    style = clomniText(ClomniTheme.FontSize.label, theme.colors.textSecondary),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            CloseButton(header.closeLabel, theme.colors.textSecondary, actions.close)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
    }
}

/** An image on black, fitted to the screen, with ✕; black until it loads (no spinner). */
@Composable
private fun FullScreenImage(url: String, closeLabel: String, close: () -> Unit) {
    Dialog(close, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (!LocalInspectionMode.current) {
                AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            }
            Box(Modifier.align(Alignment.TopEnd).windowInsetsPadding(WindowInsets.statusBars).padding(ClomniTheme.Space.xl.dp)) {
                CloseButton(closeLabel, ai.clomni.messenger.presentation.RgbColor.WHITE, close)
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
