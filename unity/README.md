# Clomni Messenger for Unity

[Azərbaycanca](#azərbaycanca) · [English](#english)

## Azərbaycanca

Clomni Messenger-i Unity oyununda və ya tətbiqində açır. İşi native Android (`ai.clomni:messenger`) və iOS
(`ClomniMessenger`) SDK-ları görür; bu paket onlara C# körpüsüdür. Editor-da və digər platformalarda çağırışlar heç
nə etmir, ilk çağırış bunu log-a bir dəfə yazır.

### Minimum versiyalar

Unity 2021.3, Android API 23 (compileSdk 34+), iOS 15 (Xcode 15+).

### Quraşdırma

1. [External Dependency Manager for Unity](https://github.com/googlesamples/unity-jar-resolver) (EDM4U) quraşdırın.
   Native SDK-ları o gətirir: Android-də Gradle ilə `ai.clomni:messenger:1.0.0`, iOS-da CocoaPods ilə
   `ClomniMessenger` 1.0.0 (`Editor/ClomniDependencies.xml`).
2. Window → Package Manager → **+** → Add package from git URL:

   ```
   https://github.com/rzayevkenann/clomni-mobile-sdk.git?path=unity#unity-1.0.0
   ```

> Native paketlər Maven Central-a və CocoaPods-a dərc olunandan sonra EDM4U onları tapacaq. O vaxta qədər Android
> və iOS build-ləri asılılığı həll edə bilmir.

### İstifadə

`Samples~/Basic/ClomniBasicSample.cs`-dən:

```csharp
using ClomniMessenger;

Clomni.Initialize(appId, apiKey);
Clomni.LoginUser(new ClomniUser { UserId = "demo-42", Email = "demo@example.com", Name = "Demo" }, userHash: null);
Clomni.Present("sample_button");
Clomni.StartFlow("ride_problem", new Dictionary<string, object> { ["ride_id"] = "R-1001" }, openMessenger: true,
    source: "sample_button");
Clomni.OnLink += Application.OpenURL;
Clomni.UnreadCountChanged += OnUnreadCountChanged;
```

Qalan çağırışlar: `LoginUnidentifiedUser`, `UpdateUser(name, language, customAttributes)`, `Logout`,
`PresentNewConversation`, `PresentConversation(id)`, `Dismiss`, `SetLanguage`, `SetSoundsEnabled`, `SetTheme`,
`SetTypeface`, `SetLauncherVisible`, `SetBottomPadding`, `SetLogLevel`, `SetDeviceToken`, `IsClomniPush`,
`HandlePush`, `ShouldShowForeground` (iOS), `SetNotificationIcon` (Android). Hadisələr: `UnreadCountChanged`,
`MessengerOpened`, `MessengerClosed`, `ConversationStarted`, `FlowCompleted`, `OnLink`. Hamısı Unity-nin əsas
thread-ində çağırılmalıdır, hadisələr də orada gəlir.

> **`userHash` oyunun öz serverində hesablanır**: hex(HMAC-SHA256(identity_secret, UserId)). `identity_secret`
> heç vaxt oyunun içinə (C# kodu, asset, PlayerPrefs) qoyulmur: APK və IPA-dan asanlıqla çıxarılır.

### Android

- `Initialize`-i mümkün qədər tez çağırın, məsələn
  `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]` ilə.
- Android 13+ bildirişləri üçün `POST_NOTIFICATIONS` icazəsini istəyin
  (`UnityEngine.Android.Permission.RequestUserPermission`).
- Bildiriş ikonu: drawable-ı `.androidlib` qovluğuna qoyun (`Assets/Plugins/Android/ClomniRes.androidlib/res/drawable/`)
  və `Clomni.SetNotificationIcon("ic_notification")`.

- **Unity 6 (6000.x).** Sınanmalı versiya 6000.3-dür. Unity 6-nın standart giriş nöqtəsi GameActivity-dir, paket onunla da
  işləyir: messenger öz ekranında açılır, oyunun activity-sinə ehtiyacı yoxdur. *Project Settings → Player → Android*:
  Minimum API Level 23 (Android 6.0) və ya yuxarı. External Dependency Manager-də *Android Resolver → Settings*:
  "Use Gradle" və "Patch mainTemplate.gradle" açıq olsun (EDM4U 1.2.183+).

### iOS

- Player Settings → Target minimum iOS Version: **15.0**.
- EDM4U Podfile-a `ClomniMessenger` pod-unu yazır; build-dən sonra `.xcworkspace`-i açın.
- `Plugins/iOS/ClomniUnityBridge.swift` və `ClomniUnityBridge.mm` Xcode layihəsində `UnityFramework` hədəfinə düşür.
  Swift faylı pod-u `import ClomniMessenger` ilə çağırır; `.mm` faylı ona `UnitySendMessage`-in ünvanını verir, ona görə
  bridging header lazım deyil. Xcode Swift versiyasını soruşsa, `UnityFramework` üçün `SWIFT_VERSION = 5.0` qoyun.

### Push

- **Android**: FCM token-i `Clomni.SetDeviceToken`-ə, data mesajını `Clomni.HandlePush`-a verin. Hazır nümunə:
  Package Manager → Clomni Messenger → Samples → **Push (Firebase)** (`ClomniFirebaseBridge`, Firebase Unity SDK
  lazımdır). Firebase Unity data mesajını C#-a yalnız oyun açıq olanda çatdırır. Oyun bağlı olanda da bildiriş
  görünsün deyə Firebase-in `com.google.firebase.messaging.cpp.ListenerService` sinfindən törəyən öz servisinizdə
  əvvəlcə `ClomniPush.handle(this, message.data)` çağırın (bax `android/docs/push.md`).
- **iOS**: Clomni APNs device token-ini hex kimi gözləyir, FCM token-ini yox. `com.unity.mobile.notifications`
  paketində: `new AuthorizationRequest(…, registerForRemoteNotifications: true)` → `request.DeviceToken` →
  `Clomni.SetDeviceToken`. Bildirişə toxunanda onun `UserInfo`-sunu `Clomni.HandlePush`-a verin.

### Nümunə

Package Manager → Clomni Messenger → Samples → **Basic** → Import. Səhnədə boş GameObject yaradın, Add Component →
`ClomniBasicSample`, Inspector-da App ID və API açarlarını yazın, cihaza build edin. Ekranda üç düymə olur: Aç,
Login, Hadisə göndər.

## English

The Clomni Messenger inside a Unity game or app. The native Android (`ai.clomni:messenger`) and iOS
(`ClomniMessenger`) SDKs do the work; this package is the C# bridge to them. In the Editor and on other platforms
every call does nothing, and the first one says so once in the log.

**Minimum versions**: Unity 2021.3, Android API 23 (compileSdk 34+), iOS 15 (Xcode 15+).

**Installation**: install the [External Dependency Manager for Unity](https://github.com/googlesamples/unity-jar-resolver)
(EDM4U), which brings the native SDKs (`Editor/ClomniDependencies.xml`), then Package Manager → **+** → Add package
from git URL: `https://github.com/rzayevkenann/clomni-mobile-sdk.git?path=unity#unity-1.0.0`. EDM4U finds
`ai.clomni:messenger:1.0.0` and the `ClomniMessenger` 1.0.0 pod only once they are published to Maven Central and
CocoaPods; until then Android and iOS builds cannot resolve them.

**Usage**: as in the code above, taken from `Samples~/Basic/ClomniBasicSample.cs`. Call from Unity's main thread; events arrive there.

> **`userHash` is computed on the game's own server**: hex(HMAC-SHA256(identity_secret, UserId)). Never put
> `identity_secret` into the game (C# code, assets, PlayerPrefs): it is easily pulled out of an APK or IPA.

**Android**: call `Initialize` as early as possible (`RuntimeInitializeLoadType.BeforeSceneLoad`); ask for
`POST_NOTIFICATIONS` on Android 13+; the notification icon is a drawable in an `.androidlib` folder, named with
`SetNotificationIcon`.

**Unity 6 (6000.x)**: the version to test is 6000.3. Unity 6 starts with GameActivity by default; the package works
with it, as the messenger opens on its own screen and needs nothing from the game's activity. *Player → Android*: Minimum
API Level 23 or higher. External Dependency Manager, *Android Resolver → Settings*: "Use Gradle" and "Patch
mainTemplate.gradle" on (EDM4U 1.2.183+).

**iOS**: Target minimum iOS Version 15.0; EDM4U adds the pod, open the `.xcworkspace`. The Swift bridge and its `.mm`
companion go into the `UnityFramework` target; the `.mm` hands Swift the address of `UnitySendMessage`, so no bridging
header is needed. If Xcode asks for a Swift version, set `SWIFT_VERSION = 5.0` on `UnityFramework`.

**Push**: Android takes the FCM token and data messages (the **Push (Firebase)** sample). Firebase Unity hands a data
message to C# only while the game runs; for notifications while it is closed, the game's own service, derived from
Firebase's `com.google.firebase.messaging.cpp.ListenerService`, calls `ClomniPush.handle(this, message.data)` first
(see `android/docs/push.md`). iOS takes the APNs device token as hex, not the FCM token (`com.unity.mobile.notifications`:
`AuthorizationRequest.DeviceToken`), and the tapped notification's `UserInfo` goes to `HandlePush`.

**Sample**: Samples → **Basic** → Import, add `ClomniBasicSample` to an empty GameObject, fill in the App ID and API
keys, build to a device.

## Checks (for the SDK's developers)

The package's C# compiles without Unity against stub `UnityEngine` and Firebase types, once per platform:

```bash
cd unity
dotnet build "Tests~/Compile/Samples/Samples.csproj" -p:DefineConstants=UNITY_ANDROID   # also UNITY_IOS, and none
python3 "Tests~/check-android-api.py"           # every JVM call against android/messenger/api/messenger.api
swift build --package-path "Tests~/Swift"      # the Swift bridge against ios/api/ClomniMessenger.txt's signatures
```
