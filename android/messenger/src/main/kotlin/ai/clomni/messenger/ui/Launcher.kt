package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.log.ClomniLog
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.LauncherState
import ai.clomni.messenger.presentation.ThemeOverride
import ai.clomni.messenger.protocol.MessengerConfig
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout

/**
 * Where the launcher stands: on the app's screen in front (an activity of the app, never the messenger's own), only
 * while [update] has a state. With no state it asks [surface] for nothing at all: no view is made (brief 7.2).
 */
internal class LauncherOverlay<S : Any>(private val surface: Surface<S>) {
    interface Surface<S> {
        /** Puts the button on [screen] (or updates the one already there). */
        fun show(screen: S, state: LauncherState, config: MessengerConfig?, override: ThemeOverride, tap: () -> Unit)

        fun hide(screen: S)
    }

    private var front: S? = null
    private var shownOn: S? = null

    /** What [shownOn] has, to ask the surface only for changes. */
    private var shown: Triple<LauncherState, MessengerConfig?, ThemeOverride>? = null
    private var state: LauncherState? = null
    private var config: MessengerConfig? = null
    private var override = ThemeOverride()
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

    /** [override]: `Clomni.setTheme`, over the panel's look. */
    fun update(state: LauncherState?, config: MessengerConfig?, override: ThemeOverride = ThemeOverride(), tap: () -> Unit) {
        this.state = state
        this.config = config
        this.override = override
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
        val look = Triple(current, config, override)
        if (target == null || shown == look) return
        shown = look
        surface.show(target, current, config, override, tap)
    }
}

/** The launcher on an activity: a [LauncherView] added to its window's decor view, never a system window. */
internal class ActivityLauncherSurface : LauncherOverlay.Surface<Activity> {
    override fun show(screen: Activity, state: LauncherState, config: MessengerConfig?, override: ThemeOverride, tap: () -> Unit) {
        val decor = screen.window?.decorView as? ViewGroup ?: return
        val view = decor.findViewWithTag<LauncherView>(TAG) ?: LauncherView(screen).also {
            it.tag = TAG
            decor.addView(it)
            ClomniLog.debug { "launcher: on ${screen.javaClass.simpleName}" }
        }
        val dark = (screen.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        view.bind(state, ClomniTheme.resolve(config, dark, override), tap)
    }

    override fun hide(screen: Activity) {
        val decor = screen.window?.decorView as? ViewGroup ?: return
        decor.findViewWithTag<LauncherView>(TAG)?.let {
            decor.removeView(it)
            ClomniLog.debug { "launcher: off ${screen.javaClass.simpleName}" }
        }
    }

    private companion object {
        const val TAG = "clomni_launcher"
    }
}

/**
 * The optional floating button (DESIGN-PASS-3 E1): a 56 dp circle in the brand colour at the bottom corner with the
 * operator's line mascot in it, 30 dp, white lines when on_primary is white and black ones when it is dark (the
 * original drawings, only shrunk; the asset puts their optical centre in the middle). A soft shadow (y 4, blur 12,
 * 18%), 0.97 while pressed (M6: on a spring), and the unread count in an 18 dp red badge at the top end ("99+"). A plain View,
 * so it works on any activity, Compose or not.
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
    private val whiteMascot = context.getDrawable(R.drawable.clomni_launcher_mascot_white)
    private val blackMascot = context.getDrawable(R.drawable.clomni_launcher_mascot_black)
    private var mascot: Drawable? = whiteMascot

    /** The white drawing is in the circle (for tests). */
    internal val whiteLines: Boolean get() = mascot === whiteMascot
    private var state: LauncherState? = null
    private val badgeBox = RectF()
    private val ringBox = RectF()
    private var bottomInset = 0

    /** The system bars' insets at the start and the end side (right first in a right-to-left layout). */
    private var sideInsets = 0 to 0

    /** The badge and the shadow stand out of the circle: the view is larger than it. */
    private val margin = (16 * density)
    private val circle = LauncherState.SIZE * density

    init {
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        // Above the app's own raised views; the shadow is drawn with the circle, softer than the platform's.
        elevation = 6 * density
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            outlineAmbientShadowColor = android.graphics.Color.TRANSPARENT
            outlineSpotShadowColor = android.graphics.Color.TRANSPARENT
            circlePaint.setShadowLayer(10 * density, 0f, 4 * density, SHADOW)
        }
        pivotX = margin + circle / 2
        pivotY = margin + circle / 2
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
        badgePaint.color = theme.colors.badge.argb
        ringPaint.color = theme.colors.background.argb
        textPaint.color = 0xFFFFFFFF.toInt()
        mascot = if (theme.colors.onPrimary.luminance > 0.5) whiteMascot else blackMascot
        textPaint.typeface = Typeface.create(ClomniFonts.typeface ?: Typeface.DEFAULT, Typeface.BOLD)
        contentDescription = state.accessibilityLabel
        setOnClickListener { tap() }
        place()
        invalidate()
    }

    /**
     * Pressed, it gives a little (0.97) and springs back when let go, overshooting a touch (M6); with the system's
     * animations off it stays as it is.
     */
    override fun setPressed(pressed: Boolean) {
        if (pressed != isPressed && !Motion.reduced(context)) {
            val scale = if (pressed) PRESSED_SCALE else 1f
            animate().scaleX(scale).scaleY(scale).setDuration(PRESS_MS)
                .setInterpolator(if (pressed) DecelerateInterpolator() else OvershootInterpolator(3f)).start()
        }
        super.setPressed(pressed)
    }

    @Deprecated("Deprecated in Java")
    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        // Above the navigation bar of an app drawn edge to edge.
        @Suppress("DEPRECATION")
        bottomInset = insets.systemWindowInsetBottom
        @Suppress("DEPRECATION")
        val left = insets.systemWindowInsetLeft

        @Suppress("DEPRECATION")
        val right = insets.systemWindowInsetRight
        sideInsets = if (layoutDirection == LAYOUT_DIRECTION_RTL) right to left else left to right
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
        // The panel's "left" is the start side: mirrored in a right-to-left app, as the rest of the messenger is.
        val start = state.side == MessengerConfig.LauncherPosition.LEFT
        params.gravity = Gravity.BOTTOM or (if (start) Gravity.START else Gravity.END)
        params.marginStart = edge + if (start) sideInsets.first else 0
        params.marginEnd = edge + if (start) 0 else sideInsets.second
        params.bottomMargin = edge + bottomInset + (state.bottomPadding * density).toInt()
        layoutParams = params
    }

    override fun onDraw(canvas: Canvas) {
        val radius = circle / 2
        val cx = margin + radius
        val cy = margin + radius
        canvas.drawCircle(cx, cy, radius, circlePaint)
        mascot?.let {
            val half = (MASCOT / 2 * density).toInt()
            it.setBounds((cx - half).toInt(), (cy - half).toInt(), (cx + half).toInt(), (cy + half).toInt())
            it.draw(canvas)
        }
        val badge = state?.badge ?: return
        val height = 18 * density
        val textWidth = textPaint.measureText(badge)
        val width = maxOf(height, textWidth + 10 * density)
        // Its top-end corner over the circle's, ringed in the background colour.
        val top = margin - 4 * density
        val box = if (layoutDirection == LAYOUT_DIRECTION_RTL) {
            val start = margin - 4 * density
            badgeBox.apply { set(start, top, start + width, top + height) }
        } else {
            val end = margin + circle + 4 * density
            badgeBox.apply { set(end - width, top, end, top + height) }
        }
        val ring = 2 * density
        val outer = height / 2 + ring
        ringBox.set(box.left - ring, box.top - ring, box.right + ring, box.bottom + ring)
        canvas.drawRoundRect(ringBox, outer, outer, ringPaint)
        canvas.drawRoundRect(box, height / 2, height / 2, badgePaint)
        val baseline = box.centerY() - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(badge, box.centerX(), baseline, textPaint)
    }

    private companion object {
        const val MASCOT = 30f
        const val PRESSED_SCALE = 0.97f
        const val PRESS_MS = 220L

        /** Black at 18%. */
        const val SHADOW = 0x2E000000
    }
}
