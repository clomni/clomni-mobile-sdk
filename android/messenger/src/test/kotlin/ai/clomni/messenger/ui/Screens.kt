package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.MessagesScreen
import androidx.compose.runtime.Composable

/** Home or the list, for the screenshot tests. */
internal enum class Shown { HOME, MESSAGES }

@Composable
internal fun MessengerScreenAt(
    home: HomeScreen,
    messages: MessagesScreen,
    theme: ClomniTheme,
    actions: MessengerActions,
    shown: Shown = Shown.HOME,
) = when (shown) {
    Shown.HOME -> HomeView(home, theme, actions)
    Shown.MESSAGES -> MessagesView(messages, theme, home.header.closeLabel, actions)
}

/** The composer as an app that declares the microphone has it: the round button shows the microphone (CM-130). */
@Composable
internal fun WithVoice(content: @Composable () -> Unit) {
    val recorder = androidx.compose.runtime.remember {
        val time = ai.clomni.messenger.presentation.FakeTime()
        VoiceRecorder(
            ai.clomni.messenger.presentation.VoiceRecorderController(
                ai.clomni.messenger.presentation.FakeMic(time), { ai.clomni.messenger.presentation.VoiceRecording.Permission.GRANTED },
                {}, { java.io.File("voice.m4a") }, time, { time.now }, 300_000, {},
            ),
            300,
        )
    }
    androidx.compose.runtime.CompositionLocalProvider(LocalVoiceRecorder provides recorder, content = content)
}
