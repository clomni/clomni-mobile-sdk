# Clomni Mobile SDK: entegrasyon kılavuzu

Clomni Mobile SDK, Clomni Messenger'ı iOS veya Android uygulamanızın içinde açar. Kullanıcılarınız uygulamadan
çıkmadan destek ekibinize yazar; konuşmalar da Clomni'de WhatsApp, Instagram ve web sitesi sohbetiyle aynı yerde
temsilcilerinize düşer.

![Uygulamanın içinde Messenger: ana sayfa, dil seçimi, bir akış adımı ve temsilcinin yanıtı](../images/sdk-screens.png)

*Bu kılavuzdaki ekran görüntüleri Android SDK'dan alınmıştır. iOS SDK aynı ekranları çizer.*

*Clomni panelinin arayüzü Azerbaycanca ve İngilizcedir. Bu kılavuzdaki panel görüntüleri ve düğme adları İngilizce
arayüzdendir.*

## SDK ne yapar

- Messenger'ı yerel (native) ekranlarla açar. WebView kullanılmaz.
- Clomni akışlarınızı yerel düğmelerle çalıştırır: dil seçimi, menüler, formlar, temsilciye aktarma.
- Uygulama kapalıyken gelen yanıtları push bildirimi olarak gösterir.
- Renkleri, logoyu, metinleri ve haberleri Clomni panelinden alır. Panelde yaptığınız bir değişiklik, yeni bir sürüm
  yayınlamadan uygulamaya ulaşır.

SDK ekranlarınıza kendiliğinden hiçbir şey eklemez. Messenger'ı kendi düğmenizden açarsınız, örneğin profil
ekranındaki "Destek" satırından. Yüzen bir düğme de vardır, ancak siz açmadıkça görünmez.

## Paketler

| Platform | Paket | En düşük sürüm |
|---|---|---|
| Android | `ai.clomni:messenger:1.0.2` (Maven Central) | Android 6.0 (API 23), Kotlin 1.8 |
| iOS | Swift Package `https://github.com/clomni/clomni-mobile-sdk.git`, sürüm 1.0.2, ürün `ClomniMessenger` | iOS 15, Xcode 15 |
| React Native | `@clomni/react-native` | React Native 0.75 |
| Flutter | `clomni_flutter` | Flutter 3.16, iOS 15, Android API 24 |
| Unity | `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.2` | Unity 2021.3, iOS 15, Android API 23 |

React Native, Flutter ve Unity arka planda yerel Android ve iOS SDK'larını kullanır. Bu yüzden bu kılavuzdaki her şey
tüm platformlarda aynı şekilde çalışır.

SDK, `https://app.clomni.ai/v1` adresiyle HTTPS üzerinden ve aynı sunucudaki bir WebSocket üzerinden konuşur. Şirket
ağınız veya bir MDM profili yalnızca listedeki sunuculara izin veriyorsa bu adresi listeye ekleyin.

## Adımlar

1. **Clomni panelinde** bir "Mobile app (App SDK)" gelen kutusu oluşturun. Bir App ID, her platform için bir API
   anahtarı ve bir Identity Secret alırsınız. Bkz. [Clomni paneli](01-panel.md).
2. **Sunucunuzda**, oturum açmış her kullanıcı için Identity Secret ile bir `user_hash` hesaplayın. Bkz.
   [Kullanıcıların tanınması](02-identity.md).
3. **Uygulamada** paketi ekleyin, açılışta `initialize` çağırın, kullanıcıyı oturuma alın ve Messenger'ı kendi
   düğmenizden açın. Platformunuzun bölümüne bakın:
   [Android](03-android.md), [iOS](04-ios.md), [React Native](05-react-native.md), [Flutter](06-flutter.md),
   [Unity](07-unity.md).
4. **Push bildirimleri**: Firebase ve APNs anahtarlarını panele yükleyin ([Push anahtarları](08-push-keys.md)) ve
   cihazın token'ını SDK'ya verin (platform bölümünüzdeki push kısmı).
5. **Kontrol edin**: paneldeki "Test push" ve **Overview** ile. Bir şey çalışmıyorsa
   [Sorun giderme](09-troubleshooting.md) bölümüne bakın.

## Anahtarlar

| Anahtar | Görünümü | Nerede durur |
|---|---|---|
| App ID | `app_…` | Uygulamada |
| Android API anahtarı | `android_…` | Android uygulamasında |
| iOS API anahtarı | `ios_…` | iOS uygulamasında |
| Identity Secret | uzun, rastgele bir dize | **Yalnızca sunucunuzda.** Asla uygulamada değil |

Bir API anahtarı tek bir platforma aittir: iOS anahtarı Android uygulamasında çalışmaz. React Native, Flutter ve
Unity uygulamaları, üzerinde çalıştıkları platformun anahtarını verir.

## Bu kılavuzda geçen terimler

- **Gelen kutusu (kanal)**: Clomni'deki tek bir uygulama. Mesajları, anahtarları ve ayarları bir arada durur.
- **Kaynak (source)**: Messenger'ı açarken verdiğiniz kısa bir ad, örneğin `profile_support`. Orada başlayan
  konuşmayla birlikte saklanır ve paneldeki istatistiklerde görünür.
- **Akış (flow)**: Clomni'nin akış oluşturucusunda kurulan otomatik bir konuşma: düğmeler, sorular, temsilciye
  aktarma.
- **Uygulama olayı (App event)**: uygulamanızın `startFlow` ile gönderdiği, `ride_problem` gibi bir ad. Bu olaya
  bağlı, yayınlanmış bir akış o konu hakkında bir konuşma başlatır.
