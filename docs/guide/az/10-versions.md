# Versiyalar

## 1.0.1

| Paket | Versiya |
|---|---|
| Android `ai.clomni:messenger` | 1.0.1 |
| React Native `@clomni/react-native` | 1.0.1 |
| Flutter `clomni_flutter` | 1.0.1 |
| Unity | `unity-1.0.1` teqi |
| iOS `ClomniMessenger` | 1.0.0, dəyişməyib |

### Nə dəyişib

Android SDK qoşulanda tətbiqin paket adını göndərir. Clomni onu kanalın "Android paket adı" ilə müqayisə edir və
uyğun gəlməsə açarı rədd edir. iOS-da Bundle ID ilə eyni yoxlama əvvəldən var idi. React Native, Flutter və Unity
1.0.1 Android-də bu yeni SDK-nı işlədir. iOS tərəfi dəyişməyib.

### Kimə təsir edir

Android tətbiqi olanlara. Kanaldakı Android paket adı tətbiqin `applicationId`-si ilə eynidirsə, heç nə dəyişmir.
Fərqlidirsə, 1.0.1-dən sonra Android tətbiqi qoşulmur. Kanalda Android paket adı yazılmayıbsa, yoxlama yoxdur.

`applicationIdSuffix` da paket adına daxildir. Debug build-in `.debug` suffiksi varsa, onun paket adı
`com.example.app.debug` olur və `com.example.app` yazılmış kanalda qəbul olunmur. Sınaq üçün suffiksi olmayan
build işlədin, ya da debug tətbiqi üçün ayrıca kanal yaradın.

### Yeniləməzdən əvvəl

Kanalın Android paket adı `app/build.gradle(.kts)`-dəki `applicationId` ilə eyni olmalıdır. Paket adı kanal
yaradılanda sehrbazda yazılır, sonra paneldə onu dəyişmək yeri yoxdur. Səhv yazılıbsa, Clomni AI-yə tətbiqin düzgün
paket adını yazın, Clomni komandası düzəldir.

### Necə yeniləmək olar

- **Android:** `implementation("ai.clomni:messenger:1.0.1")`, sonra Gradle sync.
- **React Native:** `npm install @clomni/react-native@1.0.1`, sonra tətbiqi yenidən build edin.
- **Flutter:** `pubspec.yaml`-da `clomni_flutter: ^1.0.1`, sonra `flutter pub get`.
- **Unity:** Package Manager-də paketin ünvanını
  `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1` edin (və ya `Packages/manifest.json`-da
  `#unity-1.0.1`), sonra **Assets → External Dependency Manager → Android Resolver → Force Resolve**.
- **iOS:** heç nə etmək lazım deyil.

### Uyğun gəlməyəndə

Messenger açılmır, server açarı 401 `invalid_api_key` ilə rədd edir. Logcat-da, `Clomni` tag-ı ilə:

```text
api_key səhvdir və ya bu platforma üçün deyil. Tətbiqin paket adı: com.example.app.debug; paneldəki Android paket adı ilə eyni olmalıdır (applicationIdSuffix da sayılır)
```

Logdakı paket adını paneldəki ilə müqayisə edin.

## 1.0.0

İlk buraxılış: Android, iOS, React Native, Flutter və Unity.
