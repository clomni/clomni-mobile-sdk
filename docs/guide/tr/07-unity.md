# Unity

Unity paketi, yerel Android ve iOS SDK'larına giden bir C# köprüsüdür. Ekranlar yerel ekranlardır. Editor'de ve
diğer platformlarda her çağrı hiçbir şey yapmaz; ilk çağrı bunu logda bir kez belirtir.

## Gereksinimler

- Unity 2021.3 veya daha yenisi. Unity 6 (6000.x) da çalışır.
- Android: Minimum API Level 23, compileSdk 35 veya daha yenisi.
- iOS: Target minimum iOS Version 15.0, Xcode 15 veya daha yenisi.
- [External Dependency Manager for Unity](https://github.com/googlesamples/unity-jar-resolver) (EDM4U). Yerel
  SDK'ları getirir: Gradle üzerinden `ai.clomni:messenger:1.0.1` ve CocoaPods üzerinden `ClomniMessenger` pod'u.
- Gelen kutusunun ayarlar sütununda **Installation** bölümünden App ID ve her iki API anahtarı (`android_…`, `ios_…`).

## Kurulum

1. EDM4U'yu kurun.
2. **Window → Package Manager → + → Add package from git URL** yolunu açın ve şunu girin:

   ```
   https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1
   ```

   > **Yol:** `Window → Package Manager → + → Add package from git URL → Add`
   >
   > Unity 6'da menü öğesinin adı **Install package from git URL**, düğmenin adı ise **Install**'dur.
   >
   > Belgeler: [docs.unity3d.com/Manual/upm-ui-giturl.html](https://docs.unity3d.com/Manual/upm-ui-giturl.html) (Unity 6), [docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html](https://docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html) (2022.3)

3. **Android**: Project Settings → Player → Android → Minimum API Level 23 veya daha yüksek. EDM4U'da Android
   Resolver → Settings: "Use Gradle" ve "Patch mainTemplate.gradle" seçeneklerini açın (EDM4U 1.2.183 veya daha
   yenisi).
4. **iOS**: Project Settings → Player → iOS → Target minimum iOS Version **15.0**. Build'den sonra `.xcodeproj`'yi
   değil, `.xcworkspace`'i açın. Xcode bir Swift sürümü isterse `UnityFramework` target'ında `SWIFT_VERSION = 5.0`
   ayarlayın.

   EDM4U, iOS build'inin Podfile'ına `pod 'ClomniMessenger', '1.0.0'` yazar; bu biçim pod'u, SDK'nın yayınlanmadığı
   CocoaPods trunk'ta arar. Her iOS build'inden sonra build klasöründeki `Podfile`'da bu satırı değiştirin ve orada
   `pod install` çalıştırın:

   ```ruby
   pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
   ```

Hızlıca denemek için: Package Manager → Clomni Messenger → Samples → **Basic** → Import. `ClomniBasicSample`'ı boş
bir GameObject'e ekleyin, Inspector'da App ID'yi ve anahtarları doldurun ve bir cihaza build alın.

iOS'ta uygulamanın `Info.plist` dosyasına fotoğraf, kamera ve mikrofon için izin metinlerini ekleyin: [iOS →
Info.plist](04-ios.md#infoplist). Android'de sesli mesaj (SDK 1.0.2'den itibaren) için uygulamanın manifestinde
`RECORD_AUDIO` bildirilmelidir: [Android → Gereksinimler](03-android.md#gereksinimler).

## Başlatma

Mümkün olduğunca erken, bir kez:

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

`Clomni`'yi Unity'nin ana thread'inden çağırın. Olaylar da orada gelir.

## Kullanıcı

```csharp
Clomni.LoginUser(new ClomniUser { UserId = "12345", Email = "aysel@example.com", Name = "Aysel Məmmədova" },
    hashFromYourServer);
Clomni.UpdateUser(language: "az", customAttributes: new Dictionary<string, object> { ["plan"] = "premium" });

// Oyunun kendi oturum kapatma işlemiyle birlikte:
Clomni.Logout();
```

Hash, oyununuzun sunucusundan gelir ([Kullanıcıların tanınması](02-identity.md)). Identity Secret'ı asla oyuna
koymayın: ne C# koduna, ne asset'lere, ne de PlayerPrefs'e.

Kullanıcı oturum açmışsa, uygulama her açıldığında `Clomni.LoginUser`'ı yeni giriş yapmış gibi yeniden çağırın. Aynı
kullanıcı için SDK kayıtlı oturumunu kullanır.

## Messenger'ı açma

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

| Çağrı | Ne yapar |
|---|---|
| `Clomni.Present(source)` | Ana sayfayı açar |
| `Clomni.PresentNewConversation(source)` | Doğrudan yeni bir konuşma açar |
| `Clomni.PresentConversation(id)` | Bilinen bir konuşmayı açar; ID `ConversationStarted`'dan gelir |
| `Clomni.Dismiss()` | Messenger'ı koddan kapatır |
| `Clomni.SetLauncherVisible(true)`, `Clomni.SetBottomPadding(72)` | İsteğe bağlı yüzen düğme |

## Akışlar, olaylar ve bağlantılar

```csharp
Clomni.StartFlow("ride_problem", new Dictionary<string, object> { ["ride_id"] = "R-1923" },
    openMessenger: true, source: "ride_screen");

Clomni.MessengerOpened += source => Debug.Log($"opened from {source}");
Clomni.MessengerClosed += () => Debug.Log("closed");
Clomni.ConversationStarted += id => Debug.Log($"conversation {id}");
Clomni.FlowCompleted += flowId => Debug.Log($"flow {flowId}");

// Bir haberin düğmesi. Dinleyici varsa bağlantıyı oyun açar, yoksa sistem açar.
Clomni.OnLink += Application.OpenURL;
```

Dil, sesler ve görünüm:

```csharp
Clomni.SetLanguage("en");            // "az", "en", "ru"; null telefona uyar
Clomni.SetSoundsEnabled(false);
Clomni.SetTheme(primaryColor: "#0A66C2", mode: ClomniThemeMode.Dark);
```

**Olay adı akışın adı değildir.** `Clomni.StartFlow`'a paneldeki Flows bölümünde akışın altındaki "Event: …" satırındaki
adı verin. Akış "App event" tetikleyicisiyle kurulmalıdır: "When a conversation starts" tetikleyicili bir akış
`Clomni.StartFlow` ile başlamaz.

## Push bildirimleri

Önce anahtarları panele yükleyin ([Push anahtarları](08-push-keys.md)).

### Android

Firebase Unity SDK'yı (Firebase Messaging) kullanın ve `google-services.json` dosyanızı Firebase'in anlattığı gibi
`Assets/` klasörüne ekleyin. Paketin **Push (Firebase)** örneği token'ı ve mesajları Clomni'ye iletir:

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
        // oyunun kendi push'u
    }
}
```

- Android 13+: bildirim iznini isteyin:
  `UnityEngine.Android.Permission.RequestUserPermission("android.permission.POST_NOTIFICATIONS")`.
- Bildirim simgesi bir `.androidlib` klasöründeki drawable'dır, örneğin
  `Assets/Plugins/Android/ClomniRes.androidlib/res/drawable/ic_notification.png`; adı
  `Clomni.SetNotificationIcon("ic_notification")` ile verilir.

Firebase Unity bir mesajı C#'a yalnızca oyun çalışırken iletir. Oyun kapalıyken bildirim gösterebilmek için mesajın
Unity başlamadan önce Java tarafında SDK'ya ulaşması gerekir: Firebase'in
`com.google.firebase.messaging.cpp.ListenerService` sınıfından türetilmiş kendi servisiniz önce `ClomniPush.handle`
çağırır. `ClomniPush.handle`'ın ne yaptığı için
[Android bölümüne](03-android.md#2-tokenı-ve-mesajları-iletme) bakın.

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
<!-- Assets/Plugins/Android/AndroidManifest.xml, <application> içinde.
     <manifest> öğesinde xmlns:tools="http://schemas.android.com/tools". -->
<service android:name="com.google.firebase.messaging.cpp.ListenerService" tools:node="remove" />
<service android:name="com.example.game.ClomniListenerService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

Android build'inin birleştirilmiş manifest'inde `MESSAGING_EVENT`'i yalnızca `ClomniListenerService`'in aldığını
kontrol edin.

### iOS

Clomni, FCM token'ını değil, hex biçimindeki APNs cihaz token'ını bekler. Unity'nin Mobile Notifications paketini
(`com.unity.mobile.notifications`) kullanın. Project Settings → Mobile Notifications → iOS altında **Enable Push
Notifications**'ı açın; bu, capability'yi Xcode projesine ekler.

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

    // Bildirime dokunma oyunu öne getirir: Clomni push'u kendi konuşmasını açar.
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

`Clomni.ShouldShowForeground(data)`, oyun açıkken gelen bir push'un gösterilip gösterilmeyeceğini söyler: Messenger
açıkken bir Clomni push'u için false döner.

## Sorunlar

| Belirti | Ne yapmalı |
|---|---|
| Editor'de hiçbir şey olmuyor | Beklenen davranış. SDK yalnızca Android ve iOS build'lerinde çalışır |
| Android build'i `ai.clomni:messenger`'ı çözümleyemiyor | Assets → External Dependency Manager → Android Resolver → Force Resolve çalıştırın; "Use Gradle"ı kontrol edin |
| `pod install`, `ClomniMessenger`'ı bulamıyor | Build klasöründeki `Podfile`'da pod satırını `:git` biçimine çevirin (Kurulum, 4. adım) |
| Xcode `ClomniMessenger` modülünü bulamıyor | `.xcodeproj`'yi değil, `.xcworkspace`'i açın |
| Xcode bir Swift sürümü istiyor | `UnityFramework` üzerinde `SWIFT_VERSION = 5.0` |
| Android'de bildirimler yalnızca oyun açıkken geliyor | Yukarıdaki Java servisi |

Daha fazlası: [Sorun giderme](09-troubleshooting.md).
