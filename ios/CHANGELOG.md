# ClomniMessenger for iOS — changelog

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
