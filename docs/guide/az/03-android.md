# Android

## Tələblər

- Android 6.0 (API 23) və ya daha yeni.
- `compileSdk` 35 və ya daha yeni.
- Kotlin 1.8 və ya daha yeni. Java da işləyir (bölmənin sonuna baxın).
- Paneldə kanalın ayarlar sütununun **Quraşdırma** bölməsindən App ID və Android API açarı (`android_…`).

SDK 1.0.1 şəbəkə girişindən başqa heç bir icazə istəmir və ekranlarınıza heç nə əlavə etmir. 1.0.2-dən söhbətdə kamera
ilə şəkil və video çəkmək və səsli mesaj göndərmək olar:

- **Kamera** üçün icazə lazım deyil: SDK telefonun öz kamera tətbiqini açır, FileProvider SDK-nın içindədir. Tətbiqin
  manifestində `CAMERA` elan olunubsa, SDK əvvəlcə bu icazəni soruşur.
- **Səsli mesaj** üçün tətbiq öz `AndroidManifest.xml`-ində `RECORD_AUDIO` elan etməlidir. Elan olunmayıbsa, mikrofon
  düyməsi görünmür və SDK bunu loga yazır.

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

## Quraşdırma

Paket Maven Central-dadır. Əksər layihələrdə `settings.gradle.kts`-də `mavenCentral()` artıq var.

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("ai.clomni:messenger:1.0.1")
}
```

## Başlatma

`initialize`-i bir dəfə, `Application` sinfinizdə çağırın. Bildiriş tətbiqin prosesini başlada bilər, onun açdığı
Messenger-ə isə hazır SDK lazımdır. Ona görə `Activity` gecdir.

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

AGP 8 və daha yeni versiyada `BuildConfig.DEBUG` üçün `app/build.gradle.kts`-də `buildFeatures { buildConfig = true }`
lazımdır.

`Clomni`-nin hər metodunu istənilən thread-dən çağırmaq olar. Dinləyicilər əsas thread-də çağırılır. İkinci
`initialize` nəzərə alınmır.

## İstifadəçi

İstifadəçini öz login-inizdən sonra, serverdən gələn hash ilə daxil edin
([İstifadəçinin tanıdılması](02-identity.md)):

```kotlin
val user = ClomniUser(userId = "12345", email = "aysel@example.com", name = "Aysel Məmmədova")
Clomni.loginUser(user, userHash = hashFromYourServer)

Clomni.updateUser(language = "az", customAttributes = mapOf("plan" to "premium"))

// Tətbiqin öz çıxışı ilə birlikdə:
Clomni.logout()
```

Tətbiq hər açılanda, istifadəçi daxil olubsa, `loginUser`-i yenidən çağırın, istifadəçi təzə daxil olmuş kimi. Eyni
istifadəçi üçün SDK saxlanmış sessiyanı işlədir.

## Messenger-i açmaq

Öz düymənizdən. `source` Messenger-in tətbiqin harasından açıldığını deyir.

```kotlin
findViewById<View>(R.id.support).setOnClickListener {
    Clomni.present(source = "profile_support")
}
```

Jetpack Compose-da:

```kotlin
Button(onClick = { Clomni.present(source = "profile_support") }) {
    Text("Dəstək")
}
```

Açmağın və bağlamağın digər yolları:

| Çağırış | Nə edir |
|---|---|
| `Clomni.present(source)` | Ana səhifəni açır |
| `Clomni.presentNewConversation(source)` | Birbaşa yeni söhbət açır |
| `Clomni.presentConversation(id)` | Məlum söhbəti açır; ID `onConversationStarted`-dən gəlir |
| `Clomni.dismiss()` | Messenger-i koddan bağlayır |

### Oxunmamış mesajların sayı

Oxunmamış cavabların sayını düymənizin yanında göstərin. Dinləyici cari sayı dərhal, sonra hər dəyişikliyi eşidir.

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

### Üzən düymə (istəyə bağlı)

![Tətbiq ekranının üstündə üzən düymə və oxunmamış mesajların sayı](../images/sdk-launcher.png)

Üzən düymə standart olaraq sönülüdür. Panel onu yandıra bilər (Görünüş → Tema), kodda verilən dəyər isə paneldən
üstündür. `setBottomPadding` düyməni aşağıdakı naviqasiya panelinin üstünə qaldırır, dp ilə.

```kotlin
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Tətbiqin başlatdığı flow-lar

Ekranlarınızdan birindəki düymə müəyyən mövzuda söhbət başlada bilər, məsələn gedişlə bağlı problem. Paneldə
"Tətbiq hadisəsi" trigger-i və `ride_problem` hadisə adı ilə flow qurun və onu dərc edin. Tətbiqdə:

```kotlin
Clomni.startFlow(
    "ride_problem",
    mapOf("ride_id" to "R-1923"),
    openMessenger = true,
    source = "ride_screen",
)
```

- Flow-un mətnləri datanı `{{data.ride_id}}` kimi işlədə bilər. Data JSON dəyərləri olmalıdır: sətirlər, rəqəmlər,
  boolean-lar, siyahılar və map-lər.
- Hadisəyə bağlı dərc olunmuş flow yoxdursa, heç nə baş vermir.
- İstifadəçinin özünün basmadığı hadisə üçün (məsələn, uğursuz ödəniş) `openMessenger = false` saxlayın. İstifadəçi
  söhbətdən push və ya oxunmamış mesajların sayı ilə xəbər tutur.

**Hadisənin adı flow-un adı deyil.** `startFlow`-a paneldəki Flow-lar bölməsində flow-un altındakı "Hadisə: …"
sətrindəki adı verin. Flow "Tətbiq hadisəsi" trigger-i ilə qurulmalıdır: "Söhbət başlayanda" trigger-li flow `startFlow`
ilə başlamır.

## Hadisələr

```kotlin
Clomni.onMessengerOpened { source -> Log.d("App", "opened from $source") }
Clomni.onMessengerClosed { Log.d("App", "closed") }
Clomni.onConversationStarted { id -> Log.d("App", "conversation $id") }
Clomni.onFlowCompleted { flowId -> Log.d("App", "flow $flowId completed") }
Clomni.onUnreadCountChanged { count -> Log.d("App", "unread $count") }
```

Hər hadisənin bir dinləyicisi olur. Yenisini vermək köhnəsini əvəz edir, `null` onu silir.

## Linklər

Xəbərin düyməsində veb ünvanı və ya tətbiqinizin deep link-i ola bilər. `onLink` ilə link əvvəlcə tətbiqinizə
gəlir. Tətbiq linki açıbsa `true` qaytarın. `false` qaytarsanız və ya dinləyici yoxdursa, linki sistem açır.

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

## Dil, səslər və görünüş

```kotlin
Clomni.setLanguage("en")          // az, en və ya ru; null telefonun dilinə uyğunlaşır
Clomni.setSoundsEnabled(false)    // panel nə desə də səslər sönür
```

- **Dil.** Messenger paneldə yandırılmış dillərdə danışır (Görünüş → Dillər). `setLanguage` onlardan birini seçir.
  `null` və ya sönülü dil verilsə, telefonun dili, o da yoxdursa panelin əsas dili işlənir.
- **Səslər.** Söhbət açıq olanda göndərilən və gələn mesaj üçün qısa səs. Telefonun səssiz rejiminə tabedir.

Rənglər, loqo və mətnlər paneldən gəlir. Onların üstünə tətbiqin öz rəngini, şriftini və rejimini qoymaq üçün
`setTheme` işlədin. Rəng `#RRGGBB` formatındadır, brendin digər rəngləri ondan törədilir. Hər çağırış əvvəlkini
əvəz edir, verilməyən dəyər panelinki qalır.

```kotlin
Clomni.setTheme(
    primaryColor = "#0A66C2",
    typeface = ResourcesCompat.getFont(context, R.font.montserrat),
    mode = ClomniThemeMode.DARK,      // LIGHT, DARK və ya SYSTEM
)
```

![Panelin görünüşü, açıq və tünd, və tətbiqin öz rəngi](../images/sdk-theme.png)

Yalnız şrift üçün: `Clomni.setTypeface(typeface)`. Şrift istifadəçinin mətn ölçüsü ayarına yenə tabedir.

## Push bildirişləri

Operatorların cavabları bağlı tətbiqə Firebase Cloud Messaging (FCM) data mesajları kimi çatır. SDK-nın Firebase
asılılığı yoxdur: tətbiqiniz öz `firebase-messaging` kitabxanasını saxlayır, Clomni-yə isə tokeni və mesajları
verir. Sizin öz push-larınız sizdə qalır.

Lazım olanlar:

1. Android tətbiqiniz əlavə olunmuş Firebase layihəsi və tətbiqdə onun `google-services.json` faylı.
2. Panelə yüklənmiş layihənin service account JSON faylı ([Push açarları](08-push-keys.md)).
3. Aşağıdakı kod.

### 1. Tətbiqdə Firebase

[Firebase console](https://console.firebase.google.com)-da layihənizi açın (və ya yaradın) və paket adınızla
Android tətbiqi əlavə edin.

> **Yol:** `Firebase console → layihəniz → Project Overview → + Add app → Android`
>
> **Android package name** sahəsinə tətbiqin paket adını yazın (məsələn `com.example.app`) və **Register app** basın.
>
> Sənəd: [firebase.google.com/docs/android/setup](https://firebase.google.com/docs/android/setup#register-app)

`google-services.json`-u yükləyin və layihənizin `app/` qovluğuna qoyun.

> **Yol:** `Firebase: Download google-services.json → Android Studio: <layihə>/app/google-services.json`
>
> Faylı Android Studio-da görmək üçün Project pəncərəsinin yuxarısındakı menyudan **Project** görünüşünü seçin.
>
> Sənəd: [firebase.google.com/docs/android/setup](https://firebase.google.com/docs/android/setup#add-config-file), [developer.android.com/studio/projects](https://developer.android.com/studio/projects#ProjectView)

```kotlin
// settings.gradle.kts (və ya kökdəki build.gradle.kts)
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

> `google-services.json` tətbiq üçündür. Panelə başqa fayl lazımdır: **service account JSON**. Bax:
> [Push açarları](08-push-keys.md).

### 2. Token və mesajların ötürülməsi

```kotlin
// AppMessagingService.kt
import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniPush
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
        // tətbiqin öz push-ları varsa, öz serverinizə də
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (ClomniPush.handle(this, message.data)) return
        // tətbiqin öz push-u
    }
}
```

```xml
<!-- AndroidManifest.xml, <application> içində -->
<service
    android:name=".AppMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

FCM `onNewToken`-i yalnız token dəyişəndə çağırır. Cari tokeni hər açılışda da verin, `Application.onCreate`-də
`initialize`-dən sonra:

```kotlin
FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
```

Token kim daxil olubsa onun üçün qeydə alınır, növbəti `loginUser` və ya `logout`-dan sonra yenidən.
`ClomniPush.isClomniPush(data)` push-u emal etmədən onun Clomni-yə, yoxsa sizə aid olduğunu deyir.

### 3. Android 13 və daha yeni versiyada icazə

Bildirişlər üçün `POST_NOTIFICATIONS` icazəsi lazımdır. SDK onu heç vaxt istəmir. İcazəni manifestdə elan edin və
istifadəçilərə məntiqli görünən anda istəyin, məsələn ilk mesajdan sonra:

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

İcazə olmasa heç nə göstərilmir, amma oxunmamış mesajların sayı yenə yenilənir.

### İstifadəçi nə görür

- Hər söhbətə bir bildiriş. Başlıq operator və brenddir ("Leyla · Example"), mətn mesajın özüdür (180 simvola
  qədər), operatorun şəkli də görünür. Eyni söhbətin yeni mesajı köhnə bildirişi əvəz edir.
- Bildiriş kanalı `clomni_messages`-dir (`ClomniPush.CHANNEL_ID`), Messenger-in dilində "Dəstək mesajları"
  adlanır, önəmi yüksəkdir. O, ilk bildiriş göstəriləndə yaranır. İstifadəçi onu sistem ayarlarında söndürə bilər.
- Bildirişə toxunanda tətbiqin başlanğıc ekranı, üstündə isə həmin söhbətdə Messenger açılır.
- Messenger açıq olanda Clomni bildirişləri göstərilmir: mesajı Messenger özü göstərir.

Kiçik ikon tətbiqinizin ikonudur. Android onu siluet kimi çəkir, ona görə tətbiq ikonunuz siluet deyilsə, SDK-ya ağ
ikon verin:

```kotlin
Clomni.setNotificationIcon(R.drawable.ic_notification)
```

### Yoxlama

1. Tətbiqi telefonda işə salın, bildirişlərə icazə verin və Messenger-i bir dəfə açın.
2. Paneldə: ayarlar sütununda **Push** → **Test bildirişi** → cihazı seçin → **Göndər**.

Serversiz Clomni bildirişini görmək üçün `ClomniPush.handle`-a map-i özünüz verin:

```kotlin
ClomniPush.handle(context, mapOf(
    "clomni" to "1", "type" to "message", "conversation_id" to "conv_1",
    "title" to "Leyla · Example", "body" to "Gedişinizi yoxladıq.", "unread_total" to "1",
))
```

## Java

Bütün çağırışlar Java-dan da işləyir:

```java
Clomni.initialize(context, "app_…", "android_…");
Clomni.loginUser(new ClomniUser("12345", "aysel@example.com"), hashFromYourServer);
Clomni.present("profile_support");
Clomni.onLink(url -> false);
```

## Problemlər

| Əlamət | Nə etməli |
|---|---|
| logcat-da `call Clomni.initialize first` | `initialize`-i `Application.onCreate`-də çağırın və sinfi manifestdə `android:name` ilə göstərin |
| `api_key səhvdir və ya bu platforma üçün deyil` | Açar səhvdir, ləğv olunub və ya iOS açarıdır. `android_…` açarını işlədin |
| Bildiriş yoxdur, logcat-da `notification not shown (POST_NOTIFICATIONS?)` | Android 13+ üçün `POST_NOTIFICATIONS` icazəsini istəyin |
| `push token not registered: …` | `setDeviceToken` çağırışlarını və paneldəki service account JSON-u yoxlayın |
| Bildirişlər gəlir, amma ikon boz kvadratdır | `setNotificationIcon` ilə ağ siluet ikon verin |
| Servisinizin `onMessageReceived`-i heç çağırılmır | Servis manifestdə yoxdur, ya da tətbiqdəki başqa `FirebaseMessagingService` mesajları götürür. Tətbiqdə yalnız biri olur: Clomni mesajlarını həmin servisdə ötürün |

Daha çoxu: [Problemlərin həlli](09-troubleshooting.md). Loglar logcat-da `Clomni` tag-i ilədir.
