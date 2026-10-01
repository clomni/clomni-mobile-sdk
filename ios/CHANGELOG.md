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
- Every method may be called from any thread; callbacks run on the main thread. `initialize` does no disk or keychain
  work on the main thread.
- System frameworks only. A privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no required-reason APIs.
