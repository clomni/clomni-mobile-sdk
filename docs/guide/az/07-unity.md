# Unity

Unity paketi native Android və iOS SDK-larına C# körpüsüdür. Ekranlar native ekranlardır. Editor-da və digər
platformalarda çağırışlar heç nə etmir, ilk çağırış bunu log-a bir dəfə yazır.

## Tələblər

- Unity 2021.3 və ya daha yeni. Unity 6 (6000.x) də işləyir.
- Android: Minimum API Level 23, compileSdk 35 və ya daha yeni.
- iOS: Target minimum iOS Version 15.0, Xcode 15 və ya daha yeni.
- [External Dependency Manager for Unity](https://github.com/googlesamples/unity-jar-resolver) (EDM4U). Native
  SDK-ları o gətirir: `ai.clomni:messenger:1.0.0`-i Gradle ilə, `ClomniMessenger` pod-unu CocoaPods ilə.
- Paneldə kanalın ayarlar sütununun **Quraşdırma** bölməsindən App ID və hər iki API açarı (`android_…`, `ios_…`).

## Quraşdırma

1. EDM4U-nu quraşdırın.
2. **Window → Package Manager → + → Add package from git URL** və bu ünvanı yazın:

   ```
   https://github.com/clomni/clomni-mobile-sdk.git?path=unity#1.0.0
   ```

   > **Yol:** `Window → Package Manager → + → Add package from git URL → Add`
   >
   > Unity 6-da menyu bəndi **Install package from git URL**, düymə isə **Install** adlanır.
   >
   > Sənəd: [docs.unity3d.com/Manual/upm-ui-giturl.html](https://docs.unity3d.com/Manual/upm-ui-giturl.html) (Unity 6), [docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html](https://docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html) (2022.3)

3. **Android**: Project Settings → Player → Android → Minimum API Level 23 və ya yuxarı. EDM4U-da Android Resolver →
   Settings: "Use Gradle" və "Patch mainTemplate.gradle" açıq olsun (EDM4U 1.2.183 və ya daha yeni).
4. **iOS**: Project Settings → Player → iOS → Target minimum iOS Version **15.0**. Build-dən sonra `.xcodeproj`-u
   yox, `.xcworkspace`-i açın. Xcode Swift versiyasını soruşsa, `UnityFramework` hədəfinə `SWIFT_VERSION = 5.0`
   yazın.

   EDM4U iOS build-inin Podfile-ına `pod 'ClomniMessenger', '1.0.0'` yazır. Bu forma pod-u CocoaPods trunk-da
   axtarır, SDK isə orada dərc olunmayıb. Hər iOS build-dən sonra build qovluğundakı `Podfile`-da həmin sətri
   dəyişin və orada `pod install` işlədin:

   ```ruby
   pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
   ```

Tez sınamaq üçün: Package Manager → Clomni Messenger → Samples → **Basic** → Import. Boş GameObject-ə
`ClomniBasicSample` əlavə edin, Inspector-da App ID və açarları yazın və cihaza build edin.

## Başlatma

Mümkün qədər tez, bir dəfə:

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

`Clomni`-ni Unity-nin əsas thread-indən çağırın. Hadisələr də orada gəlir.

## İstifadəçi

```csharp
Clomni.LoginUser(new ClomniUser { UserId = "12345", Email = "aysel@example.com", Name = "Aysel Məmmədova" },
    hashFromYourServer);
Clomni.UpdateUser(language: "az", customAttributes: new Dictionary<string, object> { ["plan"] = "premium" });

// Oyunun öz çıxışı ilə birlikdə:
Clomni.Logout();
```

Hash oyununuzun serverindən gəlir ([İstifadəçinin tanıdılması](02-identity.md)). Identity Secret-i heç vaxt oyuna
qoymayın: nə C# koduna, nə asset-lərə, nə də PlayerPrefs-ə.

## Messenger-i açmaq

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

| Çağırış | Nə edir |
|---|---|
| `Clomni.Present(source)` | Ana səhifəni açır |
| `Clomni.PresentNewConversation(source)` | Birbaşa yeni söhbət açır |
| `Clomni.PresentConversation(id)` | Məlum söhbəti açır; ID `ConversationStarted`-dən gəlir |
| `Clomni.Dismiss()` | Messenger-i koddan bağlayır |
| `Clomni.SetLauncherVisible(true)`, `Clomni.SetBottomPadding(72)` | İstəyə bağlı üzən düymə |

## Flow-lar, hadisələr və linklər

```csharp
Clomni.StartFlow("ride_problem", new Dictionary<string, object> { ["ride_id"] = "R-1923" },
    openMessenger: true, source: "ride_screen");

Clomni.MessengerOpened += source => Debug.Log($"opened from {source}");
Clomni.MessengerClosed += () => Debug.Log("closed");
Clomni.ConversationStarted += id => Debug.Log($"conversation {id}");
Clomni.FlowCompleted += flowId => Debug.Log($"flow {flowId}");

// Xəbərin düyməsi. Dinləyici varsa linki oyun açır, yoxdursa sistem.
Clomni.OnLink += Application.OpenURL;
```

Dil, səslər və görünüş:

```csharp
Clomni.SetLanguage("en");            // "az", "en", "ru"; null telefonun dilinə uyğunlaşır
Clomni.SetSoundsEnabled(false);
Clomni.SetTheme(primaryColor: "#0A66C2", mode: ClomniThemeMode.Dark);
```

## Push bildirişləri

Əvvəlcə açarları panelə yükləyin ([Push açarları](08-push-keys.md)).

### Android

Firebase Unity SDK-nı (Firebase Messaging) işlədin və `google-services.json`-u Firebase-in dediyi kimi `Assets/`
qovluğuna qoyun. Paketin **Push (Firebase)** nümunəsi tokeni və mesajları Clomni-yə ötürür:

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
        // oyunun öz push-u
    }
}
```

- Android 13+: bildiriş icazəsini istəyin:
  `UnityEngine.Android.Permission.RequestUserPermission("android.permission.POST_NOTIFICATIONS")`.
- Bildiriş ikonu `.androidlib` qovluğundakı drawable-dır, məsələn
  `Assets/Plugins/Android/ClomniRes.androidlib/res/drawable/ic_notification.png`, adı
  `Clomni.SetNotificationIcon("ic_notification")` ilə verilir.

Firebase Unity mesajı C#-a yalnız oyun işləyəndə çatdırır. Oyun bağlı olanda da bildiriş görünsün deyə mesaj Unity
başlamazdan əvvəl Java-da SDK-ya çatmalıdır: Firebase-in `com.google.firebase.messaging.cpp.ListenerService`
sinfindən törəyən öz servisiniz əvvəlcə `ClomniPush.handle` çağırır. `ClomniPush.handle`-ın nə etdiyi
[Android bölməsində](03-android.md#2-token-və-mesajların-ötürülməsi) yazılıb.

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
<!-- Assets/Plugins/Android/AndroidManifest.xml, <application> içində.
     <manifest> elementində xmlns:tools="http://schemas.android.com/tools". -->
<service android:name="com.google.firebase.messaging.cpp.ListenerService" tools:node="remove" />
<service android:name="com.example.game.ClomniListenerService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

Android build-inin birləşmiş manifestində `MESSAGING_EVENT`-i yalnız `ClomniListenerService`-in qəbul etdiyini
yoxlayın.

### iOS

Clomni FCM tokenini yox, APNs cihaz tokenini hex kimi gözləyir. Unity-nin Mobile Notifications paketini
(`com.unity.mobile.notifications`) işlədin. Project Settings → Mobile Notifications → iOS bölməsində **Enable Push
Notifications**-ı yandırın: o, capability-ni Xcode layihəsinə əlavə edir.

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

    // Bildirişə toxunuş oyunu önə gətirir: Clomni push-u öz söhbətini açır.
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

`Clomni.ShouldShowForeground(data)` oyun açıq olanda gələn push-un göstərilib-göstərilməməli olduğunu deyir:
Messenger açıqdırsa, Clomni push-u üçün false.

## Problemlər

| Əlamət | Nə etməli |
|---|---|
| Editor-da heç nə baş vermir | Gözlənilən haldır. SDK yalnız Android və iOS build-lərində işləyir |
| Android build `ai.clomni:messenger`-i tapa bilmir | Assets → External Dependency Manager → Android Resolver → Force Resolve; "Use Gradle" açıq olsun |
| `pod install` `ClomniMessenger`-i tapa bilmir | Build qovluğundakı `Podfile`-da pod sətrini `:git` formasına dəyişin (Quraşdırma, 4-cü addım) |
| Xcode `ClomniMessenger` modulunu tapa bilmir | `.xcodeproj`-u yox, `.xcworkspace`-i açın |
| Xcode Swift versiyasını soruşur | `UnityFramework`-də `SWIFT_VERSION = 5.0` |
| Android-də bildirişlər yalnız oyun açıq olanda gəlir | Yuxarıdakı Java servisi |

Daha çoxu: [Problemlərin həlli](09-troubleshooting.md).
