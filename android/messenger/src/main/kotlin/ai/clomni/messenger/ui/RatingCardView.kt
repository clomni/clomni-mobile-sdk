package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.RatingCard
import ai.clomni.messenger.protocol.MessageContent.RatingComment
import ai.clomni.messenger.protocol.MessageContent.RatingScale
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * A rating (CSAT) as the web widget draws one, in the form card's frame (radius 16, 1 dp border, padding 16): the
 * question, then five faces or stars, each a 48 dp target. When the rating asks for a comment, a choice opens the form's
 * textarea and "Göndər" as the card grows; otherwise it goes at once. Given, the card keeps the score and says thanks.
 * [chosenAtStart]: a choice made before the first frame (snapshots).
 */
@Composable
internal fun RatingCardView(card: RatingCard, theme: ClomniTheme, chosenAtStart: Int? = null, rate: (score: Int, comment: String?) -> Unit) {
    // After a failure the card opens again with what failed.
    var chosen by rememberSaveable(card.messageId, card.note) { mutableStateOf(card.score ?: chosenAtStart) }
    var comment by rememberSaveable(card.messageId, card.note) { mutableStateOf(card.commentText.orEmpty()) }
    var error by rememberSaveable(card.messageId) { mutableStateOf<String?>(null) }
    val open = !card.given
    val asksComment = card.comment != RatingComment.HIDDEN
    val shown = if (open) chosen else card.score
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(theme.colors.background.color)
            .border(1.dp, theme.colors.border.color, shape)
            .then(if (reduceMotion()) Modifier else Modifier.animateContentSize(tween(220)))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        BasicText(
            attributedText(card.text, theme.colors.primaryText),
            Modifier.clearAndSetSemantics { contentDescription = card.textAccessibilityLabel },
            style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary, FontWeight.Medium),
        )
        val given = card.score?.let { card.labels.getOrNull(it - 1) }.orEmpty()
        Row(Modifier.fillMaxWidth().then(if (open) Modifier.selectableGroup() else Modifier.clearAndSetSemantics { contentDescription = given })) {
            for (score in 1..5) {
                val role = if (!open) null else if (asksComment) Role.RadioButton else Role.Button
                RatingOption(score, card.labels[score - 1], shown, card.scale, theme, Modifier.weight(1f), role) {
                    if (asksComment) {
                        chosen = score
                        error = null
                    } else {
                        rate(score, null)
                    }
                }
            }
        }
        if (open && asksComment && chosen != null) {
            FormFieldView(card.commentField, comment, error, false, theme) {
                comment = it
                error = null
            }
            FormButton(card.submitTitle, theme) {
                val text = comment.trim().take(ChatPresenter.COMMENT_CHARS)
                if (card.comment == RatingComment.REQUIRED && text.isEmpty()) error = card.commentRequired else rate(chosen!!, text.ifEmpty { null })
            }
        }
        if (!open) card.commentText?.let { BasicText(it, style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary)) }
        card.note?.let {
            BasicText(it, style = clomniText(13f, if (open) theme.colors.errorText else theme.colors.textSecondary, FontWeight.Medium))
        }
    }
}

/** emoji_5, from 1 to 5, as the web widget draws them. */
private val FACES = listOf("😞", "😑", "😐", "😀", "😍")

/**
 * One face or star in a 48 dp target. A chosen face sits on the brand's soft circle and the others fade; stars fill in
 * the brand colour up to the chosen one. [role] null: read-only, no target.
 */
@Composable
private fun RatingOption(
    score: Int,
    label: String,
    chosen: Int?,
    scale: RatingScale,
    theme: ClomniTheme,
    modifier: Modifier,
    role: Role?,
    choose: () -> Unit,
) {
    val selected = chosen == score
    val target = if (role == null) {
        Modifier
    } else {
        Modifier.clickable(interactionSource = null, indication = ShapedIndication(CircleShape, 44.dp), role = role, onClick = choose)
            .clearAndSetSemantics {
                contentDescription = label
                this.role = role
                this.selected = selected
            }
    }
    Box(modifier.height(ClomniTheme.Size.touchTarget.dp).then(target), Alignment.Center) {
        if (scale == RatingScale.STAR_5) {
            val filled = chosen != null && score <= chosen
            Icon(
                if (filled) R.drawable.clomni_ic_star else R.drawable.clomni_ic_star_outline,
                if (filled) theme.colors.primaryText else theme.colors.textSecondary,
                30.dp,
            )
        } else {
            // Faces keep their size at a large font: five must fit across the card.
            val face = TextStyle(fontSize = with(LocalDensity.current) { 26.dp.toSp() })
            BasicText(
                FACES[score - 1],
                Modifier.size(44.dp).alpha(if (chosen == null || selected) 1f else 0.4f).clip(CircleShape)
                    .background(if (selected) theme.colors.primarySoft.color else Color.Transparent)
                    .wrapContentSize(),
                style = face,
            )
        }
    }
}
