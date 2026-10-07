# ClomniMessenger for iOS — changelog

## 1.0.0 (unreleased)

The first release.

- The messenger in the app's own screens: Home (greeting, recent conversation, new conversation, the brand's channels)
  and the conversation (text with limited Markdown, images, files, forms, the flows' buttons, system lines, typing,
  read status, offline outbox). SwiftUI, iOS 15+, light and dark, Dynamic Type up to accessibility3, VoiceOver.
- Ratings (CSAT): five faces or five stars, a comment when the panel asks for one, sent through the outbox like any
  message. Web addresses, emails and phone numbers written in a message are tappable; web addresses go to `onLink`.
- Opened only by the app: `Clomni.present(source:)`, `presentNewConversation`, `presentConversation`,
  `startFlow(_:data:openMessenger:source:)`; an optional launcher (`setLauncherVisible`, `setBottomPadding`).
- Users: `loginUser` with `userHash` (identity verification), `loginUnidentifiedUser`, `updateUser`, `logout`.
- Push: `setDeviceToken` (APNs environment from the app's signature), `isClomniPush`, `handlePush`,
  `shouldShowForeground`; an optional Notification Service Extension for the operator's photo
  (`ios/Examples/NotificationService`).
- The unread count (`addUnreadCountListener`, `onUnreadCountChanged`) and events (`onMessengerOpened`,
  `onMessengerClosed`, `onConversationStarted`, `onFlowCompleted`).
- `setTypeface` for the app's own font family, `setLogLevel`, `setSoundsEnabled` (the short message sounds; the panel's
  `sounds` turns them off too).
- `setLanguage`: the messenger speaks the languages turned on in the panel (Appearance, Languages): the app's choice
  when it is on, else the phone's, else the panel's main language; with one on, always that one.
- The look and the texts come from the panel (config v2): the brand's colours as the server derived them, the header
  as gradient, solid colour or picture, the glow, the logo for dark mode, the bot's picture, Home's cards in the
  panel's order, up to five channels, "Powered by Clomni", light or dark mode, and the texts with `{name}` and
  `{first_name}`. A published change fades in on the open screen. `setTheme(primaryColor:typeface:mode:)` puts the
  app's own colour, font and mode over the panel's.
- A new conversation is created on the server with the user's first message, not when it is opened; offline, the
  outbox creates it once and then sends.
- The messenger opens as a page sheet over the app (swipe down closes it), its screens in a navigation stack with
  the system's push and swipe back. Home has no tab bar: a "Mesajlar" card opens the conversations, the brand's
  colour fades into the page under the greeting, the panel's logo and greeting scales apply, and published news show
  as a card with their own screen. A news button's link goes to `Clomni.onLink`; without it the system opens it.
- The composer: the attach icon opens a sheet (photos and videos, the camera, files); a picked file waits above it
  until sent. During a flow step that takes only a button, the composer stays, greyed.
- Every method may be called from any thread; callbacks run on the main thread. `initialize` does no disk or keychain
  work on the main thread.
- System frameworks only. A privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no required-reason APIs.
