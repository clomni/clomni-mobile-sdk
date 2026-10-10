# Unity

The Unity package is a C# bridge to the native Android and iOS SDKs. The screens are the native ones. In the Editor
and on other platforms every call does nothing, and the first call says so once in the log.

## Requirements

- Unity 2021.3 or newer. Unity 6 (6000.x) works too.
- Android: Minimum API Level 23, compileSdk 35 or newer.
- iOS: Target minimum iOS Version 15.0, Xcode 15 or newer.
- [External Dependency Manager for Unity](https://github.com/googlesamples/unity-jar-resolver) (EDM4U). It brings the
  native SDKs: `ai.clomni:messenger:1.0.1` through Gradle and the `ClomniMessenger` pod through CocoaPods.
- The App ID and both API keys (`android_…`, `ios_…`) from **Installation** in the inbox's settings column.

## Install

1. Install EDM4U.
2. **Window → Package Manager → + → Add package from git URL**, and enter:

   ```
   https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1
   ```

   > **Path:** `Window → Package Manager → + → Add package from git URL → Add`
   >
   > In Unity 6 the menu item is **Install package from git URL** and the button is **Install**.
   >
   > Docs: [docs.unity3d.com/Manual/upm-ui-giturl.html](https://docs.unity3d.com/Manual/upm-ui-giturl.html) (Unity 6), [docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html](https://docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html) (2022.3)

3. **Android**: Project Settings → Player → Android → Minimum API Level 23 or higher. In EDM4U, Android Resolver →
   Settings: turn on "Use Gradle" and "Patch mainTemplate.gradle" (EDM4U 1.2.183 or newer).
4. **iOS**: Project Settings → Player → iOS → Target minimum iOS Version **15.0**. After building, open the
   `.xcworkspace`, not the `.xcodeproj`. If Xcode asks for a Swift version, set `SWIFT_VERSION = 5.0` on the
   `UnityFramework` target.

   EDM4U writes `pod 'ClomniMessenger', '1.0.0'` into the Podfile of the iOS build, and that form looks for the pod on
   CocoaPods trunk, where the SDK is not published. After each iOS build, change that line in the build folder's
   `Podfile` and run `pod install` there:

   ```ruby
   pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
   ```

To try it quickly: Package Manager → Clomni Messenger → Samples → **Basic** → Import. Add `ClomniBasicSample` to an
empty GameObject, fill in the App ID and keys in the Inspector and build to a device.

On iOS, add the permission texts for photos, the camera and the microphone to the app's `Info.plist`: [iOS →
Info.plist](04-ios.md#infoplist). On Android, voice messages (from SDK 1.0.2) need `RECORD_AUDIO` declared in the app's
manifest: [Android → Requirements](03-android.md#requirements).

## Initialize

As early as possible, once:

```csharp
using ClomniMessenger;
using UnityEngine;

public static class ClomniSetup
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    private static void Initialize()
    {
        var apiKey = Application.platform == RuntimePlatform.IPhonePlayer ? "ios_…" : "android_…";
        Clomni.Initialize("app_…", apiKey);
        if (Debug.isDebugBuild) Clomni.SetLogLevel(ClomniLogLevel.Debug);
    }
}
```

Call `Clomni` from Unity's main thread. Events arrive there too.

## The user

```csharp
Clomni.LoginUser(new ClomniUser { UserId = "12345", Email = "aysel@example.com", Name = "Aysel Məmmədova" },
    hashFromYourServer);
Clomni.UpdateUser(language: "az", customAttributes: new Dictionary<string, object> { ["plan"] = "premium" });

// With your game's own logout:
Clomni.Logout();
```

The hash comes from your game's server ([Identifying users](02-identity.md)). Never put the Identity Secret into the
game: not in C# code, not in assets, not in PlayerPrefs.

Call `Clomni.LoginUser` on every app start while the user is signed in, as if they had just signed in. For the same user
the SDK reuses its stored session.

## Open the Messenger

```csharp
using ClomniMessenger;
using UnityEngine;
using UnityEngine.UI;

public sealed class SupportButton : MonoBehaviour
{
    [SerializeField] private Button button;
    [SerializeField] private Text badge;

    private void OnEnable()
    {
        button.onClick.AddListener(Open);
        Clomni.UnreadCountChanged += ShowUnread;
    }

    private void OnDisable()
    {
        button.onClick.RemoveListener(Open);
        Clomni.UnreadCountChanged -= ShowUnread;
    }

    private void Open() => Clomni.Present("settings_support");

    private void ShowUnread(int count) => badge.text = count > 0 ? count.ToString() : "";
}
```

| Call | What it does |
|---|---|
| `Clomni.Present(source)` | Opens Home |
| `Clomni.PresentNewConversation(source)` | Opens a new conversation straight away |
| `Clomni.PresentConversation(id)` | Opens a known conversation; the ID comes from `ConversationStarted` |
| `Clomni.Dismiss()` | Closes the Messenger from code |
| `Clomni.SetLauncherVisible(true)`, `Clomni.SetBottomPadding(72)` | The optional floating button |

## Flows, events and links

```csharp
Clomni.StartFlow("ride_problem", new Dictionary<string, object> { ["ride_id"] = "R-1923" },
    openMessenger: true, source: "ride_screen");

Clomni.MessengerOpened += source => Debug.Log($"opened from {source}");
Clomni.MessengerClosed += () => Debug.Log("closed");
Clomni.ConversationStarted += id => Debug.Log($"conversation {id}");
Clomni.FlowCompleted += flowId => Debug.Log($"flow {flowId}");

// A news item's button. With a listener the game opens the link; without one the system does.
Clomni.OnLink += Application.OpenURL;
```

Language, sounds and look:

```csharp
Clomni.SetLanguage("en");            // "az", "en", "ru"; null follows the phone
Clomni.SetSoundsEnabled(false);
Clomni.SetTheme(primaryColor: "#0A66C2", mode: ClomniThemeMode.Dark);
```

**The event name is not the flow's name.** Pass `Clomni.StartFlow` the name on the flow's "Event: …" line in the panel's
Flows section. The flow must use the "App event" trigger: a flow with the "When a conversation starts" trigger does not
start with `Clomni.StartFlow`.

## Push notifications

Upload the keys to the panel first ([Push keys](08-push-keys.md)).

### Android

Use the Firebase Unity SDK (Firebase Messaging) and add your `google-services.json` to `Assets/` as Firebase
describes. The package's **Push (Firebase)** sample hands the token and the messages to Clomni:

```csharp
using ClomniMessenger;
using Firebase.Messaging;
using UnityEngine;

public sealed class ClomniFirebaseBridge : MonoBehaviour
{
    private void Start()
    {
        FirebaseMessaging.TokenReceived += OnTokenReceived;
        FirebaseMessaging.MessageReceived += OnMessageReceived;
    }

    private void OnDestroy()
    {
        FirebaseMessaging.TokenReceived -= OnTokenReceived;
        FirebaseMessaging.MessageReceived -= OnMessageReceived;
    }

    private void OnTokenReceived(object sender, TokenReceivedEventArgs e)
    {
        if (Application.platform == RuntimePlatform.Android) Clomni.SetDeviceToken(e.Token);
    }

    private void OnMessageReceived(object sender, MessageReceivedEventArgs e)
    {
        if (Application.platform != RuntimePlatform.Android) return;
        if (Clomni.HandlePush(e.Message.Data)) return;
        // the game's own push
    }
}
```

- Android 13+: ask for the notification permission:
  `UnityEngine.Android.Permission.RequestUserPermission("android.permission.POST_NOTIFICATIONS")`.
- The notification icon is a drawable in an `.androidlib` folder, for example
  `Assets/Plugins/Android/ClomniRes.androidlib/res/drawable/ic_notification.png`, named with
  `Clomni.SetNotificationIcon("ic_notification")`.

Firebase Unity hands a message to C# only while the game runs. For notifications while the game is closed, the
message must reach the SDK in Java before Unity starts: a service of your own, derived from Firebase's
`com.google.firebase.messaging.cpp.ListenerService`, calls `ClomniPush.handle` first. See the
[Android chapter](03-android.md#2-hand-over-the-token-and-the-messages) for what `ClomniPush.handle` does.

```java
// Assets/Plugins/Android/ClomniListenerService.java
package com.example.game;

import ai.clomni.messenger.ClomniPush;
import com.google.firebase.messaging.RemoteMessage;
import com.google.firebase.messaging.cpp.ListenerService;

public class ClomniListenerService extends ListenerService {
    @Override
    public void onMessageReceived(RemoteMessage message) {
        if (ClomniPush.handle(this, message.getData())) return;
        super.onMessageReceived(message);
    }
}
```

```xml
<!-- Assets/Plugins/Android/AndroidManifest.xml, inside <application>.
     xmlns:tools="http://schemas.android.com/tools" on the <manifest> element. -->
<service android:name="com.google.firebase.messaging.cpp.ListenerService" tools:node="remove" />
<service android:name="com.example.game.ClomniListenerService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

Check in the merged manifest of the Android build that only `ClomniListenerService` takes `MESSAGING_EVENT`.

### iOS

Clomni expects the APNs device token as hex, not the FCM token. Use Unity's Mobile Notifications package
(`com.unity.mobile.notifications`). In Project Settings → Mobile Notifications → iOS, turn on **Enable Push
Notifications**; it adds the capability to the Xcode project.

```csharp
using System.Collections;
using ClomniMessenger;
using UnityEngine;
#if UNITY_IOS
using Unity.Notifications.iOS;
#endif

public sealed class ClomniIosPush : MonoBehaviour
{
#if UNITY_IOS
    private string handled;

    private IEnumerator Start()
    {
        var options = AuthorizationOption.Alert | AuthorizationOption.Badge | AuthorizationOption.Sound;
        using (var request = new AuthorizationRequest(options, true))
        {
            while (!request.IsFinished) yield return null;
            if (request.Granted && !string.IsNullOrEmpty(request.DeviceToken))
            {
                Clomni.SetDeviceToken(request.DeviceToken);
            }
        }
    }

    // A tap on a notification brings the game to the front: a Clomni push opens its conversation.
    private void OnApplicationFocus(bool focused)
    {
        if (!focused) return;
        var tapped = iOSNotificationCenter.GetLastRespondedNotification();
        if (tapped == null || tapped.Identifier == handled) return;
        handled = tapped.Identifier;
        Clomni.HandlePush(tapped.UserInfo);
    }
#endif
}
```

`Clomni.ShouldShowForeground(data)` says whether a push that arrives while the game is open should be shown: false for
a Clomni push while the Messenger is open.

## Problems

| Symptom | What to do |
|---|---|
| Nothing happens in the Editor | Expected. The SDK runs only in Android and iOS builds |
| The Android build cannot resolve `ai.clomni:messenger` | Run Assets → External Dependency Manager → Android Resolver → Force Resolve; check "Use Gradle" |
| `pod install` cannot find `ClomniMessenger` | Change the pod line in the build folder's `Podfile` to the `:git` form (Install, step 4) |
| Xcode cannot find the `ClomniMessenger` module | Open the `.xcworkspace`, not the `.xcodeproj` |
| Xcode asks for a Swift version | `SWIFT_VERSION = 5.0` on `UnityFramework` |
| Notifications on Android only while the game is open | The Java service above |

More in [Troubleshooting](09-troubleshooting.md).
