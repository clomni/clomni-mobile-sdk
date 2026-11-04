# ai.clomni:messenger (Android) changelog

## 1.0.7

- A drag up or down that starts on a voice message scrolls the conversation: the waveform takes a drag only once it
  goes sideways (it took every touch before). Other bubbles already scrolled.
- The user can delete their own message while the conversation is not closed: «Sil» in the long-press menu, then
  "Mesaj silinsin?". A message not sent yet only leaves the queue. A closed conversation answers 409 and the message
  stays, with a short notice. A message deleted by the user or in the panel shows as a muted "Bu mesaj silindi" with
  its time, and nothing can be done with it; the conversation list says so too.
- With `home.tab_bar` on in the panel, Home, the conversations (with the unread count), the news and the questions
  are tabs under the list screens; a conversation, a news item or an answer opens over them, without the bar. Off,
  nothing changes.
- Home shows `home.news_on_home` news items (2 by default), and "Hamısı" when there are more; it opens the News tab
  or the news list.
- The questions (FAQ, `GET /faq`, kept like the news): Home's card with the first three ("Hamısı" when there are
  more), the list with a search on the device ("Heç nə tapılmadı" when nothing matches), and each answer on its own
  screen (`faq_opened`).
- The new texts come from `config.strings`, with az, en and ru in the SDK.
- A bot is named the same everywhere (its bubbles, the typing row, a quote of it, Home's latest message and the
  conversation list): the name the server sends with the message, else the panel's bot name, else the brand's. Its
  picture: the sender's, else the panel's bot picture, else the logo. It no longer always speaks as the brand.
- The unread badge on the conversations' tab is 16 dp high, ringed in the bar's colour and placed on the icon's top
  end, wholly inside the bar (4 dp under its top line); "99+" over 99. TalkBack reads the tab with the number
  ("Söhbətlər, 7 oxunmamış").
- How a screen opens: a new tab, or a screen pushed (the conversations, a conversation, a news item, an answer,
  "Hamısı"), shows its own background and the brand's spinner in the middle for at least 350 ms, and until its data
  is there; then it fades in over 150 ms. The screen before goes at once, and pushes slide with no fade, so two
  screens are never seen through each other. A screen gone back to is there at once. A tab keeps its state (scroll,
  search, pictures). With the system's animations off there is no fade, the spinner still comes first.
- The user can answer their own sent messages (swipe or «Cavabla»); the quote says "Siz". It already worked on
  Android and is now tested.
- With `config.conversation.single` on (the inbox keeps one conversation per user), every way to a new conversation
  ("Bizə mesaj göndərin", the list's card, `presentNewConversation`, "Yeni söhbət başlat") first asks for the list,
  under the spinner, and opens the conversation the server names in it (`resume_conversation_id`) with its history,
  instead of an empty one that jumped to it after the first message. None named, the switch off, offline, or a server
  without the field: a new conversation, as before.

## 1.0.6

A push that starts the app no longer counts as the app being open. When the app was not running, the push started it
with no screen, the SDK opened its connection and the server took the user for online: the dashboard stopped saying the
reply goes by push, and the replies after the first got no push. The connection now waits for one of the app's screens.
The same fix covers an SDK initialized late (React Native, Flutter, Unity): leaving the app now closes the connection,
so pushes come while the app is in the background. Nothing to change in the app; iOS stays 1.0.4.

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
