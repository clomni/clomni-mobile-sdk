package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatComposer
import ai.clomni.messenger.presentation.ClomniTheme
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private val Decelerate = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)

/**
 * The attachment sheet (DESIGN-PASS-2 12), a bottom sheet in the way of Material 3's (the SDK does not depend on its
 * library): a handle on top; rows 56 high, a 24 icon and 16 text: "Şəkil və ya video" (the system's photo picker),
 * "Kamera" (only when the app may use the camera), "Fayl" (the system's file picker). No cancel row: a tap on the scrim,
 * back, or dragging it down closes it.
 */
@Composable
internal fun AttachmentSheet(composer: ChatComposer, theme: ClomniTheme, actions: ChatActions, dismiss: () -> Unit) {
    BottomSheet(theme, dismiss) { close ->
        SheetRow(R.drawable.clomni_ic_file_image, composer.mediaLabel, theme) { close(actions.pickImage) }
        actions.pickCamera?.let { camera -> SheetRow(R.drawable.clomni_ic_camera, composer.cameraLabel, theme) { close(camera) } }
        SheetRow(R.drawable.clomni_ic_file, composer.fileLabel, theme) { close(actions.pickFile) }
    }
}

/**
 * A bottom sheet over a 32% scrim: it rises 300 ms, a handle on top; a tap on the scrim, back, or dragging it down
 * (more than 30%, or a flick) closes it. [dragAnywhere] false drags it by the handle only, for content that scrolls
 * itself. [content] gets `close(after)`: the sheet slides away, then `after` runs.
 */
@Composable
internal fun BottomSheet(
    theme: ClomniTheme,
    dismiss: () -> Unit,
    dragAnywhere: Boolean = true,
    content: @Composable ColumnScope.(close: (after: () -> Unit) -> Unit) -> Unit,
) {
    val offset = remember { Animatable(1f) }
    val height = remember { intArrayOf(1) }
    val scope = rememberCoroutineScope()
    val still = reduceMotion()
    LaunchedEffect(Unit) { if (still) offset.snapTo(0f) else offset.animateTo(0f, tween(300, easing = Decelerate)) }
    val close: (after: () -> Unit) -> Unit = { after ->
        scope.launch {
            if (!still) offset.animateTo(1f, tween(200))
            dismiss()
            after()
        }
    }
    val drag = Modifier.draggable(
        rememberDraggableState { delta ->
            scope.launch { offset.snapTo((offset.value + delta / height[0]).coerceIn(0f, 1f)) }
        },
        Orientation.Vertical,
        onDragStopped = { velocity ->
            if (offset.value > 0.3f || velocity > 1500f) close {} else offset.animateTo(0f, tween(200))
        },
    )
    Dialog({ close {} }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(
            Modifier.fillMaxSize()
                .background(Color.Black.copy(alpha = 0.32f * (1f - offset.value)))
                .clickable(remember { MutableInteractionSource() }, indication = null) { close {} },
            Alignment.BottomCenter,
        ) {
            Column(
                Modifier.fillMaxWidth()
                    .onSizeChanged { height[0] = it.height.coerceAtLeast(1) }
                    .offset { IntOffset(0, (offset.value * height[0]).roundToInt()) }
                    .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .background(theme.colors.background.color)
                    .clickable(remember { MutableInteractionSource() }, indication = null) {}
                    .then(if (dragAnywhere) drag else Modifier)
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(bottom = 8.dp),
            ) {
                // The handle: 32×4, grey.
                Box(Modifier.fillMaxWidth().then(if (dragAnywhere) Modifier else drag).padding(top = 16.dp, bottom = 8.dp), Alignment.Center) {
                    Box(Modifier.size(32.dp, 4.dp).clip(RoundedCornerShape(2.dp)).background(theme.colors.border.color))
                }
                content(close)
            }
        }
    }
}

@Composable
private fun SheetRow(icon: Int, label: String, theme: ClomniTheme, pick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).button(label, onClick = pick).padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.Start,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, theme.colors.textPrimary, 24.dp)
        Spacer(Modifier.width(16.dp))
        BasicText(label, style = clomniText(16f, theme.colors.textPrimary))
    }
}

/** The emoji button's sheet: the system's emoji picker (categories, recently used); a pick closes it. */
@Composable
internal fun EmojiSheet(theme: ClomniTheme, pick: (String) -> Unit, dismiss: () -> Unit) {
    BottomSheet(theme, dismiss, dragAnywhere = false) { close ->
        AndroidView(
            { context ->
                androidx.emoji2.emojipicker.EmojiPickerView(context).apply {
                    setOnEmojiPickedListener { item -> close { pick(item.emoji) } }
                }
            },
            Modifier.fillMaxWidth().height(320.dp),
        )
    }
}
