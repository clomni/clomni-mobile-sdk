# iOS

## Gereksinimler

- iOS 15 veya daha yenisi, Xcode 15 veya daha yenisi.
- Gelen kutusunun ayarlar sütununda **Installation** bölümünden App ID ve iOS API anahtarı (`ios_…`).
- Push için: bir Apple Developer hesabı ve bir APNs anahtarı ([Push anahtarları](08-push-keys.md)).

## Kurulum

### Swift Package Manager

Xcode'da: **File → Add Package Dependencies**, `https://github.com/clomni/clomni-mobile-sdk.git` adresini girin,
`1.0.0`'dan itibaren "Up to Next Major Version" kuralını seçin ve `ClomniMessenger` ürününü uygulama hedefinize
ekleyin.

Bir `Package.swift` içinde:

```swift
dependencies: [
    .package(url: "https://github.com/clomni/clomni-mobile-sdk.git", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "ClomniMessenger", package: "clomni-mobile-sdk"),
    ]),
]
```

### CocoaPods

SDK, CocoaPods trunk'ta yayınlanmaz. Bir CocoaPods projesi pod'u deponun etiketinden alır:

```ruby
# Podfile, uygulamanın target'ı içinde
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
```

### Info.plist

Kullanıcılar konuşmada fotoğraf gönderebilir. iOS'un erişim isterken gösterdiği iki metni ekleyin:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Destek ekibine fotoğraf göndermek için</string>
<key>NSCameraUsageDescription</key>
<string>Fotoğraf çekip destek ekibine göndermek için</string>
```

## Başlatma

`initialize`'ı uygulama açılırken bir kez çağırın.

UIKit:

```swift
import ClomniMessenger
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_…", apiKey: "ios_…")
        #if DEBUG
        Clomni.setLogLevel(.debug)
        #endif
        return true
    }
}
```

SwiftUI: uygulamaya `@UIApplicationDelegateAdaptor` ile bir `AppDelegate` verin. Push için zaten gereklidir.

```swift
import SwiftUI

@main
struct ExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`Clomni`'nin tüm metotları herhangi bir thread'den çağrılabilir. Callback'ler ana thread'de gelir. İkinci bir
`initialize` çağrısı yok sayılır.

## Kullanıcı

```swift
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: hashFromYourServer)   // sunucunuzdan gelen hash

Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])

// Uygulamanın kendi oturum kapatma işlemiyle birlikte:
Clomni.logout()
```

Hash için bkz. [Kullanıcıların tanınması](02-identity.md).

## Messenger'ı açma

```swift
// SwiftUI
Button("Destek") { Clomni.present(source: "profile_support") }

// UIKit
@objc private func supportTapped() {
    Clomni.present(source: "profile_support")
}
```

| Çağrı | Ne yapar |
|---|---|
| `Clomni.present(source:)` | Ana sayfayı açar |
| `Clomni.presentNewConversation(source:)` | Doğrudan yeni bir konuşma açar |
| `Clomni.presentConversation(_:)` | Bilinen bir konuşmayı açar; ID `onConversationStarted`'dan gelir |
| `Clomni.dismiss()` | Messenger'ı koddan kapatır |

Messenger, uygulamanın en üstteki ekranının üzerinde açılır. `present`'i bir ekran görünür olduktan sonra çağırın,
`didFinishLaunching` içinde değil.

### Okunmamış sayısı

```swift
import ClomniMessenger
import SwiftUI

struct SupportRow: View {
    @State private var unread = 0
    @State private var token: UUID?

    var body: some View {
        Button {
            Clomni.present(source: "profile_support")
        } label: {
            HStack {
                Text("Destek")
                Spacer()
                if unread > 0 { Text("\(unread)").foregroundStyle(.red) }
            }
        }
        .onAppear { token = Clomni.addUnreadCountListener { count in unread = count } }
        .onDisappear { if let token { Clomni.removeUnreadCountListener(token) } }
    }
}
```

Dinleyici güncel sayıyı hemen, sonra her değişikliği alır.

### Yüzen düğme (isteğe bağlı)

Varsayılan olarak kapalıdır. Panel onu açabilir; kodda verilen değer önceliklidir. `setBottomPadding` düğmeyi tab
bar'ın üstüne kaldırır, point cinsinden.

```swift
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Uygulamanın başlattığı akışlar

Panelde "App event" tetikleyicisi ve olay adıyla bir akış kurup yayınlayın, ardından:

```swift
Clomni.startFlow("ride_problem", data: ["ride_id": "R-1923"], openMessenger: true, source: "ride_screen")
```

Akışın metinleri veriyi `{{data.ride_id}}` biçiminde kullanabilir. Olaya bağlı yayınlanmış bir akış yoksa hiçbir şey
olmaz. Kullanıcının dokunmadığı bir olay için `openMessenger: false` bırakın.

## Olaylar

```swift
Clomni.onMessengerOpened = { source in print("opened from \(source ?? "-")") }
Clomni.onMessengerClosed = { print("closed") }
Clomni.onConversationStarted = { id in print("conversation \(id)") }
Clomni.onFlowCompleted = { flowId in print("flow \(flowId) completed") }
Clomni.onUnreadCountChanged = { count in print("unread \(count)") }
```

Her olayın tek bir dinleyicisi vardır; `nil` dinleyiciyi kaldırır.

## Bağlantılar

Bir haberin düğmesi bir web adresi veya uygulamanızın deep link'ini taşıyabilir. `onLink` atanmışsa her bağlantı
uygulamanıza gelir ve onu uygulama açar. Atanmamışsa bağlantıları sistem açar.

```swift
Clomni.onLink = { url in
    if url.scheme == "example" {
        // uygulamanın içinde yönlendirin
    } else {
        UIApplication.shared.open(url)
    }
}
```

## Dil, sesler ve görünüm

```swift
Clomni.setLanguage("en")          // az, en veya ru; nil telefona uyar
Clomni.setSoundsEnabled(false)
Clomni.setTheme(primaryColor: "#0A66C2", typeface: "Montserrat", mode: .dark)
```

- `setLanguage`, panelde açılmış dillerden birini seçer. `nil` ya da kapalı bir dil telefona, ardından panelin ana
  diline uyar.
- `setTheme`: renk `#RRGGBB`, mod `.light`, `.dark` veya `.system`. Her çağrı öncekinin yerine geçer; verilmeyen
  değer panelinki olarak kalır.
- Yazı tipi, uygulama paketindeki ve `Info.plist`'te `UIAppFonts` altında listelenen bir yazı tipinin aile adıdır
  (`Montserrat-Regular.ttf` → `"Montserrat"`). Metin Dynamic Type'a uymaya devam eder. Yalnızca yazı tipi için:
  `Clomni.setTypeface("Montserrat")`.

## Push bildirimleri

Clomni, iOS push'larını `.p8` anahtarınızla doğrudan APNs'e gönderir. iOS'ta Firebase devreye girmez.

Gerekenler:

1. Panele yüklenmiş bir APNs anahtarı ([Push anahtarları](08-push-keys.md)). Anahtar **Sandbox & Production** için
   oluşturulmuş olmalıdır.
2. Uygulamada Push Notifications capability'si.
3. Aşağıdaki kod.

### 1. Capability

Xcode'da: uygulama hedefini seçin → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.

> **Yol:** `Xcode → Project navigator → proje → TARGETS → uygulama → Signing & Capabilities → + Capability → Push Notifications`
>
> Yapılandırma: **All**. Kütüphanede **Push Notifications**'a çift tıklayın; **Signing** bölümünün altında görünür.
>
> Belgeler: [developer.apple.com/documentation/xcode/adding-capabilities-to-your-app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app#Add-a-capability)

### 2. AppDelegate

```swift
import ClomniMessenger
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_…", apiKey: "ios_…")
        UNUserNotificationCenter.current().delegate = self
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true { UIApplication.shared.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Clomni.setDeviceToken(deviceToken)
    }

    // Uygulama açıkken gelen push. Messenger açıkken Clomni push'ları gösterilmez.
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // Bildirime dokunma: Clomni push'u kendi konuşmasını açar.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // uygulamanın kendi push'u
    }
}
```

- İki delegate metodunu da `nonisolated` değil, `@MainActor` olarak bırakın. Sistem onları bir arka plan
  kuyruğundan çağırabilir ve Swift, sistemin completion handler'ını metodun bittiği yerde çağırır. Ana thread dışında
  biterse UIKit uygulamayı "Call must be made on main thread" hatasıyla durdurur.
- Bildirim iznini kullanıcılarınıza uygun bir anda isteyin. Örnek, kısalık için açılışta istiyor.
- `Clomni.isClomniPush(userInfo)`, bir Clomni push'unu işlemeden sizin push'larınızdan ayırt eder.

### 3. Sandbox ve production

SDK her cihazın APNs ortamını kendisi bildirir:

| Uygulama nasıl kuruldu | APNs ortamı |
|---|---|
| Xcode'dan çalıştırıldı (development profili) | sandbox |
| TestFlight, App Store, Ad Hoc | production |

Tek bir `.p8` anahtarı, **Sandbox & Production** için oluşturulduysa ikisine de hizmet eder. Tek bir ortamla
sınırlanmış anahtar diğerinde `BadEnvironmentKeyInToken` hatası verir. Paneldeki Test push listesi her cihazın
ortamını gösterir.

### 4. Temsilcinin fotoğrafı (isteğe bağlı)

Başka bir şey eklemeden Clomni bildirimi başlığı ("Leyla · Example") ve metni gösterir. Bir Notification Service
Extension temsilcinin fotoğrafını ekler.

1. Xcode'da: **File → New → Target → Notification Service Extension**. Deployment target iOS 15 veya daha yenisi.

   > **Yol:** `Xcode → File → New → Target… → iOS → Notification Service Extension → Next → Product Name → Finish`
   >
   > Belgeler: [developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)

2. Oluşturulan `NotificationService.swift` dosyasını aşağıdaki dosyayla değiştirin. Extension, Clomni SDK'ya ihtiyaç
   duymaz.
3. Uygulamada zaten bir Notification Service Extension varsa onu koruyun ve Clomni dalını ekleyin: `"clomni": "1"`
   ve `avatar_url` içeren push'lar.

Clomni her push'u `mutable-content: 1` ile gönderir; başka bir şey gerekmez.

```swift
// NotificationService.swift, extension target'ında
import Foundation
import UserNotifications

/// Clomni bildirimlerine temsilcinin fotoğrafını ekler. Clomni push'larını `mutable-content: 1` ve bir `avatar_url`
/// ile gönderir; bu sayede extension, iOS bildirimi göstermeden önce fotoğrafı indirebilir. Diğer push'lar olduğu
/// gibi geçer; fotoğrafı zamanında gelmeyen bir Clomni push'u da öyle: metin fotoğrafı hiçbir zaman beklemez.
///
/// Yalnızca Foundation ve UserNotifications kullanır; extension Clomni SDK'yı bağlamaz. Durumu bir kilit arkasındadır:
/// indirme URLSession'ın kuyruğunda, süre sınırı ise başka bir kuyrukta biter.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var download: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              content.userInfo["clomni"] as? String == "1",
              let avatar = (content.userInfo["avatar_url"] as? String).flatMap(URL.init(string:)),
              avatar.scheme == "https" else {
            return contentHandler(request.content)
        }
        let download = URLSession.shared.downloadTask(with: avatar) { [weak self] location, response, _ in
            // İndirilen dosya bu closure dönünce silinir, bu yüzden önce taşınır.
            let attachment = location.flatMap { NotificationService.attachment(from: $0, response: response) }
            self?.finish(with: attachment)
        }
        lock.lock()
        self.contentHandler = contentHandler
        self.content = content
        self.download = download
        lock.unlock()
        download.resume()
    }

    /// Sistemin süre sınırı (yaklaşık 30 saniye) yaklaştı: bildirim fotoğrafsız gider.
    override func serviceExtensionTimeWillExpire() {
        lock.lock()
        let download = self.download
        lock.unlock()
        download?.cancel()
        finish(with: nil)
    }

    /// Bildirimi iOS'a bir kez verir; indirme ile süre sınırından hangisi önce gelirse.
    private func finish(with attachment: UNNotificationAttachment?) {
        lock.lock()
        let handler = contentHandler
        let content = self.content
        contentHandler = nil
        lock.unlock()
        guard let handler, let content else { return }
        if let attachment { content.attachments = [attachment] }
        handler(content)
    }

    /// iOS bir görsel eki dosya uzantısından tanır: JPEG, PNG veya GIF.
    private static func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let types = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"]
        let fromPath = response?.url?.pathExtension.lowercased()
        guard let ext = response?.mimeType.flatMap({ types[$0] })
                ?? (["jpg", "jpeg", "png", "gif"].contains(fromPath ?? "") ? fromPath : nil) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            // iOS dosyayı kendi deposuna taşır; sonradan silmek bize düşmez.
            return try UNNotificationAttachment(identifier: "avatar", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }
}
```

### Test etme

1. Uygulamayı gerçek bir iPhone'da çalıştırın (simülatör Clomni'den APNs push'u alamaz), bildirimlere izin verin ve
   Messenger'ı bir kez açın.
2. Panelde: ayarlar sütununda **Push** → **Test push** → cihazı seçin → **Send**.

## Sorunlar

| Belirti | Ne yapmalı |
|---|---|
| `api_key səhvdir və ya bu platforma üçün deyil` | Android anahtarını değil, `ios_…` anahtarını kullanın |
| Messenger açılmıyor, logda `no window to present the messenger from yet` yazıyor | `present`'i bir ekran gösterildikten sonra çağırın |
| `font family "…" is not in the app; the system font stays` | Yazı tipi dosyasını target'a ve `UIAppFonts`'a ekleyin |
| Test push `BadEnvironmentKeyInToken` diyor | APNs anahtarı tek bir ortamla sınırlı. Sandbox & Production için bir anahtar oluşturun ([Push anahtarları](08-push-keys.md)) |
| Test push `DeviceTokenNotForTopic` diyor | **Push** bölümündeki Bundle ID uygulamanın Bundle ID'si değil |
| Test push listesinde cihaz yok | Telefonda bildirimlere izin verilmemiş ya da `setDeviceToken` hiç çağrılmıyor |
| Bildirime dokununca uygulama "Call must be made on main thread" ile çöküyor | Delegate metotlarını yukarıdaki gibi `@MainActor` olarak işaretleyin |

Loglar Xcode konsolunda ve Console.app'tedir: subsystem `ai.clomni.messenger`, category `Clomni`. Daha fazlası:
[Sorun giderme](09-troubleshooting.md).
