# Sorun giderme

## Önce nereye bakmalı

1. **Panelin Overview bölümü.** Her platformun bağlanıp bağlanmadığını, push'un etkin olup olmadığını ve "yanlış
   hash yüzünden reddedilen oturum açmalar" veya "push kurulmamış" gibi uyarıları gösterir; her uyarının bir **Fix**
   düğmesi vardır.
2. **SDK'nın logu.** Geliştirme sırasında debug düzeyini açın. Varsayılan düzey `warning`'dir; entegrasyon hataları
   `error` olarak loglanır.

| Platform | Nasıl açılır | Log nerede |
|---|---|---|
| Android | `Clomni.setLogLevel(ClomniLogLevel.DEBUG)` | logcat, etiket `Clomni` |
| iOS | `Clomni.setLogLevel(.debug)` | Xcode konsolu ve Console.app: subsystem `ai.clomni.messenger`, category `Clomni` |
| React Native | `Clomni.setLogLevel('debug')` | yukarıdaki yerel loglar |
| Flutter | `await Clomni.setLogLevel(ClomniLogLevel.debug)` | yukarıdaki yerel loglar; Dart tarafındaki hatalar `[Clomni]` ile başlar |
| Unity | `Clomni.SetLogLevel(ClomniLogLevel.Debug)` | yukarıdaki yerel loglar |

Sunucunun bazı mesajları Azerbaycancadır; aşağıdaki tabloda tam olarak göründükleri gibi verilmiştir.

## Kurulum

| Log veya belirti | Neden | Ne yapmalı |
|---|---|---|
| `call Clomni.initialize first` | Bir metot `initialize`'dan önce çağrıldı | `initialize`'ı açılışta çağırın; Android'de `Application.onCreate` içinde |
| `initialize was called before; the first call stays` | `initialize` iki kez çağrıldı | Bir kez çağırın. Anahtarları değiştirmek için uygulamayı yeniden başlatın |
| `api_key səhvdir və ya bu platforma üçün deyil` | API anahtarı yanlış, iptal edilmiş, yenisi oluşturulalı 7 günden fazla olmuş ya da diğer platformun anahtarı | Android'de `android_…`, iOS'ta `ios_…` anahtarı. Anahtarı **Installation** bölümünde kontrol edin |
| Android 1.0.1+: `api_key səhvdir ... Tətbiqin paket adı: …` | Uygulamanın paket adı (`applicationIdSuffix` dahil) gelen kutusunun Android paket adıyla aynı değil | Logdaki paket adını paneldekiyle karşılaştırın, bkz. [Sürümler](10-versions.md) |
| `this App SDK inbox is switched off in Clomni` | Gelen kutusu panelde kapatılmış | Açın. O zamana kadar `present()` hiçbir şey yapmaz |
| Hiçbir şey açılmıyor, logda da bir şey yok | Log düzeyi çok düşük ya da çağrı Unity Editor'de yapılıyor | Debug düzeyini açın; bir cihazda test edin |
| `setTheme: primaryColor "…" is not #RRGGBB` | Renk biçimi | `#` ile altı hex rakam, örneğin `#0A66C2` |
| iOS: `no window to present the messenger from yet` | `present`, henüz bir ekran yokken çağrıldı | Bir düğmeden ya da bir ekran gösterildikten sonra çağırın |
| iOS: `font family "…" is not in the app; the system font stays` | Yazı tipi pakette yok | Target'a ve `UIAppFonts`'a ekleyin |
| Uygulama şirket ağında sunucuya ulaşamıyor | Bir proxy veya izin listesi sunucuyu engelliyor | `app.clomni.ai` adresine izin verin (HTTPS ve WebSocket) |

## Kullanıcılar

| Log veya belirti | Neden | Ne yapmalı |
|---|---|---|
| `user_hash səhvdir. identity_secret və user_id-ni yoxlayın` | Hash eşleşmiyor | `loginUser`'dakiyle aynı `user_id` dizesi, küçük harfli hex, güncel secret. `userId` yoksa, kırpılmış ve küçük harfe çevrilmiş e-posta. Security → Test a hash ile kontrol edin |
| `403 identity_verification_failed` | Enforced mod ve hash yok ya da yanlış | Hash'i gönderin ya da tüm uygulama sürümleri gönderene kadar Recommended'a geri dönün |
| Telefonun sonraki kullanıcısı önceki kullanıcının konuşmalarını görüyor | `logout` çağrılmıyor | `Clomni.logout()`'u uygulamanızın kendi oturum kapatma işlemiyle birlikte çağırın |
| Temsilciler kullanıcının adını veya e-postasını görmüyor | `loginUser` bu alanlar olmadan ya da sizin oturum açma işleminiz bitmeden çağrılıyor | Alanları verin; sonraki değişiklikler için `updateUser` kullanın |

## Akışlar, görünüm ve metinler

| Belirti | Neden | Ne yapmalı |
|---|---|---|
| `startFlow` hiçbir şey yapmıyor | Olaya bağlı yayınlanmış bir akış yok | Akış oluşturucuda: "App event" tetikleyicisi, aynı ad, yayınlanmış. **Flows** bölümü olayın adını gösterir |
| Akışın metninde `{{data.…}}` boş kalıyor | `startFlow` verisindeki anahtarın adı farklı | Uygulamada ve akışta aynı anahtarı kullanın |
| Paneldeki bir değişiklik uygulamada görünmüyor | Appearance taslağı yayınlanmamış | Appearance → **Publish** |
| Messenger beklenenden farklı bir dilde konuşuyor | `setLanguage` kapalı bir dil seçmiş ya da hiç dil seçilmemiş | Dili Appearance → Languages altında açın ya da `setLanguage` çağırın |
| Yüzen düğme görünmüyor | Hem panelde hem kodda kapalı | `setLauncherVisible(true)` ya da Appearance → Theme altında açın |
| Flutter, Android: yüzen düğme görünmüyor | `MainActivity`, `FlutterActivity`'den türüyor | `FlutterFragmentActivity`'den türetin |

## Push bildirimleri

Ayarlar sütununda **Push** → **Test push** ile başlayın. Oradaki yanıt doğrudan FCM'in veya APNs'in yanıtıdır;
[Push anahtarları](08-push-keys.md#test-push) bölümündeki tablo her yanıtı açıklar.

| Belirti | Neden | Ne yapmalı |
|---|---|---|
| Cihaz Test push listesinde yok | Clomni'ye hiçbir token ulaşmadı | Telefonda bildirimlere izin verin; `setDeviceToken` çağrısını kontrol edin; Messenger'ı bir kez açın |
| Android: bildirim yok, `notification not shown (POST_NOTIFICATIONS?)` | Android 13+ üzerinde izin yok | `POST_NOTIFICATIONS` iznini isteyin |
| Android: `push token not registered: …` | Token sunucuya ulaşmadı | Ağı ve `setDeviceToken` çağrısını kontrol edin |
| Android: bildirimler yalnızca uygulama açıkken geliyor | Data mesajı yalnızca arayüzde işleniyor | Mesajı `FirebaseMessagingService` içinde `ClomniPush.handle`'a verin (React Native: `setBackgroundMessageHandler`, Flutter: `onBackgroundMessage`) |
| Android: simge yerine gri bir kare | Uygulama simgesi siluet değil | Beyaz bir simgeyle `setNotificationIcon` |
| Android: `SENDER_ID_MISMATCH` | Service account ve `google-services.json` farklı Firebase projelerine ait | Uygulamanın projesine ait service account'u yükleyin |
| iOS: `BadEnvironmentKeyInToken` | APNs anahtarı tek bir ortamla sınırlı | Sandbox & Production için bir anahtar oluşturun |
| iOS: `InvalidProviderToken` | Key ID veya Team ID yanlış ya da anahtar iptal edilmiş | İki kimliği de kontrol edin; anahtarı yeniden yükleyin |
| iOS: `DeviceTokenNotForTopic` | **Push** bölümündeki Bundle ID uygulamanınki değil | Uygulamanın Bundle ID'sini girin |
| iOS: Xcode'dan çalışıyor, TestFlight'tan çalışmıyor (ya da tersi) | Anahtar yalnızca tek bir ortamı kapsıyor | Sandbox & Production anahtarı |
| iOS: bir Clomni bildirimine dokunmak yalnızca uygulamayı açıyor | Dokunma `handlePush`'a ulaşmıyor | Yerel iOS: AppDelegate'teki delegate. React Native ve Flutter: kendi bölümlerindeki yerel delegate; Firebase kütüphaneleri iOS'ta Clomni push'larını görmez |
| iOS: dokununca uygulama "Call must be made on main thread" ile çöküyor | Async delegate metodu `nonisolated` | `@MainActor` olarak işaretleyin |
| Messenger açıkken bir Clomni bildirimi görünüyor | `shouldShowForeground` kullanılmıyor | false olduğunda hiçbir gösterim seçeneği döndürmeyin |

## Değişiklikten sonra anahtarlar

- Yeni bir API anahtarı: eskisi 7 gün daha çalışır. Bu sürenin sonunda eski anahtarı taşıyan uygulama sürümleri
  bağlanamaz.
- İptal edilen bir API anahtarı hemen durur.
- Yeni bir Identity Secret: eskisi 7 gün daha çalışır. Test a hash, bir hash'in hangi secret ile üretildiğini söyler.
- Yeni bir push anahtarı: **Push** bölümüne yükleyin; sonraki push onu kullanır.

## Yardım isteme

Clomni desteğine şunlarla yazın:

- platform ve SDK sürümü (Kotlin ve Swift'te `Clomni.version`);
- App ID (asla Identity Secret veya tam bir API anahtarı değil);
- **Overview**'un söyledikleri ve sorun anında debug düzeyindeki SDK logu;
- push için: Test push'un yanıtı.
