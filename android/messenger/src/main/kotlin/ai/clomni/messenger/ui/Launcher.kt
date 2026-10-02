package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.LauncherState
import ai.clomni.messenger.protocol.MessengerConfig
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.widget.FrameLayout

/**
 * Where the launcher stands: on the app's screen in front (an activity of the app, never the messenger's own), only
 * while [update] has a state. With no state it asks [surface] for nothing at all: no view is made (brief 7.2).
 */
internal class LauncherOverlay<S : Any>(private val surface: Surface<S>) {
    interface Surface<S> {
        /** Puts the button on [screen] (or updates the one already there). */
        fun show(screen: S, state: LauncherState, config: MessengerConfig?, tap: () -> Unit)

        fun hide(screen: S)
    }

    private var front: S? = null
    private var shownOn: S? = null

    /** What [shownOn] has, to ask the surface only for changes. */
    private var shown: Pair<LauncherState, MessengerConfig?>? = null
    private var state: LauncherState? = null
    private var config: MessengerConfig? = null
    private var tap: () -> Unit = {}

    /** An app screen came to the front. */
    fun resumed(screen: S) {
        front = screen
        render()
    }

    /** It left the front (another activity, the messenger, the background). */
    fun paused(screen: S) {
        if (front === screen) front = null
        render()
    }

    fun update(state: LauncherState?, config: MessengerConfig?, tap: () -> Unit) {
        this.state = state
        this.config = config
        this.tap = tap
        render()
    }

    private fun render() {
        val target = front.takeIf { state != null }
        shownOn?.let {
            if (it !== target) {
                surface.hide(it)
                shown = null
            }
        }
        shownOn = target
        val current = state ?: return
        if (target == null || shown == current to config) return
        shown = current to config
        surface.show(target, current, config, tap)
    }
}

/** The launcher on an activity: a [LauncherView] added to its window's decor view, never a system window. */
internal class ActivityLauncherSurface : LauncherOverlay.Surface<Activity> {
    override fun show(screen: Activity, state: LauncherState, config: MessengerConfig?, tap: () -> Unit) {
        val decor = screen.window?.decorView as? ViewGroup ?: return
        val view = decor.findViewWithTag<LauncherView>(TAG) ?: LauncherView(screen).also {
            it.tag = TAG
            decor.addView(it)
        }
        val dark = (screen.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        view.bind(state, ClomniTheme.resolve(config, dark), tap)
    }

    override fun hide(screen: Activity) {
        val decor = screen.window?.decorView as? ViewGroup ?: return
        decor.findViewWithTag<LauncherView>(TAG)?.let(decor::removeView)
    }

    private companion object {
        const val TAG = "clomni_launcher"
    }
}

/**
 * The optional floating button: a 56 dp brand-coloured circle at the bottom corner with the chat mark, the unread
 * count on it ("99+"). A plain View, so it works on any activity, Compose or not.
 */
@SuppressLint("ViewConstructor")
internal class LauncherView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
        // Sized with the circle, not with the user's font scale.
        textSize = 11 * resources.displayMetrics.density
    }
    private val icon = context.getDrawable(R.drawable.clomni_ic_chat_filled)?.mutate()
    private var state: LauncherState? = null
    private val badgeBox = RectF()
    private val ringBox = RectF()
    private var bottomInset = 0
    private var sideInsets = 0 to 0

    /** The badge may stand out of the circle: the view is a little larger than it. */
    private val margin = (6 * density)
    private val circle = LauncherState.SIZE * density

    init {
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        elevation = 6 * density
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setOval(margin.toInt(), margin.toInt(), (margin + circle).toInt(), (margin + circle).toInt())
            }
        }
        val side = (circle + 2 * margin).toInt()
        layoutParams = FrameLayout.LayoutParams(side, side)
    }

    fun bind(state: LauncherState, theme: ClomniTheme, tap: () -> Unit) {
        this.state = state
        circlePaint.color = theme.colors.primary.argb
        badgePaint.color = theme.colors.unread.argb
        ringPaint.color = theme.colors.background.argb
        textPaint.color = 0xFFFFFFFF.toInt()
        icon?.colorFilter = PorterDuffColorFilter(theme.colors.onPrimary.argb, PorterDuff.Mode.SRC_IN)
        textPaint.typeface = Typeface.create(ClomniFonts.typeface ?: Typeface.DEFAULT, Typeface.BOLD)
        contentDescription = state.accessibilityLabel
        setOnClickListener { tap() }
        place()
        invalidate()
    }

    @Deprecated("Deprecated in Java")
    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        // Above the navigation bar of an app drawn edge to edge.
        @Suppress("DEPRECATION")
        bottomInset = insets.systemWindowInsetBottom
        @Suppress("DEPRECATION")
        sideInsets = insets.systemWindowInsetLeft to insets.systemWindowInsetRight
        place()
        return insets
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestApplyInsets()
    }

    private fun place() {
        val state = state ?: return
        val params = layoutParams as? FrameLayout.LayoutParams ?: return
        val edge = (LauncherState.EDGE_PADDING * density - margin).toInt()
        val left = state.side == MessengerConfig.LauncherPosition.LEFT
        params.gravity = Gravity.BOTTOM or (if (left) Gravity.START else Gravity.END)
        params.marginStart = edge + if (left) sideInsets.first else 0
        params.marginEnd = edge + if (left) 0 else sideInsets.second
        params.bottomMargin = edge + bottomInset + (state.bottomPadding * density).toInt()
        layoutParams = params
    }

    override fun onDraw(canvas: Canvas) {
        val radius = circle / 2
        val cx = margin + radius
        val cy = margin + radius
        canvas.drawCircle(cx, cy, radius, circlePaint)
        icon?.let {
            val half = (12 * density).toInt()
            it.setBounds((cx - half).toInt(), (cy - half).toInt(), (cx + half).toInt(), (cy + half).toInt())
            it.draw(canvas)
        }
        val badge = state?.badge ?: return
        val height = 18 * density
        val textWidth = textPaint.measureText(badge)
        val width = maxOf(height, textWidth + 10 * density)
        // Its top-end corner over the circle's, ringed in the background colour.
        val right = margin + circle + 4 * density
        val top = margin - 4 * density
        val box = badgeBox.apply { set(right - width, top, right, top + height) }
        val ring = 2 * density
        val outer = height / 2 + ring
        ringBox.set(box.left - ring, box.top - ring, box.right + ring, box.bottom + ring)
        canvas.drawRoundRect(ringBox, outer, outer, ringPaint)
        canvas.drawRoundRect(box, height / 2, height / 2, badgePaint)
        val baseline = box.centerY() - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(badge, box.centerX(), baseline, textPaint)
    }
}
