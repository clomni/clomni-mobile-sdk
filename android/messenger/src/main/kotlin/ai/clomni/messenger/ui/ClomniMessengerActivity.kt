package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.core.AndroidMessenger
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerRoute
import ai.clomni.messenger.presentation.MessengerSnapshot
import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.Window
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext

/**
 * The messenger, full screen in an activity of its own (brief 8·7.2): it slides up over the app and back down when
 * closed, and the user is where they were. It draws edge to edge and places its own content around the system bars
 * and the keyboard. It is only ever started by [MessengerRuntime] while the messenger is open.
 */
internal class ClomniMessengerActivity : ComponentActivity() {
    /** Another instance took over (a notification tapped while this one was open behind the app). */
    var replaced = false

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, R.anim.clomni_slide_up, R.anim.clomni_stay)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, R.anim.clomni_stay, R.anim.clomni_slide_down)
        }
        window.edgeToEdge()
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = MessengerRuntime.back()
            },
        )
        setContentView(ComposeView(this).apply { setContent { MessengerRoot(MessengerRuntime) } })
    }

    override fun finish() {
        super.finish()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            @Suppress("DEPRECATION")
            overridePendingTransition(R.anim.clomni_stay, R.anim.clomni_slide_down)
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
    statusBarColor = Color.TRANSPARENT
    @Suppress("DEPRECATION")
    navigationBarColor = Color.TRANSPARENT
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
 * The open messenger: grey skeletons until the SDK is ready (never an empty screen; "Yenidən cəhd et" when nothing
 * could be reached), then Home or a conversation as the coordinator's route says.
 */
@Composable
internal fun MessengerRoot(runtime: MessengerRuntime) {
    val coordinator = runtime.coordinator ?: return
    val engine = runtime.engine ?: return
    val state = runtime.root
    val theme = rememberTheme(state.config)
    val route = state.route
    LaunchedEffect(coordinator) { coordinator.prepare() }
    val window = (LocalContext.current as? Activity)?.window
    // The conversation's top is the background; Home's is its header, with header_text's colour on it.
    val lightTop = if (route is MessengerRoute.Conversation && state.ready) !theme.isDark else theme.colors.headerText.luminance < 0.5
    SideEffect { window?.barIcons(darkStatus = lightTop, darkNavigation = !theme.isDark) }
    val close = coordinator::dismiss
    Box(Modifier.fillMaxSize().background(theme.colors.background.color)) {
        when {
            route is MessengerRoute.Conversation && state.ready -> key(route.id) {
                val chat = remember { AndroidMessenger.chatController(engine, route.id, null, runtime.known) }
                DisposableEffect(chat, state.offline) {
                    chat.isOffline = state.offline
                    onDispose {}
                }
                ClomniChat(
                    chat,
                    back = { coordinator.navigate(MessengerRoute.Home) },
                    close = close,
                    conversationStarted = coordinator::conversationStarted,
                )
            }
            route == MessengerRoute.Home && state.ready -> {
                val home = remember { AndroidMessenger.homeController(engine, null, runtime.identity?.name) }
                DisposableEffect(home, state.offline) {
                    home.isOffline = state.offline
                    onDispose {}
                }
                ClomniMessenger(
                    home,
                    openedFrom = state.source,
                    close = close,
                    openConversation = { coordinator.navigate(MessengerRoute.Conversation(it)) },
                    conversationStarted = coordinator::conversationStarted,
                )
            }
            else -> {
                // Not ready yet, or a conversation being started: grey blocks, ✕ still working.
                val snapshot = if (state.failed) {
                    MessengerSnapshot(configLoad = MessengerSnapshot.Load.FAILED, isOffline = state.offline)
                } else {
                    MessengerSnapshot(isOffline = state.offline)
                }
                val presenter = HomePresenter(ClomniStrings(state.config?.languages?.firstOrNull()), now = System.currentTimeMillis())
                HomeView(presenter.home(snapshot), theme, MessengerActions(close = close, retry = { coordinator.prepare() }))
            }
        }
    }
}
