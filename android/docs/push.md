# Push notifications on Android

Operators' replies reach a closed app as Firebase Cloud Messaging data messages. The SDK has no Firebase
dependency: the app keeps its own `firebase-messaging` and hands Clomni the token and the messages. Its own pushes
stay its own.

## 1. Firebase in the Clomni panel

Upload the Firebase project's service account JSON in the App SDK inbox's settings (Mobil tətbiq → Push). The
server sends Clomni pushes with it.

## 2. The app's messaging service

```kotlin
// build.gradle.kts of the app
dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-messaging")
}
```

```kotlin
class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
        // the app's own server, if it has pushes of its own
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (ClomniPush.handle(this, message.data)) return
        // the app's own push
    }
}
```

```xml
<!-- AndroidManifest.xml of the app -->
<service android:name=".AppMessagingService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

FCM calls `onNewToken` only when the token changes. Hand the current one over at start as well; the SDK sends it to
the server only when the server does not have it for the logged-in user:

```kotlin
FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
```

`Clomni.initialize` must run in `Application.onCreate`: a notification can start the app's process, and the
messenger opened from it needs the SDK ready.

## 3. Permission (Android 13+)

Notifications need `POST_NOTIFICATIONS`, which the app declares and asks for at a moment that makes sense to its
users (the SDK never asks):

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

```kotlin
if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
```

Without it the SDK still keeps the unread count current; nothing is shown.

## 4. What the user sees

- One notification per conversation: the operator and the brand as the title ("Leyla · Apar"), the message (at most
  180 characters), the operator's photo. A newer message of the same conversation replaces it.
- Channel `clomni_messages` (`ClomniPush.CHANNEL_ID`), named "Dəstək mesajları" in the messenger's language, made the
  first time a notification is shown, high importance.
- A tap opens the app's start screen with the messenger on that conversation over it; the conversation is marked
  as opened from a push. A running app comes to the front as it was.
- While the messenger is open, on any screen, Clomni's notifications are not shown: the messenger shows the news
  itself. The unread count still reaches `Clomni.addUnreadCountListener`.
- The small icon is the app's own; Android draws it as a silhouette, so set a white one if the app icon is not:

```kotlin
Clomni.setNotificationIcon(R.drawable.ic_notification)
```

## 5. Trying it without a server

`ClomniPush.handle` takes any map, so a push can be shown from a button (the sample does this):

```kotlin
ClomniPush.handle(context, mapOf(
    "clomni" to "1", "type" to "message", "conversation_id" to "conv_5521",
    "title" to "Leyla · Apar", "body" to "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
    "unread_total" to "1",
))
```

From Firebase's console or API, send a **data** message (no `notification` block) with the same keys, priority
high.
