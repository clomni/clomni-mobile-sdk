# Gözlənilən şəkillər

Bu şəkillər Firebase, Apple Developer, Xcode, Android Studio və Unity ekranlarıdır. Onlara bizim girişimiz yoxdur,
ona görə təlimatda indi onların yerində "Şəkil gözlənilir" qutusu durur.

Necə əvəz etmək olar:

- Şəkli eyni adla `docs/guide/images/` qovluğuna qoyun, köhnə qutunun üstünə yazın. Markdown dəyişmir.
- PNG, eni 1400 px-dən çox olmasın. Lazımi yeri qırmızı çərçivə ilə göstərin, panel şəkillərindəki kimi.
- Açar, ID, e-poçt, layihə adı və şirkət adı görünürsə, bulanıqlaşdırın. Nümunə ad lazımdırsa, `Example` və
  `com.example.app` işlədin.
- Sonra PDF-i yenidən yaradın: `node docs/guide/build-pdf.mjs`.

| Fayl | Harada | Nə görünməlidir | Hansı bölmədə |
|---|---|---|---|
| `firebase-add-android-app.png` | Firebase console → layihə → Project Overview → Add app → Android | "Register app" forması, "Android package name" sahəsində `com.example.app` | Android (push, 1-ci addım) |
| `android-studio-google-services.png` | Android Studio → Project görünüşü | Layihə ağacında `app/google-services.json` (seçilmiş) | Android (push, 1-ci addım) |
| `firebase-service-account.png` | Firebase console → Project settings → Service accounts | "Firebase Admin SDK" bölməsi və "Generate new private key" düyməsi (çərçivədə). Service account e-poçtu bulanıq | Push açarları (Android) |
| `apple-keys-create.png` | developer.apple.com/account → Certificates, Identifiers & Profiles → Keys | Keys siyahısı və başlığın yanındakı "+" düyməsi (çərçivədə). Mövcud açarların adları və ID-ləri bulanıq | Push açarları (iOS, 1-ci addım) |
| `apple-apns-environment.png` | Keys → yeni açar → Apple Push Notifications service (APNs) → Configure | "Environment: Sandbox & Production" və "Key Restriction: Team Scoped (All Topics)" seçilib (hər ikisi çərçivədə) | Push açarları (iOS, 1-ci addım) |
| `apple-key-download.png` | Keys → yaradılan açarın səhifəsi | Key ID sətri və "Download" düyməsi (çərçivədə). Key ID bulanıq | Push açarları (iOS, 2-ci addım) |
| `apple-team-id.png` | developer.apple.com/account → Membership details | Team ID sətri (çərçivədə). Team ID və komanda adı bulanıq | Push açarları (iOS, 2-ci addım) |
| `xcode-push-capability.png` | Xcode → tətbiq hədəfi → Signing & Capabilities | Əlavə olunmuş "Push Notifications" capability-si; "+ Capability" düyməsi çərçivədə. Team və Bundle ID `com.example.app` | iOS (push, 1-ci addım) |
| `xcode-notification-service-extension.png` | Xcode → File → New → Target… | Şablon pəncərəsində iOS → "Notification Service Extension" seçilib | iOS (push, 4-cü addım) |
| `unity-add-package-git.png` | Unity → Window → Package Manager | "+" menyusu açıq, "Add package from git URL" seçilib, sahədə `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#1.0.0` | Unity (quraşdırma) |

## SDK ekranları

`sdk-screens.png`, `sdk-theme.png` və `sdk-launcher.png` Android SDK-nın Paparazzi şəkillərindən yığılıb
(`android/messenger/src/test/snapshots/images`). Repozitoriyada iOS ekran şəkilləri yoxdur. iOS SDK eyni ekranları
çəkdiyi üçün təlimat Android şəkillərini işlədir və bunu ilk bölmədə deyir. iOS şəkilləri çəkiləndə onları ayrıca
əlavə etmək olar.

## Panel şəkilləri

`panel-*-az.png` və `panel-*-en.png` dev.clomni.co-da (hesab 7, "Clomni Demo tətbiq" kanalı) Playwright ilə
çəkilib. Açarlar, Key ID, Team ID və Firebase layihəsinin adı bulanıqlaşdırılıb. Panel dəyişəndə onları yenidən
çəkmək lazım ola bilər.
