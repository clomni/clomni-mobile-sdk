# Integrating the Clomni Messenger on Android

Draft for the customer documentation (CM-110). Every Kotlin and Java block below is cut from the sample app
(`android/sample`), which CI compiles; the comment above each block names the file and lines, and `DocsTest` fails
when they no longer match. Push notifications have their own page: [push.md](push.md).

## 1. The keys

In Clomni: Channels → Add channel → Mobile app. The channel gives an **App ID**, an **Android API key** (and one for
iOS), and an **Identity Secret**, which stays on the app's server.

## 2. The dependency

```kts
// build.gradle.kts of the app
dependencies {
    implementation("ai.clomni:messenger:1.0.0")
}
```

Android 6.0 (API 23) or newer. The SDK adds nothing to the app's screens and asks for no permission itself.

## 3. Initialize, once

In the app's `Application` (named in the manifest with `android:name`), so that a notification that starts the app
finds the SDK ready:

<!-- sample: kotlin/ai/clomni/messenger/sample/SampleApp.kt#L7-L16 -->
```kotlin
class SampleApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Once, at start: a notification can start the app, and the messenger it opens needs the SDK ready.
        // App ID and the Android API key: Clomni panel → Channels → Mobile app.
        Clomni.initialize(this, appId = BuildConfig.CLOMNI_APP_ID, apiKey = BuildConfig.CLOMNI_API_KEY)
        // Integration mistakes (a wrong key or user_hash) and more show in logcat under the tag "Clomni".
        if (BuildConfig.DEBUG) Clomni.setLogLevel(ClomniLogLevel.DEBUG)
    }
}
```

Every method of `Clomni` may be called from any thread; listeners and callbacks are called on the main thread.

## 4. Log the user in, and out

Without a login the messenger opens for an anonymous visitor, kept on the device. When the app's user logs in, hand
Clomni the user and a hash from the app's server; the visitor's conversations move to the user:

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L66-L72 -->
```kotlin
private fun logIn() {
    // After the app's own login: its user, and the hash its server computed (DemoServer stands in for it).
    val userId = "12345"
    val user = ClomniUser(userId = userId, email = "aysel@example.com", name = "Aysel Məmmədova")
    Clomni.loginUser(user, userHash = DemoServer.userHash(userId))
    findViewById<TextView>(R.id.user).text = user.name
}
```

The hash is hex(HMAC-SHA256(identity_secret, user_id)), made on the server, never in the app:

```js
// Node
crypto.createHmac('sha256', secret).update(String(user.id)).digest('hex')
```

```php
// PHP
hash_hmac('sha256', (string)$user->id, $secret)
```

```python
# Python
hmac.new(secret.encode(), str(user.id).encode(), hashlib.sha256).hexdigest()
```

A wrong hash is logged as `user_hash səhvdir. identity_secret və user_id-ni yoxlayın`.

With the app's own logout:

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L74-L78 -->
```kotlin
private fun logOut() {
    // With the app's own logout: the next user must not see this one's conversations.
    Clomni.logout()
    findViewById<TextView>(R.id.user).text = ""
}
```

## 5. The app's own button

The messenger opens only when the app asks. Put it behind the app's own "Support" row, with the unread count next to
it:

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L32-L33 -->
```kotlin
// The app's own button opens the messenger; the source is stored with a conversation started there.
findViewById<View>(R.id.support).setOnClickListener { Clomni.present(source = "profile_support") }
```

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L20-L24 -->
```kotlin
// The unread count on the app's own "Dəstək" row.
private val unread = UnreadCountListener { count ->
    supportBadge.visibility = if (count > 0) View.VISIBLE else View.GONE
    supportBadge.text = count.toString()
}
```

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L56-L64 -->
```kotlin
override fun onStart() {
    super.onStart()
    Clomni.addUnreadCountListener(unread)
}

override fun onStop() {
    Clomni.removeUnreadCountListener(unread)
    super.onStop()
}
```

`presentNewConversation()` goes straight into a new conversation, `presentConversation(id)` into one the app knows
(`onConversationStarted` gives the id), and `dismiss()` closes the messenger from code.

## 6. A conversation about something

A button on a screen of the app can start the flow bound to an event, with what it is about:

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L35-L38 -->
```kotlin
// A contextual button: the conversation starts with the ride it is about.
findViewById<View>(R.id.report_problem).setOnClickListener {
    Clomni.startFlow("ride_problem", mapOf("ride_id" to "R-1923"), openMessenger = true, source = "ride_screen")
}
```

The flow's texts can use the data as `{{data.ride_id}}`. For an event the user did not tap (a failed payment), leave
`openMessenger` false: the user learns of the conversation from a push or the unread count.

## 7. The floating button (optional)

Off by default; the Clomni panel can turn it on too, and the app's choice wins. `setBottomPadding(dp)` lifts it
above a bottom navigation:

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L40-L41 -->
```kotlin
// The floating button is off unless the app (or the Clomni panel) turns it on.
findViewById<Switch>(R.id.launcher).setOnCheckedChangeListener { _, on -> Clomni.setLauncherVisible(on) }
```

Sounds: a short one for a message received while a conversation is open and one sent, muted by the phone's silent
mode and never pausing music. The panel can turn them off; `Clomni.setSoundsEnabled(false)` turns them off whatever
it says.

## 8. Events

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L47-L48 -->
```kotlin
Clomni.onConversationStarted { id -> note("conversation $id started") }
Clomni.onMessengerClosed { note("messenger closed") }
```

Also `onMessengerOpened`, `onUnreadCountChanged` and `onFlowCompleted`; one listener each, `null` removes it.

## 9. Push notifications

See [push.md](push.md): the app's `FirebaseMessagingService` hands Clomni the token and the messages. On Android 13+
the app asks for the permission:

<!-- sample: kotlin/ai/clomni/messenger/sample/MainActivity.kt#L50-L53 -->
```kotlin
// Android 13+: Clomni's notifications need the user's permission, which the app asks for.
if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
}
```

## 10. Java

Every call works from Java as well; the sample compiles one of each:

<!-- sample: java/ai/clomni/messenger/sample/JavaUsage.java#L24-L26 -->
```java
Clomni.initialize(context, "app_demo", "android_sdk-demo");
Clomni.setLogLevel(ClomniLogLevel.DEBUG);
Clomni.loginUser(new ClomniUser("12345", "aysel@example.com"), "hash from the app's server");
```

## 11. Look, font and logs

The messenger's colours, logo, header, Home cards and texts come from the panel (the inbox's "Görünüş" tab) and
change without an app update; a published change fades in on the open screen. To put the app's own look over the
panel's, `Clomni.setTheme(primaryColor = "#0A66C2", mode = ClomniThemeMode.DARK)`: the other brand colours are
derived from the colour by the panel's rules, the mode is `LIGHT`, `DARK` or `SYSTEM`, and each call replaces the
last; a value left out (null) stays the panel's. Its `typeface`, like `Clomni.setTypeface(typeface)`, puts the app's
font on every text of the messenger (it still follows the user's font size).

`Clomni.setLogLevel(ClomniLogLevel.DEBUG)` while developing; integration mistakes are logged as errors under the tag
`Clomni`.
