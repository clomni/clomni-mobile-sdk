# Android

## Требования

- Android 6.0 (API 23) или новее.
- Актуальный `compileSdk` (35 или новее).
- Kotlin 1.8 или новее. Java тоже подходит (см. конец главы).
- App ID и API-ключ Android (`android_…`) из раздела **Installation** в колонке настроек канала.

Кроме доступа к сети, SDK не запрашивает собственных разрешений и ничего не добавляет на ваши экраны.

## Установка

Пакет опубликован в Maven Central. В большинстве проектов `mavenCentral()` уже указан в `settings.gradle.kts`.

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("ai.clomni:messenger:1.0.0")
}
```

## Инициализация

Вызовите `initialize` один раз, в классе `Application`. Процесс приложения может запустить уведомление, а открытому
им Messenger нужен готовый SDK, поэтому `Activity` — слишком поздно.

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

Для `BuildConfig.DEBUG` на AGP 8 и новее нужен `buildFeatures { buildConfig = true }` в `app/build.gradle.kts`.

Любой метод `Clomni` можно вызывать из любого потока. Слушатели вызываются в главном потоке. Повторный `initialize`
игнорируется.

## Пользователь

Авторизуйте пользователя после входа в ваше приложение, с хешем от вашего сервера
([Идентификация пользователей](02-identity.md)):

```kotlin
val user = ClomniUser(userId = "12345", email = "aysel@example.com", name = "Aysel Məmmədova")
Clomni.loginUser(user, userHash = hashFromYourServer)

Clomni.updateUser(language = "az", customAttributes = mapOf("plan" to "premium"))

// Вместе с выходом из вашего приложения:
Clomni.logout()
```

## Открытие Messenger

Из вашей собственной кнопки. `source` указывает, из какого места приложения он открыт.

```kotlin
findViewById<View>(R.id.support).setOnClickListener {
    Clomni.present(source = "profile_support")
}
```

В Jetpack Compose:

```kotlin
Button(onClick = { Clomni.present(source = "profile_support") }) {
    Text("Поддержка")
}
```

Другие способы открыть и закрыть:

| Вызов | Что делает |
|---|---|
| `Clomni.present(source)` | Открывает главный экран |
| `Clomni.presentNewConversation(source)` | Сразу открывает новый диалог |
| `Clomni.presentConversation(id)` | Открывает известный диалог; ID приходит из `onConversationStarted` |
| `Clomni.dismiss()` | Закрывает Messenger из кода |

### Счётчик непрочитанных

Показывайте число непрочитанных ответов рядом с вашей кнопкой. Слушатель сразу получает текущее значение, а затем
каждое изменение.

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

### Плавающая кнопка (необязательно)

![Плавающая кнопка поверх экрана приложения, со счётчиком непрочитанных](../images/sdk-launcher.png)

По умолчанию плавающая кнопка выключена. Её можно включить в панели (Appearance → Theme); значение из кода важнее.
`setBottomPadding` поднимает её над нижней панелью навигации, в dp.

```kotlin
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Сценарии, запускаемые приложением

Кнопка на одном из ваших экранов может начать диалог на конкретную тему, например о проблеме с поездкой. В панели
соберите сценарий с триггером «App event» и именем события `ride_problem` и опубликуйте его. В приложении:

```kotlin
Clomni.startFlow(
    "ride_problem",
    mapOf("ride_id" to "R-1923"),
    openMessenger = true,
    source = "ride_screen",
)
```

- Тексты сценария могут использовать данные как `{{data.ride_id}}`. Данные должны быть JSON-значениями: строки,
  числа, логические значения, списки и словари.
- Если к событию не привязан опубликованный сценарий, ничего не происходит.
- Для события, которое пользователь не вызывал сам (например, неудачный платёж), оставьте `openMessenger = false`.
  Пользователь узнает о диалоге из push-уведомления или по счётчику непрочитанных.

## События

```kotlin
Clomni.onMessengerOpened { source -> Log.d("App", "opened from $source") }
Clomni.onMessengerClosed { Log.d("App", "closed") }
Clomni.onConversationStarted { id -> Log.d("App", "conversation $id") }
Clomni.onFlowCompleted { flowId -> Log.d("App", "flow $flowId completed") }
Clomni.onUnreadCountChanged { count -> Log.d("App", "unread $count") }
```

У каждого события один слушатель. Новый заменяет старый; `null` удаляет его.

## Ссылки

Кнопка новости может содержать веб-адрес или deep link вашего приложения. С `onLink` ссылка сначала приходит в ваше
приложение. Верните `true`, если приложение её открыло; `false` или отсутствие слушателя — и её откроет система.

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

## Язык, звуки и оформление

```kotlin
Clomni.setLanguage("en")          // az, en или ru; null — как на телефоне
Clomni.setSoundsEnabled(false)    // выключено независимо от панели
```

- **Язык.** Messenger говорит на языках, включённых в панели (Appearance → Languages). `setLanguage` выбирает один из
  них. `null` или выключенный язык — и Messenger берёт язык телефона, а затем основной язык панели.
- **Звуки.** Короткий звук при отправке и получении сообщения, пока диалог открыт. Учитывает беззвучный режим
  телефона.

Цвета, логотип и тексты приходят из панели. Чтобы наложить поверх них собственный цвет, шрифт и режим приложения,
используйте `setTheme`. Цвет задаётся как `#RRGGBB`; остальные цвета бренда вычисляются из него. Каждый вызов
заменяет предыдущий, а неуказанное значение остаётся из панели.

```kotlin
Clomni.setTheme(
    primaryColor = "#0A66C2",
    typeface = ResourcesCompat.getFont(context, R.font.montserrat),
    mode = ClomniThemeMode.DARK,      // LIGHT, DARK или SYSTEM
)
```

![Оформление из панели, светлое и тёмное, и собственный цвет приложения](../images/sdk-theme.png)

Только для шрифта: `Clomni.setTypeface(typeface)`. Шрифт по-прежнему учитывает настройку размера текста.

## Push-уведомления

Ответы операторов доходят до закрытого приложения как data-сообщения Firebase Cloud Messaging (FCM). У SDK нет
зависимости от Firebase: приложение сохраняет свой `firebase-messaging` и передаёт Clomni токен и сообщения. Ваши
собственные push-уведомления остаются вашими.

Понадобятся:

1. Проект Firebase с добавленным Android-приложением и его `google-services.json` в приложении.
2. JSON-файл service account проекта, загруженный в панель ([Ключи для push](08-push-keys.md)).
3. Код ниже.

### 1. Firebase в приложении

В [Firebase console](https://console.firebase.google.com) откройте свой проект (или создайте новый) и добавьте
Android-приложение с вашим именем пакета.

> **Путь:** `Firebase console → ваш проект → Project Overview → + Add app → Android`
>
> Введите имя пакета приложения в **Android package name** (например, `com.example.app`) и нажмите **Register app**.
>
> Документация: [firebase.google.com/docs/android/setup](https://firebase.google.com/docs/android/setup#register-app)

Скачайте `google-services.json` и положите его в папку `app/` вашего проекта.

> **Путь:** `Firebase: Download google-services.json → Android Studio: <проект>/app/google-services.json`
>
> Чтобы увидеть файл в Android Studio, выберите вид **Project** в меню вверху окна Project.
>
> Документация: [firebase.google.com/docs/android/setup](https://firebase.google.com/docs/android/setup#add-config-file), [developer.android.com/studio/projects](https://developer.android.com/studio/projects#ProjectView)

```kotlin
// settings.gradle.kts (или корневой build.gradle.kts)
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
    implementation("ai.clomni:messenger:1.0.0")
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-messaging")
}
```

> `google-services.json` нужен приложению. Панели нужен другой файл — **service account JSON**. См.
> [Ключи для push](08-push-keys.md).

### 2. Передача токена и сообщений

```kotlin
// AppMessagingService.kt
import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniPush
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
        // и на ваш сервер, если у приложения есть свои push-уведомления
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (ClomniPush.handle(this, message.data)) return
        // собственный push приложения
    }
}
```

```xml
<!-- AndroidManifest.xml, внутри <application> -->
<service
    android:name=".AppMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

FCM вызывает `onNewToken` только при смене токена. Передавайте текущий токен и при каждом запуске, в
`Application.onCreate` после `initialize`:

```kotlin
FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
```

Токен регистрируется для того, кто сейчас авторизован, и повторно — после следующего `loginUser` или `logout`.
`ClomniPush.isClomniPush(data)` отличает push от Clomni от ваших собственных, не обрабатывая его.

### 3. Разрешение на Android 13 и новее

Для уведомлений нужно разрешение `POST_NOTIFICATIONS`. SDK никогда его не запрашивает. Объявите его и запросите в
момент, понятный пользователю, например после его первого сообщения:

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

Без разрешения ничего не показывается, но счётчик непрочитанных остаётся актуальным.

### Что видит пользователь

- Одно уведомление на диалог. Заголовок — оператор и бренд («Leyla · Example»), текст — само сообщение (до 180
  символов), показывается фото оператора. Более новое сообщение того же диалога заменяет уведомление.
- Канал уведомлений — `clomni_messages` (`ClomniPush.CHANNEL_ID`), с названием «Support messages» на языке
  Messenger и высокой важностью. Он создаётся при первом показе уведомления. Пользователь может отключить его в
  настройках системы.
- Нажатие открывает стартовый экран приложения, а поверх него — Messenger с этим диалогом.
- Пока Messenger открыт, уведомления Clomni не показываются: сообщение показывает сам Messenger.

Маленькая иконка — это иконка приложения. Android рисует её силуэтом, поэтому, если иконка приложения не белая,
передайте SDK белую:

```kotlin
Clomni.setNotificationIcon(R.drawable.ic_notification)
```

### Проверка

1. Запустите приложение на телефоне, разрешите уведомления и один раз откройте Messenger.
2. В панели: **Push** в колонке настроек → **Test push** → выберите устройство → **Send**.

Чтобы увидеть уведомление Clomni без сервера, передайте `ClomniPush.handle` словарь самостоятельно:

```kotlin
ClomniPush.handle(context, mapOf(
    "clomni" to "1", "type" to "message", "conversation_id" to "conv_1",
    "title" to "Leyla · Example", "body" to "Мы проверили вашу поездку.", "unread_total" to "1",
))
```

## Java

Все вызовы работают и из Java:

```java
Clomni.initialize(context, "app_…", "android_…");
Clomni.loginUser(new ClomniUser("12345", "aysel@example.com"), hashFromYourServer);
Clomni.present("profile_support");
Clomni.onLink(url -> false);
```

## Проблемы

| Симптом | Что делать |
|---|---|
| `call Clomni.initialize first` в logcat | Вызывайте `initialize` в `Application.onCreate` и укажите класс в манифесте через `android:name` |
| `api_key səhvdir və ya bu platforma üçün deyil` | Ключ неверный, отозван или это ключ iOS. Используйте ключ `android_…` |
| Уведомления нет, в logcat `notification not shown (POST_NOTIFICATIONS?)` | Запросите `POST_NOTIFICATIONS` на Android 13+ |
| `push token not registered: …` | Проверьте вызовы `setDeviceToken` и service account JSON в панели |
| Уведомления приходят, но иконка — серый квадрат | Задайте белую иконку-силуэт через `setNotificationIcon` |
| `onMessageReceived` вашего сервиса никогда не вызывается | Сервиса нет в манифесте или сообщения забирает другой `FirebaseMessagingService` в приложении. Он может быть только один: передавайте сообщения Clomni из него |

Подробнее — в главе [Решение проблем](09-troubleshooting.md). Логи — в logcat под тегом `Clomni`.
