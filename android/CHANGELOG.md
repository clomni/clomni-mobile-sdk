# ai.clomni:messenger (Android) changelog

## 1.0.1

The session carries the app's package name (`app_identifier`: the `applicationId`, with any `applicationIdSuffix`), so
an inbox that names an Android package accepts its keys only from that app, as iOS already did with the bundle ID.
When the two differ, the server refuses the key and the error in the log names the package name the app sent.

## 1.0.0

The first release: the Clomni Messenger in the app's own screens (Jetpack Compose, Android 6.0+), with users and
identity verification, the flows' buttons, attachments, ratings, push replies through the app's own Firebase, the
unread count and events. The look and the texts come from the panel. Depends only on OkHttp, kotlinx.serialization,
Coil and Jetpack Compose. Distributed on Maven Central as `ai.clomni:messenger`.
