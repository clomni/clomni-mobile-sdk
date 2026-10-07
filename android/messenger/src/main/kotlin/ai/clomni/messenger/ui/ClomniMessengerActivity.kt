package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.core.AndroidMessenger
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerRoute
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.protocol.speaks
import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.Window
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * The messenger, full screen in an activity of its own (brief 8·7.2): it slides up over the app and back down when
 * closed, and the user is where they were. It draws edge to edge and places its own content around the system bars
 * and the keyboard. It is only ever started by [MessengerRuntime] while the messenger is open.
 */
internal class ClomniMessengerActivity : ComponentActivity() {
    /** Another instance took over (a notification tapped while this one was open behind the app). */
    var replaced = false

    /** The sheet is sliding away; the activity finishes when it is gone. */
    private var closing by mutableStateOf(false)

    /** Closed (✕, back, `Clomni.dismiss`): the sheet slides down, then the activity goes, with no window animation. */
    fun closeAnimated() {
        if (isFinishing) return
        closing = true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MessengerRuntime.attach(this)
        // A tap on a Clomni notification opens its conversation, the first time only (not after a rotation).
        if (savedInstanceState == null && intent.getBooleanExtra(PushNotifier.EXTRA_PUSH, false)) {
            MessengerRuntime.openFromPush(intent.getStringExtra(PushNotifier.EXTRA_CONVERSATION))
        }
        // Recreated after the process was gone, or closed before it got here: back to the app.
        if (MessengerRuntime.coordinator?.route == null) {
            finish()
            return
        }
        // The sheet animates itself (MessengerSheet); the window does not.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        }
        // The look the previous run kept, before anything is drawn (no default colour first).
        MessengerRuntime.coordinator?.firstFrame()
        window.edgeToEdge()
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = MessengerRuntime.back()
            },
        )
        setContentView(ComposeView(this).apply { setContent { MessengerRoot(MessengerRuntime, closing) { finish() } } })
    }

    override fun finish() {
        super.finish()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    override fun onDestroy() {
        MessengerRuntime.detach(this, closedByUser = isFinishing && !isChangingConfigurations)
        super.onDestroy()
    }
}

/** Under the status and navigation bars, transparent; the screens pad themselves by the insets. */
internal fun Window.edgeToEdge() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        setDecorFitsSystemWindows(false)
    } else {
        @Suppress("DEPRECATION")
        decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
    }
    @Suppress("DEPRECATION")
    statusBarColor = android.graphics.Color.TRANSPARENT
    @Suppress("DEPRECATION")
    navigationBarColor = android.graphics.Color.TRANSPARENT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        isNavigationBarContrastEnforced = false
        isStatusBarContrastEnforced = false
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        attributes = attributes.apply { layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES }
    }
}

/** Dark icons on a light bar, light icons on a dark or brand-coloured one. */
internal fun Window.barIcons(darkStatus: Boolean, darkNavigation: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val status = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
        val navigation = WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
        insetsController?.setSystemBarsAppearance(
            (if (darkStatus) status else 0) or (if (darkNavigation) navigation else 0),
            status or navigation,
        )
    } else {
        @Suppress("DEPRECATION")
        var flags = decorView.systemUiVisibility
        flags = if (darkStatus) flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR else flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            flags = if (darkNavigation) {
                flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            } else {
                flags and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
            }
        }
        @Suppress("DEPRECATION")
        decorView.systemUiVisibility = flags
    }
}

/**
 * The open messenger: a sheet over the app (DESIGN-PASS-2 7), then grey skeletons with the indicator until the SDK is
 * ready ("Yenidən cəhd et" when nothing could be reached), then the screen the coordinator's route names: Home, the
 * list, a conversation. Screens change with Material's shared-axis X (300 ms): deeper slides in from the end, back
 * from the start.
 */
@Composable
internal fun MessengerRoot(runtime: MessengerRuntime, closing: Boolean = false, closed: () -> Unit = {}) {
    val coordinator = runtime.coordinator ?: return
    val engine = runtime.engine ?: return
    val state = runtime.root
    val theme = rememberTheme(state.config)
    val shownRoute = remember { ShownRoute() }
    val route = shownRoute.of(state.route)
    LaunchedEffect(coordinator) { coordinator.prepare() }
    val window = (LocalContext.current as? Activity)?.window
    // The status bar is over the dimmed app, above the sheet: light icons; the navigation bar is the sheet's.
    SideEffect { window?.barIcons(darkStatus = false, darkNavigation = !theme.isDark) }
    val close = coordinator::dismiss
    val back = coordinator::back
    val home = remember(engine) { AndroidMessenger.homeController(engine, runtime.language, state.userName) }
    DisposableEffect(home, state.offline) {
        home.isOffline = state.offline
        onDispose {}
    }
    // G6: a login while the messenger is open greets by name at once (the name was read only when Home was built).
    DisposableEffect(home, state.userName) {
        home.userName = state.userName
        onDispose {}
    }
    val screens = rememberMessengerScreens(home, live = state.ready)
    val actions = rememberMessengerActions(
        home,
        state.source,
        close,
        back,
        openMessages = { coordinator.navigate(MessengerRoute.Messages) },
        openConversation = { coordinator.navigate(MessengerRoute.Conversation(it)) },
        openNews = { coordinator.navigate(MessengerRoute.News(it)) },
    )
    val uriHandler = LocalUriHandler.current
    val openLink: (String) -> Unit = { url ->
        if (runtime.events.link?.invoke(url) != true) runCatching { uriHandler.openUri(url) }
    }
    val intro = remember { HomeIntro(played = false) }
    CompositionLocalProvider(LocalHomeIntro provides intro) {
    MessengerSheet(theme, closing, closed, dismiss = close) {
        if (!state.ready || route == null) {
            // Not ready yet: the grey skeleton, the indicator in the middle while there is no look kept, ✕ working.
            val snapshot = if (state.failed) {
                MessengerSnapshot(configLoad = MessengerSnapshot.Load.FAILED, isOffline = state.offline)
            } else {
                MessengerSnapshot(isOffline = state.offline)
            }
            val presenter = HomePresenter(ClomniStrings(state.config.speaks(runtime.language)), now = System.currentTimeMillis())
            val skeleton = presenter.home(snapshot)
            HomeView(skeleton, theme, MessengerActions(close = close, retry = { coordinator.prepare() }))
            if (state.config == null) {
                Box(Modifier.fillMaxSize(), Alignment.Center) {
                    LoadingSpinner(!state.failed, theme.colors.primary, skeleton.loadingLabel)
                }
            }
            return@MessengerSheet
        }
        val still = reduceMotion()
        val forward = coordinator.forward
        AnimatedContent(
            route,
            Modifier.fillMaxSize(),
            transitionSpec = { pushPop(forward, still) },
            // A draft that became a conversation is the same screen: no transition for it.
            contentKey = { (it as? MessengerRoute.Conversation)?.let { open -> "chat:" + coordinator.screenKey(open.id) } ?: it },
            label = "screen",
        ) { shown ->
            val screenTheme = rememberTheme(screens.config ?: state.config)
            when (shown) {
                MessengerRoute.Home -> HomeView(screens.home, screenTheme, actions)
                MessengerRoute.Messages -> MessagesView(screens.messages, screenTheme, screens.home.header.closeLabel, actions)
                is MessengerRoute.News -> {
                    // The item as Home has it; withdrawn meanwhile, back to where it was opened from.
                    val news = remember(shown.id, screens.home) { home.newsScreen(shown.id) }
                    if (news != null) NewsView(news, screenTheme, back, close, openLink) else LaunchedEffect(Unit) { back() }
                }
                is MessengerRoute.Conversation -> key(coordinator.screenKey(shown.id)) {
                    val context = LocalContext.current
                    val chat = remember { AndroidMessenger.chatController(engine, shown.id, runtime.language, runtime.known, context.applicationContext) }
                    DisposableEffect(chat, state.offline) {
                        chat.isOffline = state.offline
                        onDispose {}
                    }
                    ClomniChat(chat, back = back, close = close)
                }
            }
        }
    }
    }
}

/**
 * The screen the sheet shows. Closing (pulled down, ✕, back out of the first screen) it goes down still showing what it
 * showed: the coordinator is back at "closed" at once, the screen is not (DESIGN-PASS-3 C4). Each opening is a new
 * activity, so a new one of these: it starts from the coordinator's route, Home.
 */
internal class ShownRoute {
    private var last: MessengerRoute? = null

    fun of(route: MessengerRoute?): MessengerRoute? {
        if (route != null) last = route
        return last
    }
}

/**
 * M2, push and pop: 300 ms, emphasized decelerate. The new screen comes 24% of the width from the end, fading in, over
 * the old one, which goes 8% the other way and dims to 0.9. Going back is the same played backwards: the screen on
 * top leaves to the end. With "Remove animations", a plain fade.
 */
private fun pushPop(forward: Boolean, still: Boolean): ContentTransform {
    if (still) return fadeIn(tween(150)) togetherWith fadeOut(tween(150))
    val move = tween<IntOffset>(300, easing = Motion.EmphasizedDecelerate)
    val fade = tween<Float>(300, easing = Motion.EmphasizedDecelerate)
    val top = { width: Int -> (width * 0.24f).roundToInt() }
    val under = { width: Int -> -(width * 0.08f).roundToInt() }
    return if (forward) {
        (slideInHorizontally(move, top) + fadeIn(fade)) togetherWith (slideOutHorizontally(move, under) + fadeOut(fade, targetAlpha = 0.9f))
    } else {
        ((slideInHorizontally(move, under) + fadeIn(fade, initialAlpha = 0.9f)) togetherWith (slideOutHorizontally(move, top) + fadeOut(fade)))
            .apply { targetContentZIndex = -1f }
    }
}

/**
 * The messenger as a sheet over the app: it slides up from the bottom (350 ms, emphasized decelerate) while a scrim
 * dims the app to 32%; its top corners are 28 dp round and it starts 12 dp under the status bar. [closing] plays it
 * backwards (250 ms), then [closed]. With "Remove animations", it fades.
 */
@Composable
private fun MessengerSheet(
    theme: ai.clomni.messenger.presentation.ClomniTheme,
    closing: Boolean,
    closed: () -> Unit,
    dismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    val still = reduceMotion()
    val visible = remember { MutableTransitionState(false) }
    visible.targetState = !closing
    LaunchedEffect(visible.currentState, visible.isIdle) {
        if (closing && visible.isIdle && !visible.currentState) closed()
    }
    // M1: the scrim 0 → 32% in 250 ms; the sheet on a spring (0.86, 400); its content fades in 180 ms, 120 ms after
    // it starts. Closing plays it backwards; pulled down and let go, the sheet keeps the finger's speed (SheetDrag).
    val scrim by animateFloatAsState(
        if (closing) 0f else 0.32f,
        tween(250, easing = if (closing) Motion.EmphasizedAccelerate else Motion.EmphasizedDecelerate),
        label = "scrim",
    )
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val inside by animateFloatAsState(
        if (shown && !closing) 1f else 0f,
        if (closing || still) tween(120) else tween(180, delayMillis = 120),
        label = "content",
    )
    val drag = rememberSheetDrag(dismiss)
    drag.still = still
    // Pulled down, the app shows through as the scrim lifts.
    // Drawn, not composed, so following the finger redraws one rectangle and recomposes nothing.
    Box(Modifier.fillMaxSize().drawBehind { drawRect(Color.Black, alpha = if (shown) scrim * (1f - drag.fraction) else 0f) }) {
        AnimatedVisibility(
            visible,
            enter = if (still) fadeIn(tween(200)) else slideInVertically(Motion.sheet(IntOffset.VisibilityThreshold)) { it },
            // Pulled all the way down, it is gone already (read only then: following the finger recomposes nothing).
            exit = when {
                still -> fadeOut(tween(200))
                closing && drag.fraction >= 1f -> ExitTransition.None
                else -> slideOutVertically(spring(stiffness = 400f, visibilityThreshold = IntOffset.VisibilityThreshold)) { it }
            },
        ) {
            Box(
                Modifier.fillMaxSize()
                    .windowInsetsPadding(WindowInsets.statusBars)
                    .padding(top = 12.dp)
                    .sheetDrag(drag),
            ) {
                Box(
                    Modifier.fillMaxSize()
                        .offset { IntOffset(0, drag.offset.roundToInt()) }
                        .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                        .background(theme.colors.background.color),
                ) {
                    val tint = if (theme.isDark) Color.White.copy(alpha = 0.12f) else Color.Black.copy(alpha = 0.08f)
                    CompositionLocalProvider(LocalPressTint provides tint) {
                        Box(Modifier.fillMaxSize().graphicsLayer { alpha = inside }) { content() }
                    }
                    // The handle: 36×4, the text colour at 20%, 4 over the bar's title block (DESIGN-PASS-3 B3); the bar
                    // itself stays where it is on every screen, so ✕ does not move.
                    Box(
                        Modifier.align(Alignment.TopCenter).padding(top = 14.dp).size(36.dp, 4.dp)
                            .clip(RoundedCornerShape(2.dp)).background(theme.colors.textPrimary.color.copy(alpha = 0.2f)),
                    )
                }
            }
        }
    }
}
