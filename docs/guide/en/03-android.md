# Android

## Requirements

- Android 6.0 (API 23) or newer.
- `compileSdk` 35 or newer.
- Kotlin 1.8 or newer. Java works too (see the end of this chapter).
- The App ID and the Android API key (`android_…`) from **Installation** in the inbox's settings column.

SDK 1.0.1 asks for no permission of its own except network access, and adds nothing to your screens. From 1.0.2 a
conversation can take a photo with the camera and send a voice message: the `CAMERA` and `RECORD_AUDIO` permissions and
the FileProvider for the camera are in the SDK's manifest, so the app adds nothing.

## Install

The package is on Maven Central. Most projects already list `mavenCentral()` in `settings.gradle.kts`.

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("ai.clomni:messenger:1.0.1")
}
```

## Initialize

Call `initialize` once, in your `Application` class. A notification can start the app's process, and the Messenger
it opens needs the SDK ready, so an `Activity` is too late.

```kotlin
// App.kt
import android.app.Application
import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniLogLevel

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Clomni.initialize(this, appId = "app_…", apiKey = "android_…")
        if (BuildConfig.DEBUG) Clomni.setLogLevel(ClomniLogLevel.DEBUG)
    }
}
```

```xml
<!-- AndroidManifest.xml -->
<application
    android:name=".App"
    ...>
```

`BuildConfig.DEBUG` needs `buildFeatures { buildConfig = true }` in `app/build.gradle.kts` on AGP 8 and newer.

Every method of `Clomni` may be called from any thread. Listeners are called on the main thread. A second
`initialize` is ignored.

## The user

Log the user in after your own login, with the hash from your server ([Identifying users](02-identity.md)):

```kotlin
val user = ClomniUser(userId = "12345", email = "aysel@example.com", name = "Aysel Məmmədova")
Clomni.loginUser(user, userHash = hashFromYourServer)

Clomni.updateUser(language = "az", customAttributes = mapOf("plan" to "premium"))

// With your app's own logout:
Clomni.logout()
```

Call `loginUser` on every app start while the user is signed in, as if they had just signed in. For the same user the
SDK reuses its stored session.

## Open the Messenger

From your own button. `source` says where in the app it was opened.

```kotlin
findViewById<View>(R.id.support).setOnClickListener {
    Clomni.present(source = "profile_support")
}
```

In Jetpack Compose:

```kotlin
Button(onClick = { Clomni.present(source = "profile_support") }) {
    Text("Support")
}
```

Other ways to open and close:

| Call | What it does |
|---|---|
| `Clomni.present(source)` | Opens Home |
| `Clomni.presentNewConversation(source)` | Opens a new conversation straight away |
| `Clomni.presentConversation(id)` | Opens a known conversation; the ID comes from `onConversationStarted` |
| `Clomni.dismiss()` | Closes the Messenger from code |

### Unread count

Show the number of unread replies next to your button. The listener hears the current count at once and then every
change.

```kotlin
class ProfileActivity : AppCompatActivity() {
    private val unread = UnreadCountListener { count ->
        supportBadge.isVisible = count > 0
        supportBadge.text = count.toString()
    }

    override fun onStart() {
        super.onStart()
        Clomni.addUnreadCountListener(unread)
    }

    override fun onStop() {
        Clomni.removeUnreadCountListener(unread)
        super.onStop()
    }
}
```

### Floating button (optional)

![The floating button over an app screen, with the unread count](../images/sdk-launcher.png)

The floating button is off by default. The panel can turn it on (Appearance → Theme); a value set in code wins.
`setBottomPadding` lifts it above a bottom navigation bar, in dp.

```kotlin
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Flows started by the app

A button on one of your screens can start a conversation about something, for example a problem with a ride. In the
panel, build a flow with the "App event" trigger and the event name `ride_problem`, and publish it. In the app:

```kotlin
Clomni.startFlow(
    "ride_problem",
    mapOf("ride_id" to "R-1923"),
    openMessenger = true,
    source = "ride_screen",
)
```

- The flow's texts can use the data as `{{data.ride_id}}`. The data must be JSON values: strings, numbers,
  booleans, lists and maps.
- Without a published flow bound to the event, nothing happens.
- For an event the user did not tap (a failed payment, for example), keep `openMessenger = false`. The user learns of
  the conversation from a push or the unread count.

**The event name is not the flow's name.** Pass `startFlow` the name on the flow's "Event: …" line in the panel's Flows
section. The flow must use the "App event" trigger: a flow with the "When a conversation starts" trigger does not start
with `startFlow`.

## Events

```kotlin
Clomni.onMessengerOpened { source -> Log.d("App", "opened from $source") }
Clomni.onMessengerClosed { Log.d("App", "closed") }
Clomni.onConversationStarted { id -> Log.d("App", "conversation $id") }
Clomni.onFlowCompleted { flowId -> Log.d("App", "flow $flowId completed") }
Clomni.onUnreadCountChanged { count -> Log.d("App", "unread $count") }
```

Each event has one listener. Setting a new one replaces the old one; `null` removes it.

## Links

A news item's button can carry a web address or your app's deep link. With `onLink` the link comes to your app
first. Return `true` when the app opened it; `false`, or no listener, lets the system open it.

```kotlin
Clomni.onLink { url ->
    if (url.startsWith("example://")) {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(packageName))
        true
    } else {
        false
    }
}
```

## Language, sounds and look

```kotlin
Clomni.setLanguage("en")          // az, en or ru; null follows the phone
Clomni.setSoundsEnabled(false)    // off whatever the panel says
```

- **Language.** The Messenger speaks the languages turned on in the panel (Appearance → Languages). `setLanguage`
  picks one of them. `null`, or a language that is off, follows the phone's language, then the panel's main
  language.
- **Sounds.** A short sound for a message sent or received while a conversation is open. It follows the phone's
  silent mode.

Colours, logo and texts come from the panel. To put your app's own colour, font and mode over them, use `setTheme`.
The colour is `#RRGGBB`; the other brand colours are derived from it. Each call replaces the previous one, and a value
left out stays the panel's.

```kotlin
Clomni.setTheme(
    primaryColor = "#0A66C2",
    typeface = ResourcesCompat.getFont(context, R.font.montserrat),
    mode = ClomniThemeMode.DARK,      // LIGHT, DARK or SYSTEM
)
```

![The panel's look, light and dark, and the app's own colour](../images/sdk-theme.png)

For the font alone: `Clomni.setTypeface(typeface)`. The font still follows the user's text size setting.

## Push notifications

Agents' replies reach a closed app as Firebase Cloud Messaging (FCM) data messages. The SDK has no Firebase
dependency: your app keeps its own `firebase-messaging` and hands Clomni the token and the messages. Your own pushes
stay yours.

You need:

1. A Firebase project with your Android app added, and its `google-services.json` in the app.
2. The project's service account JSON uploaded to the panel ([Push keys](08-push-keys.md)).
3. The code below.

### 1. Firebase in the app

In the [Firebase console](https://console.firebase.google.com), open your project (or create one) and add an
Android app with your package name.

> **Path:** `Firebase console → your project → Project Overview → + Add app → Android`
>
> Enter your app's package name in **Android package name** (for example `com.example.app`) and press **Register app**.
>
> Docs: [firebase.google.com/docs/android/setup](https://firebase.google.com/docs/android/setup#register-app)

Download `google-services.json` and put it into the `app/` folder of your project.

> **Path:** `Firebase: Download google-services.json → Android Studio: <project>/app/google-services.json`
>
> To see the file in Android Studio, choose the **Project** view from the menu at the top of the Project window.
>
> Docs: [firebase.google.com/docs/android/setup](https://firebase.google.com/docs/android/setup#add-config-file), [developer.android.com/studio/projects](https://developer.android.com/studio/projects#ProjectView)

```kotlin
// settings.gradle.kts (or the root build.gradle.kts)
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

```kotlin
// app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

dependencies {
    implementation("ai.clomni:messenger:1.0.1")
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-messaging")
}
```

> `google-services.json` is for the app. The panel needs a different file, the **service account JSON**. See
> [Push keys](08-push-keys.md).

### 2. Hand over the token and the messages

```kotlin
// AppMessagingService.kt
import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniPush
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
        // and to your own server, if the app has pushes of its own
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (ClomniPush.handle(this, message.data)) return
        // the app's own push
    }
}
```

```xml
<!-- AndroidManifest.xml, inside <application> -->
<service
    android:name=".AppMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

FCM calls `onNewToken` only when the token changes. Hand the current token over at every start too, in
`Application.onCreate` after `initialize`:

```kotlin
FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
```

The token is registered for whoever is logged in, and again after the next `loginUser` or `logout`.
`ClomniPush.isClomniPush(data)` tells a Clomni push from your own without handling it.

### 3. The permission on Android 13 and newer

Notifications need the `POST_NOTIFICATIONS` permission. The SDK never asks for it. Declare it and ask at a moment
that makes sense to your users, for example after their first message:

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

```kotlin
class MainActivity : AppCompatActivity() {
    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
```

Without the permission nothing is shown, but the unread count stays current.

### What the user sees

- One notification per conversation. The title is the agent and the brand ("Leyla · Example"), the text is the
  message (up to 180 characters), and the agent's photo is shown. A newer message of the same conversation replaces it.
- The notification channel is `clomni_messages` (`ClomniPush.CHANNEL_ID`), named "Support messages" in the
  Messenger's language, with high importance. It is created the first time a notification is shown. Users can turn
  it off in the system settings.
- A tap opens your app's start screen with the Messenger on that conversation over it.
- While the Messenger is open, Clomni notifications are not shown: the Messenger shows the message itself.

The small icon is your app's icon. Android draws it as a silhouette, so give the SDK a white one if your app icon is
not:

```kotlin
Clomni.setNotificationIcon(R.drawable.ic_notification)
```

### Test it

1. Run the app on a phone, allow notifications and open the Messenger once.
2. In the panel: **Push** in the settings column → **Test push** → choose the device → **Send**.

To see a Clomni notification without the server, hand `ClomniPush.handle` a map yourself:

```kotlin
ClomniPush.handle(context, mapOf(
    "clomni" to "1", "type" to "message", "conversation_id" to "conv_1",
    "title" to "Leyla · Example", "body" to "We have checked your ride.", "unread_total" to "1",
))
```

## Java

Every call works from Java:

```java
Clomni.initialize(context, "app_…", "android_…");
Clomni.loginUser(new ClomniUser("12345", "aysel@example.com"), hashFromYourServer);
Clomni.present("profile_support");
Clomni.onLink(url -> false);
```

## Problems

| Symptom | What to do |
|---|---|
| `call Clomni.initialize first` in logcat | Call `initialize` in `Application.onCreate`, and name the class in the manifest with `android:name` |
| `api_key səhvdir və ya bu platforma üçün deyil` | The key is wrong, revoked or the iOS one. Use the `android_…` key |
| No notification, logcat says `notification not shown (POST_NOTIFICATIONS?)` | Ask for `POST_NOTIFICATIONS` on Android 13+ |
| `push token not registered: …` | Check the `setDeviceToken` calls and the service account JSON in the panel |
| Notifications arrive but the icon is a grey square | Set a white silhouette icon with `setNotificationIcon` |
| The `onMessageReceived` of your service is never called | The service is missing from the manifest, or another `FirebaseMessagingService` in the app takes the messages. An app has only one: hand Clomni's messages over in that one |

More in [Troubleshooting](09-troubleshooting.md). Logs are in logcat under the tag `Clomni`.
