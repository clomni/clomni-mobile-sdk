# Версии

## 1.0.6

| Пакет | Версия |
|---|---|
| Android `ai.clomni:messenger` | 1.0.6 |
| React Native `@clomni/react-native` | 1.0.6 |
| Flutter `clomni_flutter` | 1.0.6 |
| Unity | тег `unity-1.0.6` |
| iOS `ClomniMessenger` | 1.0.4, без изменений |

Изменился только Android. Push, пришедший, когда приложение не запущено, запускает его без экрана. SDK считал, что
приложение открыто, и подключался, а сервер видел пользователя в сети: панель переставала писать, что ответ уйдёт
push-уведомлением, и после первого ответа push больше не приходили. Теперь соединение ждёт, пока откроется один из
экранов приложения. В приложениях, которые инициализируют SDK позже (React Native, Flutter, Unity), выход из
приложения теперь тоже закрывает соединение, и push приходят в фоне. В коде ничего менять не нужно.

Чтобы обновиться: Android `ai.clomni:messenger:1.0.6`, React Native `@clomni/react-native@1.0.6`, Flutter
`clomni_flutter: ^1.0.6`, Unity `#unity-1.0.6` (затем resolve в EDM4U). iOS остаётся 1.0.4.

## 1.0.5

| Пакет | Версия |
|---|---|
| Android `ai.clomni:messenger` | 1.0.5 |
| React Native `@clomni/react-native` | 1.0.5 |
| Flutter `clomni_flutter` | 1.0.5 |
| Unity | тег `unity-1.0.5` |
| iOS `ClomniMessenger` | 1.0.4, без изменений |

Изменился только Android. Камера SDK теперь использует собственный класс FileProvider. Раньше сборка Android могла
остановиться на слиянии манифестов, если приложение или другая библиотека (например, unity-webview в игре на Unity)
тоже использовали FileProvider из androidx: `provider#androidx.core.content.FileProvider@authorities … collides with
another value`. 1.0.5 собирается вместе с ними. Если вы добавили `tools:replace` из-за этой ошибки, удалите его.
Больше ничего не меняется.

Чтобы обновиться: Android `ai.clomni:messenger:1.0.5`, React Native `@clomni/react-native@1.0.5`, Flutter
`clomni_flutter: ^1.0.5`, Unity `#unity-1.0.5` (затем resolve в EDM4U). iOS остаётся 1.0.4.

## 1.0.4

Все пакеты в версии 1.0.4: Android, iOS, React Native, Flutter и Unity (тег `unity-1.0.4`).

- Если в шаге с кнопками выключено «Customer can't type», поле ввода остаётся под кнопками. Клиент может выбрать
  кнопку или написать ответ.
- После шага «Turn off typing» клиент не может писать в этот разговор. Блокировка остаётся и после окончания сценария:
  если разговор закрыт, клиенту остаётся только «Начать новый диалог». Поле ввода возвращается на шаге с вопросом, при
  передаче оператору или когда пишет оператор.
- Сценарии без этих настроек работают как раньше. Прежние версии SDK не видят этих настроек и ведут себя как раньше.

Чтобы обновиться, поставьте версию 1.0.4: Android `ai.clomni:messenger:1.0.4`, React Native
`@clomni/react-native@1.0.4`, Flutter `clomni_flutter: ^1.0.4`, Unity `#unity-1.0.4`, iOS `from: "1.0.4"` или `:tag =>
'1.0.4'`.

## 1.0.3

Все пакеты в версии 1.0.3: Android, iOS, React Native, Flutter и Unity (тег `unity-1.0.3`).

- Кнопка микрофона отвечает сразу при касании: круг, таймер и вибрация появляются мгновенно.
- Нажатие в одну секунду тоже записывается, подсказка "нажмите и держите" больше не появляется.

Чтобы обновиться, поставьте версию 1.0.3: Android `ai.clomni:messenger:1.0.3`, React Native
`@clomni/react-native@1.0.3`, Flutter `clomni_flutter: ^1.0.3`, Unity `#unity-1.0.3`, iOS `from: "1.0.3"` или `:tag =>
'1.0.3'`.

## 1.0.2

| Пакет | Версия |
|---|---|
| Android `ai.clomni:messenger` | 1.0.2 |
| React Native `@clomni/react-native` | 1.0.2 |
| Flutter `clomni_flutter` | 1.0.2 |
| Unity | тег `unity-1.0.2` |
| iOS `ClomniMessenger` | 1.0.2 |

### Что изменилось

- Голосовые сообщения: нажмите и держите кнопку микрофона. Сдвиг влево отменяет запись, сдвиг вверх фиксирует её. Перед
  отправкой запись можно прослушать, скорость 1×, 1.5× и 2×.
- Фото и видео с камеры.
- Сообщения, написанные без интернета, ждут в очереди и уходят, когда связь вернётся.
- Адреса без `https://`, например `clomni.ai`, тоже становятся ссылками.
- Плавающая кнопка появляется, даже если `initialize` вызван поздно (React Native, Flutter, Unity).
- Android: Messenger больше не пропадает в приложении, где `MainActivity` с `singleTask`.
- Имя пользователя не теряется при повторном запуске приложения.
- Строка "присоединился к диалогу" стоит на своём месте.
- Рядом с "Вы" показывается логотип компании.
- Сценарий заканчивается на варианте без продолжения, и открывается поле ввода.
- На iPhone поле ввода держится над клавиатурой.
- На уровне `debug` в лог пишутся шаги SDK.
- Язык Messenger одинаковый с интернетом и без него.
- Кнопки эмодзи больше нет, справа от поля ввода кнопка микрофона.

### Разрешения

- Android: голосовым сообщениям нужно `RECORD_AUDIO` в манифесте приложения, иначе кнопка микрофона не показывается.
  Камере разрешение не нужно. См. [Android → Требования](03-android.md#требования).
- iOS: `NSCameraUsageDescription` и `NSMicrophoneUsageDescription`. См. [iOS → Info.plist](04-ios.md#infoplist).

### Как обновить

- **Android:** `implementation("ai.clomni:messenger:1.0.2")`.
- **React Native:** `npm install @clomni/react-native@1.0.2`, затем пересоберите приложение (на iOS `pod install`).
- **Flutter:** `clomni_flutter: ^1.0.2`, затем `flutter pub get`.
- **Unity:** адрес пакета `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.2`, затем **Force
  Resolve**.
- **iOS:** `from: "1.0.2"` в Swift Package Manager, `:tag => '1.0.2'` в CocoaPods. В этот раз изменился и код iOS.

## 1.0.1

| Пакет | Версия |
|---|---|
| Android `ai.clomni:messenger` | 1.0.1 |
| React Native `@clomni/react-native` | 1.0.1 |
| Flutter `clomni_flutter` | 1.0.1 |
| Unity | тег `unity-1.0.1` |
| iOS `ClomniMessenger` | 1.0.0, без изменений |

### Что изменилось

При подключении Android SDK отправляет имя пакета приложения. Clomni сравнивает его с «Android package name» канала и
отклоняет ключ, если они не совпадают. На iOS такая же проверка по Bundle ID была с самого начала. React Native,
Flutter и Unity 1.0.1 используют на Android этот новый SDK. На iOS ничего не изменилось.

### Кого это касается

Приложений на Android. Если имя пакета в канале совпадает с `applicationId` приложения, ничего не меняется. Если нет,
после 1.0.1 Android-приложение не подключится. Если в канале имя пакета Android не указано, проверки нет.

`applicationIdSuffix` тоже входит в имя пакета. У debug-сборки с суффиксом `.debug` имя пакета
`com.example.app.debug`, и канал с `com.example.app` её не примет. Для тестов используйте сборку без суффикса или
создайте отдельный канал для debug-приложения.

### Перед обновлением

Имя пакета Android в канале должно совпадать с `applicationId` в `app/build.gradle(.kts)`. Его вводят в мастере
при создании канала, позже изменить его в панели негде. Если оно указано неверно, напишите Clomni AI правильное имя
пакета приложения, команда Clomni исправит.

### Как обновить

- **Android:** `implementation("ai.clomni:messenger:1.0.1")`, затем Gradle sync.
- **React Native:** `npm install @clomni/react-native@1.0.1`, затем пересоберите приложение.
- **Flutter:** `clomni_flutter: ^1.0.1` в `pubspec.yaml`, затем `flutter pub get`.
- **Unity:** в Package Manager замените адрес пакета на
  `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1` (или `#unity-1.0.1` в
  `Packages/manifest.json`), затем **Assets → External Dependency Manager → Android Resolver → Force Resolve**.
- **iOS:** ничего делать не нужно.

### Если не совпадает

Messenger не открывается, сервер отклоняет ключ с ответом 401 `invalid_api_key`. В Logcat, тег `Clomni` (SDK пишет
это сообщение на азербайджанском):

```text
api_key səhvdir və ya bu platforma üçün deyil. Tətbiqin paket adı: com.example.app.debug; paneldəki Android paket adı ilə eyni olmalıdır (applicationIdSuffix da sayılır)
```

Сравните имя пакета в логе с тем, что в панели.

## 1.0.0

Первый выпуск: Android, iOS, React Native, Flutter и Unity.
