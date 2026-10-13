# ai.clomni:messenger (Android) changelog

## 1.0.5

The camera's FileProvider is the SDK's own class (`ai.clomni.messenger.ui.ClomniFileProvider`), so it no longer
collides with apps or libraries that declare androidx's `FileProvider` themselves, such as unity-webview: their build
stopped at the manifest merge ("provider#androidx.core.content.FileProvider@authorities … collides with another
value"). Its authority (`<applicationId>.clomni.camera`) and paths are unchanged. An app that added `tools:replace` to
get past the merge should remove it. Nothing else changes; iOS stays 1.0.4.

## 1.0.4

A flow decides whether the user can type, as its steps are set in Clomni. Buttons whose step lets the user type keep
the field under them, so an answer can be typed as well as tapped. A step that turns typing off hides the field while
the flow runs, and the lock stays after the flow is over: the bar then offers only a new conversation ("Söhbət
bağlanıb · Yeni söhbət başlat" without writing into this one). The lock (`conversation.flow.input_disabled`) is kept
in the copy on disk. With an earlier server, and with flows that do not use these settings, nothing changes: the
server sends the lock only when it is on.

## 1.0.3

The microphone answers the moment it is touched: the circle, the haptic and the clock start at once, and the hold that
records is counted from the touch, not from when the microphone is ready (on a phone that took up to two seconds, so a
short message was refused with "hold to record"). The recorder starts off the main thread.

## 1.0.2

Voice messages, as in WhatsApp: hold the microphone to record, slide left to cancel, slide up to lock, listen
before sending; voice bubbles with a filling waveform and 1×, 1.5×, 2× speed. The microphone sits to the right of the
field and turns into send once there is text; the emoji button is gone (the keyboard has emoji). Messages written
offline wait with their clock and go as soon as the network is back. Bare domains such as clomni.ai are links. The
joined line stands before the operator's first message; next to the user's own last message, the company's face. A
flow whose choice leads nowhere gives the composer back. The kept user is greeted by name on the next launch; the
messenger speaks one language online and offline; debug logs reach the system log. The attachment sheet takes a photo or a video with the camera (no permission needed unless the app declares
CAMERA). The launcher shows after a late initialize (React Native, Flutter, Unity); an app with a singleTask activity
no longer loses the open messenger; an announcement is read once by TalkBack. Recording needs the app to declare
`RECORD_AUDIO` in its own manifest (without it the microphone is not shown).

## 1.0.1

The session carries the app's package name (`app_identifier`: the `applicationId`, with any `applicationIdSuffix`), so
an inbox that names an Android package accepts its keys only from that app, as iOS already did with the bundle ID.
When the two differ, the server refuses the key and the error in the log names the package name the app sent.

## 1.0.0

The first release: the Clomni Messenger in the app's own screens (Jetpack Compose, Android 6.0+), with users and
identity verification, the flows' buttons, attachments, ratings, push replies through the app's own Firebase, the
unread count and events. The look and the texts come from the panel. Depends only on OkHttp, kotlinx.serialization,
Coil and Jetpack Compose. Distributed on Maven Central as `ai.clomni:messenger`.
