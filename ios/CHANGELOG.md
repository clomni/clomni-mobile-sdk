# ClomniMessenger for iOS — changelog

## 1.0.0 (unreleased)

The first release.

- The messenger in the app's own screens: Home (greeting, recent conversation, new conversation, the brand's channels)
  and the conversation (text with limited Markdown, images, files, forms, the flows' buttons, system lines, typing,
  read status, offline outbox). SwiftUI, iOS 15+, light and dark, Dynamic Type up to accessibility3, VoiceOver.
- Opened only by the app: `Clomni.present(source:)`, `presentNewConversation`, `presentConversation`,
  `startFlow(_:data:openMessenger:source:)`; an optional launcher (`setLauncherVisible`, `setBottomPadding`).
- Users: `loginUser` with `userHash` (identity verification), `loginUnidentifiedUser`, `updateUser`, `logout`.
- Push: `setDeviceToken` (APNs environment from the app's signature), `isClomniPush`, `handlePush`,
  `shouldShowForeground`; an optional Notification Service Extension for the operator's photo
  (`ios/Examples/NotificationService`).
- The unread count (`addUnreadCountListener`, `onUnreadCountChanged`) and events (`onMessengerOpened`,
  `onMessengerClosed`, `onConversationStarted`, `onFlowCompleted`).
- `setTypeface` for the app's own font family, `setLogLevel`.
- The look and the texts come from the panel (config v2): the brand's colours as the server derived them, the header
  as gradient, solid colour or picture, the glow, the logo for dark mode, the bot's picture, Home's cards in the
  panel's order, up to five channels, "Powered by Clomni", light or dark mode, and the texts with `{name}` and
  `{first_name}`. A published change fades in on the open screen. `setTheme(primaryColor:typeface:mode:)` puts the
  app's own colour, font and mode over the panel's.
- Every method may be called from any thread; callbacks run on the main thread. `initialize` does no disk or keychain
  work on the main thread.
- System frameworks only. A privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no required-reason APIs.
