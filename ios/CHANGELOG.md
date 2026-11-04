# ClomniMessenger for iOS — changelog

## 1.0.7

Send empties the field on the tap, as on Android, and puts the text (or the picked file) back if it could not go. It
used to empty only when the send returned, which for a new conversation's first message is after the server has created
the conversation; a second tap in that time sent the message twice.

A drag that starts on a message bubble scrolls the conversation again (iOS 18 and later). The swipe to answer and the
voice message's waveform now use a pan that starts only sideways, so a drag up or down from a bubble or a waveform is
the list's; a drag to the right still answers, and a drag along the waveform still moves the playhead.

The user can delete their own message while the conversation is not closed: "Sil" in the long-press menu, after a
question. It goes for everyone and shows as "Bu mesaj silindi" in a muted bubble, its time kept; a message not sent
yet only leaves the queue. If the conversation was closed meanwhile, the message stays and the app says so. A message
an operator deletes in Clomni shows the same, and a quote of a deleted message reads "Mesaj silinib". A deleted
message has no menu.

With `home.tab_bar` on in Clomni, tabs under the list screens: Home, the conversations with the unread count, the
news while there is some, the FAQ while it is on and has a question; a conversation, a news item and an answer hide
them. Without it nothing changes. Home's news card shows `home.news_on_home` items (two by default) and "Hamısı" when
there are more, to the news tab or the news list. The FAQ: Home's card with the first three questions, the list with
a search on the device, each answer on the news item's screen; opening one is reported as `faq_opened`.

A bot (a flow, Clomni AI, an AgentBot) shows by the name and picture the server sends with its message, else the
bot's name and picture from Clomni's appearance settings, else the brand's name and logo. 1.0.6 put the brand over
every bot message. The same in the conversation, in quotes, while it types, on Home's last message and in the
conversations' list. Operators and the user show as before.

The unread count on the conversations' tab is 16 pt high, ringed in the bar's colour, at the icon's top right corner,
and stays inside its tab; "99+" over 99. VoiceOver reads the tab with the count ("Söhbətlər, 7 oxunmamış").

The tabs keep their lists while the messenger is open: back on a tab, its list is there at once, scrolled where it was
left. Before, Home was made again each time and the sheet was blank white for a moment. Tabs cross-fade over 200 ms;
a conversation, a news item and an answer still open with the system's push. A list with nothing to show yet has the
spinner in the brand's colour in the middle (after 150 ms rather than 300, so a quick load shows none), and its
content fades in. With Reduce Motion the tabs and the content that comes change at once.

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
short message was refused with "hold to record"). The audio session starts off the main thread and stays up between
messages recorded one after another.

## 1.0.2

Voice messages, as in WhatsApp: hold the microphone to record, slide left to cancel, slide up to lock, listen
before sending; voice bubbles with a filling waveform and 1×, 1.5×, 2× speed. The microphone sits to the right of the
field and turns into send once there is text; the emoji button is gone (the keyboard has emoji). Messages written
offline wait with their clock and go as soon as the network is back. Bare domains such as clomni.ai are links. The
joined line stands before the operator's first message; next to the user's own last message, the company's face. A
flow whose choice leads nowhere gives the composer back. The kept user is greeted by name on the next launch; the
messenger speaks one language online and offline; debug logs reach the system log. The composer stands on the keyboard with no band under it; the launcher shows after a late initialize; a
picked file brings the end of the conversation into sight. Recording needs `NSMicrophoneUsageDescription` in the app's
Info.plist (without it the microphone is not shown); the camera, `NSCameraUsageDescription`.

## 1.0.0

The first release: the Clomni Messenger in the app's own screens (SwiftUI, iOS 15+), with users and identity
verification, the flows' buttons, attachments, ratings, push replies, the unread count and events. The look and the
texts come from the panel. System frameworks only, with a privacy manifest. Distributed through Swift Package Manager
(this repository, tag `1.0.0`); it is not on CocoaPods trunk.
