# Push anahtarları

Clomni push bildirimlerini sizin anahtarlarınızla gönderir: Android için bir Firebase service account, iOS için bir
APNs anahtarı. İkisi de gelen kutusunun ayarlar sütununda **Push** bölümüne (veya sihirbazın 4. adımında) yüklenir.

| Platform | Panelin ihtiyacı | Nereden alınır |
|---|---|---|
| Android | Service account JSON | Firebase console → Project settings → Service accounts |
| iOS | `.p8` anahtarı, Key ID, Team ID, Bundle ID | Apple Developer → Certificates, Identifiers & Profiles → Keys |

## Android: Firebase service account JSON

> Panel `google-services.json`'u değil, **service account JSON** dosyasını ister. `google-services.json` uygulamaya
> girer ve yalnızca projeyi tanımlar. Service account JSON ise Clomni sunucusunun projeniz üzerinden mesaj
> göndermesini sağlayan özel bir anahtardır.

1. [Firebase console](https://console.firebase.google.com)'u açın ve uygulamanızın `google-services.json` dosyasının
   ait olduğu projeyi seçin. Push yalnızca iki dosya da aynı projeden geldiğinde çalışır.
2. "Project Overview"ın yanındaki dişliye tıklayın → **Project settings** → **Service accounts** sekmesi.
3. "Firebase Admin SDK" altında **Generate new private key**, ardından **Generate key** düğmesine basın. Bir JSON
   dosyası iner.

   > **Yol:** `Firebase console → ⚙ Project settings → Service accounts → Firebase Admin SDK → Generate new private key → Generate key`
   >
   > Belgeler: [firebase.google.com/docs/admin/setup](https://firebase.google.com/docs/admin/setup#initialize-sdk-non-google)

4. Clomni panelinde: gelen kutusu → **Push** → "Android · Firebase Cloud Messaging" → **Service account JSON file**
   (1) ve indirilen dosyayı seçin. Kartta ardından projenin adı ve yükleme tarihi görünür.

   ![Clomni paneli: service account JSON yükleme](../images/panel-push-fcm-en.png)

Dosyayı bir parola gibi saklayın: commit etmeyin, e-postayla göndermeyin. Sızarsa anahtarı Google Cloud Console'da
silin (IAM → Service accounts → Keys) ve yenisini yükleyin.

Firebase Cloud Messaging API (V1) yeni Firebase projelerinde varsayılan olarak açıktır. Kapatılmışsa Test push,
FCM'den gelen bir hata gösterir; API'yi Google Cloud Console → APIs & Services altında açın.

## iOS: APNs anahtarı

Apple Developer Program'da Account Holder veya Admin rolüne sahip olmanız gerekir.

### 1. Anahtarı oluşturun

1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** →
   **Keys** → **+** yolunu açın.

   > **Yol:** `developer.apple.com/account → Certificates, Identifiers & Profiles → Keys → +`
   >
   > **+** düğmesi **Keys** başlığının yanındadır.
   >
   > Belgeler: [developer.apple.com/help/account/keys/create-a-private-key](https://developer.apple.com/help/account/keys/create-a-private-key/)

2. Anahtara bir ad verin, **Apple Push Notifications service (APNs)** kutusunu işaretleyin ve **Configure**
   düğmesine basın.
3. **Environment: Sandbox & Production.** Bu seçim önemlidir:
   - Yalnızca Sandbox anahtarı Xcode'dan çalıştırılan build'lerde çalışır, ama TestFlight ve App Store'da başarısız
     olur.
   - Yalnızca Production anahtarı TestFlight ve App Store'da çalışır, ama Xcode'dan çalıştırılan build'lerde
     başarısız olur.
   - Her iki durumda da APNs `BadEnvironmentKeyInToken` yanıtını verir ve hiçbir push ulaşmaz.

   Anahtar kısıtlaması için **Team Scoped (All Topics)**, tek bir anahtarın ekibinizin tüm uygulamalarına hizmet
   etmesini sağlar.

   > **Yol:** `Keys → + → Key Name → Apple Push Notifications service (APNs) → Configure`
   >
   > **Environment: Sandbox & Production** ve **Key Restriction: Team Scoped (All Topics)** seçin, ardından **Save**.
   >
   > Belgeler: [developer.apple.com/help/account/keys/create-a-private-key](https://developer.apple.com/help/account/keys/create-a-private-key/)

4. **Save** → **Continue** → **Register**.

Apple ortam seçimini eklemeden önce oluşturulmuş anahtarlar her iki ortamda da çalışır. Ekibinizde böyle bir anahtar
ya da Sandbox & Production anahtarı zaten varsa onu Clomni için de kullanabilirsiniz.

### 2. İndirin ve kimlikleri not edin

1. Anahtarın sayfasında **Download** düğmesine basın. `.p8` dosyası **yalnızca bir kez** indirilebilir. Güvenli bir
   yerde saklayın; kaybolursa yeni bir anahtar oluşturun.
2. Aynı sayfada gösterilen **Key ID**'yi not edin (10 karakter).

   > **Yol:** `Certificates, Identifiers & Profiles → Keys → anahtarınız → Download`
   >
   > **Key ID**, anahtarın adının altında gösterilir. **Download** sayfanın sağ üstündedir.
   >
   > Belgeler: [developer.apple.com/help/account/keys/get-a-key-identifier](https://developer.apple.com/help/account/keys/get-a-key-identifier/), [developer.apple.com/help/account/keys/revoke-edit-and-download-keys](https://developer.apple.com/help/account/keys/revoke-edit-and-download-keys/)

3. **Team ID**'yi bulun: Apple Developer → **Membership details** (10 karakter).

   > **Yol:** `developer.apple.com/account → Membership details → Team ID`
   >
   > Belgeler: [developer.apple.com/help/account/basics/account-landing-page](https://developer.apple.com/help/account/basics/account-landing-page/)

4. **Bundle ID**, uygulamanızın Bundle Identifier değeridir (Xcode → target → Signing & Capabilities), örneğin
   `com.example.app`.

### 3. Clomni'ye yükleyin

Gelen kutusu → **Push** → "iOS · Apple Push Notification service":

![Clomni paneli: APNs anahtarını yükleme](../images/panel-push-apns-en.png)

1. **.p8 file**: indirilen `AuthKey_XXXXXXXXXX.p8` dosyasını seçin.
2. **Key ID**.
3. **Team ID**.
4. **Bundle ID**.
5. **Upload**.

Panel biçimleri kontrol eder (Key ID ve Team ID 10 harf veya rakamdan oluşur). Apple'ın anahtarı kabul edip
etmediği ilk push'ta anlaşılır: Test push kullanın.

## Test push

Uygulama bildirimlere izin verilmiş bir telefonda çalışıp token'ını ilettikten sonra cihaz, **Push** bölümündeki
**Test push** listesinde görünür. Cihazı seçin ve **Send** düğmesine basın. Yanıt doğrudan FCM'in veya APNs'in
yanıtıdır.

| Yanıt | Anlamı | Ne yapmalı |
|---|---|---|
| Sent | Bildirim yolda | Hiçbir şey görünmüyorsa uygulamanın push kodunu kontrol edin |
| `BadEnvironmentKeyInToken` (APNs) | Anahtar diğer ortamla sınırlı | Sandbox & Production anahtarı oluşturun |
| `InvalidProviderToken` (APNs) | Key ID veya Team ID yanlış ya da anahtar iptal edilmiş | İki kimliği de kontrol edin; anahtarı yeniden yükleyin |
| `DeviceTokenNotForTopic` (APNs) | Bundle ID uygulamayla eşleşmiyor | Uygulamanın Bundle ID'sini girin |
| `BadDeviceToken` (APNs) | Token başka bir uygulamaya ait ya da artık geçerli değil | Uygulamayı yeniden kurun, açın, bildirimlere izin verin |
| `SENDER_ID_MISMATCH` (FCM) | Service account, `google-services.json`'dan farklı bir Firebase projesine ait | Uygulamanın projesine ait service account'u yükleyin |
| `UNREGISTERED` (FCM) | Uygulama cihazdan kaldırılmış ya da token'ın süresi dolmuş | Yeni token göndermesi için uygulamayı yeniden açın |
| Not sent: no key | O platform için yüklenmiş anahtar yok | Anahtarı yükleyin |

APNs'in veya FCM'in ölü olarak bildirdiği token'ı Clomni siler. **Push** bölümündeki "Removed tokens" sütunu
bunları sayar.
