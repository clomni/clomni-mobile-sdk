package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.core.AndroidMessenger
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerRoute
import ai.clomni.messenger.presentation.MessengerSnapshot
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
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp

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
    val route = state.route
    LaunchedEffect(coordinator) { coordinator.prepare() }
    val window = (LocalContext.current as? Activity)?.window
    // The status bar is over the dimmed app, above the sheet: light icons; the navigation bar is the sheet's.
    SideEffect { window?.barIcons(darkStatus = false, darkNavigation = !theme.isDark) }
    val close = coordinator::dismiss
    val back = coordinator::back
    val home = remember(engine) { AndroidMessenger.homeController(engine, null, runtime.identity?.name) }
    DisposableEffect(home, state.offline) {
        home.isOffline = state.offline
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
    MessengerSheet(theme, closing, closed) {
        if (!state.ready || route == null) {
            // Not ready yet: the grey skeleton, the indicator in the middle while there is no look kept, ✕ working.
            val snapshot = if (state.failed) {
                MessengerSnapshot(configLoad = MessengerSnapshot.Load.FAILED, isOffline = state.offline)
            } else {
                MessengerSnapshot(isOffline = state.offline)
            }
            val presenter = HomePresenter(ClomniStrings(state.config?.languages?.firstOrNull()), now = System.currentTimeMillis())
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
            transitionSpec = { sharedAxisX(forward, still) },
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
                    val chat = remember { AndroidMessenger.chatController(engine, shown.id, null, runtime.known) }
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

/**
 * Material 3's shared axis X: the new screen comes 30 dp from the end (from the start going back) while fading in
 * after the old one has faded; 300 ms. With "Remove animations", a plain fade.
 */
private fun sharedAxisX(forward: Boolean, still: Boolean): ContentTransform {
    if (still) return fadeIn(tween(150)) togetherWith fadeOut(tween(150))
    val distance = 90
    val easing = FastOutSlowInEasing
    val sign = if (forward) 1 else -1
    return (slideInHorizontally(tween(300, easing = easing)) { sign * distance } + fadeIn(tween(210, delayMillis = 90))) togetherWith
        (slideOutHorizontally(tween(300, easing = easing)) { -sign * distance } + fadeOut(tween(90)))
}

/** Material 3's emphasized decelerate and accelerate. */
private val EmphasizedDecelerate = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)
private val EmphasizedAccelerate = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)

/**
 * The messenger as a sheet over the app: it slides up from the bottom (350 ms, emphasized decelerate) while a scrim
 * dims the app to 32%; its top corners are 28 dp round and it starts 12 dp under the status bar. [closing] plays it
 * backwards (250 ms), then [closed]. With "Remove animations", it fades.
 */
@Composable
private fun MessengerSheet(theme: ai.clomni.messenger.presentation.ClomniTheme, closing: Boolean, closed: () -> Unit, content: @Composable () -> Unit) {
    val still = reduceMotion()
    val visible = remember { MutableTransitionState(false) }
    visible.targetState = !closing
    LaunchedEffect(visible.currentState, visible.isIdle) {
        if (closing && visible.isIdle && !visible.currentState) closed()
    }
    val scrim by animateFloatAsState(
        if (closing) 0f else 0.32f,
        tween(if (closing) 250 else 350, easing = if (closing) EmphasizedAccelerate else EmphasizedDecelerate),
        label = "scrim",
    )
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (shown) scrim else 0f))) {
        AnimatedVisibility(
            visible,
            enter = if (still) fadeIn(tween(200)) else slideInVertically(tween(350, easing = EmphasizedDecelerate)) { it },
            exit = if (still) fadeOut(tween(200)) else slideOutVertically(tween(250, easing = EmphasizedAccelerate)) { it },
        ) {
            Box(
                Modifier.fillMaxSize()
                    .windowInsetsPadding(WindowInsets.statusBars)
                    .padding(top = 12.dp)
                    .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .background(theme.colors.background.color),
            ) { content() }
        }
    }
}
