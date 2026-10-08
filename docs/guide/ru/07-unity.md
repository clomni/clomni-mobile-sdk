# Unity

Пакет для Unity — это мост на C# к нативным SDK для Android и iOS. Экраны остаются нативными. В редакторе и на
других платформах вызовы ничего не делают, и первый вызов один раз сообщает об этом в логе.

## Требования

- Unity 2021.3 или новее. Unity 6 (6000.x) тоже поддерживается.
- Android: Minimum API Level 23, compileSdk 35 или новее.
- iOS: Target minimum iOS Version 15.0, Xcode 15 или новее.
- [External Dependency Manager for Unity](https://github.com/googlesamples/unity-jar-resolver) (EDM4U). Он подтягивает
  нативные SDK: `ai.clomni:messenger:1.0.0` через Gradle и pod `ClomniMessenger` через CocoaPods.
- App ID и оба API-ключа (`android_…`, `ios_…`) из раздела **Installation** в боковом меню панели.

## Установка

1. Установите EDM4U.
2. Откройте **Window → Package Manager → + → Add package from git URL** и введите:

   ```
   https://github.com/clomni/clomni-mobile-sdk.git?path=unity#1.0.0
   ```

   > **Путь:** `Window → Package Manager → + → Add package from git URL → Add`
   >
   > В Unity 6 пункт меню называется **Install package from git URL**, а кнопка — **Install**.
   >
   > Документация: [docs.unity3d.com/Manual/upm-ui-giturl.html](https://docs.unity3d.com/Manual/upm-ui-giturl.html) (Unity 6), [docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html](https://docs.unity3d.com/2022.3/Documentation/Manual/upm-ui-giturl.html) (2022.3)

3. **Android**: Project Settings → Player → Android → Minimum API Level 23 или выше. В EDM4U, Android Resolver →
   Settings: включите «Use Gradle» и «Patch mainTemplate.gradle» (EDM4U 1.2.183 или новее).
4. **iOS**: Project Settings → Player → iOS → Target minimum iOS Version **15.0**. После сборки открывайте
   `.xcworkspace`, а не `.xcodeproj`. Если Xcode просит указать версию Swift, задайте `SWIFT_VERSION = 5.0` для
   таргета `UnityFramework`.

   EDM4U записывает в Podfile iOS-сборки `pod 'ClomniMessenger', '1.0.0'`, а в такой форме pod ищется в CocoaPods
   trunk, где SDK не опубликован. После каждой сборки под iOS замените эту строку в `Podfile` папки сборки и
   выполните там `pod install`:

   ```ruby
   pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
   ```

Чтобы быстро попробовать: Package Manager → Clomni Messenger → Samples → **Basic** → Import. Добавьте
`ClomniBasicSample` на пустой GameObject, заполните App ID и ключи в Inspector и соберите проект на устройство.

## Инициализация

Как можно раньше, один раз:

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

Вызывайте `Clomni` из главного потока Unity. События тоже приходят туда.

## Пользователь

```csharp
Clomni.LoginUser(new ClomniUser { UserId = "12345", Email = "aysel@example.com", Name = "Aysel Məmmədova" },
    hashFromYourServer);
Clomni.UpdateUser(language: "az", customAttributes: new Dictionary<string, object> { ["plan"] = "premium" });

// Вместе с выходом из вашей игры:
Clomni.Logout();
```

Хеш приходит с сервера вашей игры ([Идентификация пользователей](02-identity.md)). Никогда не кладите Identity
Secret в игру: ни в код на C#, ни в ассеты, ни в PlayerPrefs.

## Открытие Messenger

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

| Вызов | Что делает |
|---|---|
| `Clomni.Present(source)` | Открывает главный экран |
| `Clomni.PresentNewConversation(source)` | Сразу открывает новый диалог |
| `Clomni.PresentConversation(id)` | Открывает известный диалог; ID приходит из `ConversationStarted` |
| `Clomni.Dismiss()` | Закрывает Messenger из кода |
| `Clomni.SetLauncherVisible(true)`, `Clomni.SetBottomPadding(72)` | Необязательная плавающая кнопка |

## Сценарии, события и ссылки

```csharp
Clomni.StartFlow("ride_problem", new Dictionary<string, object> { ["ride_id"] = "R-1923" },
    openMessenger: true, source: "ride_screen");

Clomni.MessengerOpened += source => Debug.Log($"opened from {source}");
Clomni.MessengerClosed += () => Debug.Log("closed");
Clomni.ConversationStarted += id => Debug.Log($"conversation {id}");
Clomni.FlowCompleted += flowId => Debug.Log($"flow {flowId}");

// Кнопка новости. Если есть слушатель, ссылку открывает игра; если нет — система.
Clomni.OnLink += Application.OpenURL;
```

Язык, звуки и оформление:

```csharp
Clomni.SetLanguage("en");            // "az", "en", "ru"; null — как на телефоне
Clomni.SetSoundsEnabled(false);
Clomni.SetTheme(primaryColor: "#0A66C2", mode: ClomniThemeMode.Dark);
```

## Push-уведомления

Сначала загрузите ключи в панель ([Ключи для push](08-push-keys.md)).

### Android

Используйте Firebase Unity SDK (Firebase Messaging) и добавьте `google-services.json` в `Assets/`, как описано у
Firebase. Пример **Push (Firebase)** из пакета передаёт токен и сообщения в Clomni:

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
        // собственный push игры
    }
}
```

- Android 13+: запросите разрешение на уведомления:
  `UnityEngine.Android.Permission.RequestUserPermission("android.permission.POST_NOTIFICATIONS")`.
- Иконка уведомления — drawable в папке `.androidlib`, например
  `Assets/Plugins/Android/ClomniRes.androidlib/res/drawable/ic_notification.png`; её имя передаётся через
  `Clomni.SetNotificationIcon("ic_notification")`.

Firebase Unity передаёт сообщение в C# только пока игра запущена. Чтобы уведомления показывались и при закрытой
игре, сообщение должно попасть в SDK на стороне Java ещё до запуска Unity: ваш собственный сервис, унаследованный от
`com.google.firebase.messaging.cpp.ListenerService` из Firebase, сначала вызывает `ClomniPush.handle`. Что делает
`ClomniPush.handle`, см. в [главе об Android](03-android.md#2-передача-токена-и-сообщений).

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
<!-- Assets/Plugins/Android/AndroidManifest.xml, внутри <application>.
     xmlns:tools="http://schemas.android.com/tools" в элементе <manifest>. -->
<service android:name="com.google.firebase.messaging.cpp.ListenerService" tools:node="remove" />
<service android:name="com.example.game.ClomniListenerService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

Проверьте в объединённом манифесте Android-сборки, что `MESSAGING_EVENT` получает только `ClomniListenerService`.

### iOS

Clomni ожидает APNs-токен устройства в виде hex, а не FCM-токен. Используйте пакет Unity Mobile Notifications
(`com.unity.mobile.notifications`). В Project Settings → Mobile Notifications → iOS включите **Enable Push
Notifications** — это добавит capability в проект Xcode.

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

    // Нажатие на уведомление выводит игру на передний план: push от Clomni открывает свой диалог.
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

`Clomni.ShouldShowForeground(data)` говорит, нужно ли показывать push, пришедший при открытой игре: для push от
Clomni при открытом Messenger возвращается false.

## Проблемы

| Симптом | Что делать |
|---|---|
| В редакторе ничего не происходит | Так и должно быть. SDK работает только в сборках под Android и iOS |
| Android-сборка не может разрешить `ai.clomni:messenger` | Выполните Assets → External Dependency Manager → Android Resolver → Force Resolve; проверьте «Use Gradle» |
| `pod install` не находит `ClomniMessenger` | Замените строку pod в `Podfile` папки сборки на форму с `:git` («Установка», шаг 4) |
| Xcode не находит модуль `ClomniMessenger` | Откройте `.xcworkspace`, а не `.xcodeproj` |
| Xcode просит указать версию Swift | `SWIFT_VERSION = 5.0` для `UnityFramework` |
| На Android уведомления приходят только при открытой игре | Нужен Java-сервис, описанный выше |

Подробнее — в главе [Решение проблем](09-troubleshooting.md).
