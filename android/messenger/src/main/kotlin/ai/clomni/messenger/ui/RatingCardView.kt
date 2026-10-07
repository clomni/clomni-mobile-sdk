package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.RatingCard
import ai.clomni.messenger.protocol.MessageContent.RatingComment
import ai.clomni.messenger.protocol.MessageContent.RatingScale
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

/**
 * A rating (CSAT) as the web widget draws one, in the form card's frame (radius 16, 1 dp border, padding 16): the
 * question, then five faces or stars, each a 48 dp target. When the rating asks for a comment a choice opens the field
 * and "Göndər" softly; otherwise it goes at once. Given, the card keeps the score and says thanks. [chosenAtStart]: a
 * choice made before the first frame (snapshots).
 */
@Composable
internal fun RatingCardView(card: RatingCard, theme: ClomniTheme, chosenAtStart: Int? = null, rate: (score: Int, comment: String?) -> Unit) {
    // After a failure the card opens again with what failed.
    var chosen by rememberSaveable(card.messageId, card.failure) { mutableStateOf(card.score ?: chosenAtStart) }
    var comment by rememberSaveable(card.messageId, card.failure) { mutableStateOf(card.commentText.orEmpty()) }
    var error by rememberSaveable(card.messageId) { mutableStateOf<String?>(null) }
    val asksComment = card.comment != RatingComment.HIDDEN
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(theme.colors.background.color)
            .border(1.dp, theme.colors.border.color, shape).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        BasicText(
            attributedText(card.text, theme.colors.primaryText),
            Modifier.clearAndSetSemantics { contentDescription = card.textAccessibilityLabel },
            style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary, FontWeight.Medium),
        )
        if (card.given) {
            val label = card.options.firstOrNull { it.score == card.score }?.label
            Column(
                Modifier.clearAndSetSemantics { contentDescription = listOfNotNull(label, card.commentText, card.thanks).joinToString(". ") },
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(Modifier.fillMaxWidth()) {
                    for (option in card.options) RatingOption(option, card.score, card.scale, theme, Modifier.weight(1f), null)
                }
                card.commentText?.let { BasicText(it, style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary)) }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(R.drawable.clomni_ic_check, theme.colors.textSecondary, 14.dp)
                    BasicText(card.thanks, style = clomniText(13f, theme.colors.textSecondary, FontWeight.Medium))
                }
            }
            return@Column
        }
        Row(Modifier.fillMaxWidth().selectableGroup()) {
            for (option in card.options) {
                val role = if (asksComment) Role.RadioButton else Role.Button
                RatingOption(option, chosen, card.scale, theme, Modifier.weight(1f), role) {
                    if (asksComment) {
                        chosen = option.score
                        error = null
                    } else {
                        rate(option.score, null)
                    }
                }
            }
        }
        val motion = if (reduceMotion()) 0 else 220
        AnimatedVisibility(
            asksComment && chosen != null,
            enter = expandVertically(tween(motion)) + fadeIn(tween(motion)),
            exit = shrinkVertically(tween(motion)) + fadeOut(tween(motion)),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CommentField(card, comment, error, theme) {
                    comment = it
                    error = null
                }
                val send = RoundedCornerShape(10.dp)
                Box(
                    Modifier.fillMaxWidth().fieldBox(theme.colors.primary.color).button(card.submitTitle, send) {
                        val text = comment.trim()
                        val score = chosen ?: return@button
                        if (card.comment == RatingComment.REQUIRED && text.isEmpty()) error = card.commentRequired else rate(score, text.ifEmpty { null })
                    },
                    Alignment.Center,
                ) {
                    BasicText(card.submitTitle, style = clomniText(15f, theme.colors.onPrimary, FontWeight.SemiBold))
                }
            }
        }
        card.failure?.let { BasicText(it, style = clomniText(ClomniTheme.FontSize.label, theme.colors.errorText)) }
    }
}

/**
 * One face or star in a 48 dp target. A chosen face sits on the brand's soft circle and the others fade; stars fill in
 * the brand colour up to the chosen one. [role] null: read-only, no target.
 */
@Composable
private fun RatingOption(
    option: RatingCard.Option,
    chosen: Int?,
    scale: RatingScale,
    theme: ClomniTheme,
    modifier: Modifier,
    role: Role?,
    choose: () -> Unit = {},
) {
    val selected = chosen == option.score
    val target = if (role == null) {
        Modifier
    } else {
        Modifier.clickable(interactionSource = null, indication = ShapedIndication(CircleShape, 44.dp), role = role, onClick = choose)
            .clearAndSetSemantics {
                contentDescription = option.label
                this.role = role
                this.selected = selected
            }
    }
    Box(modifier.height(ClomniTheme.Size.touchTarget.dp).then(target), Alignment.Center) {
        when (scale) {
            RatingScale.EMOJI_5 -> Box(
                Modifier.size(44.dp).alpha(if (chosen == null || selected) 1f else 0.4f).clip(CircleShape)
                    .background(if (selected) theme.colors.primarySoft.color else Color.Transparent),
                Alignment.Center,
            ) {
                // Faces keep their size at a large font: five must fit across the card.
                val size = with(LocalDensity.current) { 26.dp.toSp() }
                BasicText(option.glyph.orEmpty(), style = TextStyle(fontSize = size))
            }
            RatingScale.STAR_5 -> {
                val filled = chosen != null && option.score <= chosen
                Icon(
                    if (filled) R.drawable.clomni_ic_star else R.drawable.clomni_ic_star_outline,
                    if (filled) theme.colors.primaryText else theme.colors.textSecondary,
                    30.dp,
                )
            }
        }
    }
}

/** The comment: the form's textarea (72 high, canvas grey, 1.5 dp brand edge while focused), kept over the keyboard. */
@Composable
private fun CommentField(card: RatingCard, value: String, error: String?, theme: ClomniTheme, change: (String) -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val edge = when {
        error != null -> theme.colors.unread.color
        focused -> theme.colors.primary.color
        else -> Color.Transparent
    }
    val requester = remember { BringIntoViewRequester() }
    val ime = WindowInsets.ime
    val density = LocalDensity.current
    LaunchedEffect(focused) {
        if (focused) snapshotFlow { ime.getBottom(density) }.collect { requester.bringIntoView() }
    }
    Column(Modifier.bringIntoViewRequester(requester), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BasicTextField(
            value,
            { change(it.take(COMMENT_LIMIT)) },
            Modifier.fillMaxWidth().fieldBox(theme.colors.canvas.color, edge, 72.dp)
                .onFocusChanged { focused = it.isFocused }
                .semantics {
                    contentDescription = card.commentLabel
                    if (error != null) error(error)
                },
            textStyle = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary),
            minLines = 3,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            cursorBrush = SolidColor(theme.colors.primary.color),
            decorationBox = { inner ->
                Box(Modifier.padding(horizontal = ClomniTheme.Space.m.dp, vertical = ClomniTheme.Space.s.dp)) {
                    if (value.isEmpty()) BasicText(card.commentLabel, style = clomniText(ClomniTheme.FontSize.text, theme.colors.textSecondary), maxLines = 1)
                    inner()
                }
            },
        )
        error?.let { BasicText(it, style = clomniText(ClomniTheme.FontSize.label, theme.colors.errorText)) }
    }
}

/** client-message.json: a comment is at most 4000 characters. */
private const val COMMENT_LIMIT = 4_000
