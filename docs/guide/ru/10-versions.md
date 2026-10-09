# Версии

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
