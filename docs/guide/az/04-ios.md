# iOS

## Tələblər

- iOS 15 və ya daha yeni, Xcode 15 və ya daha yeni.
- Paneldə kanalın ayarlar sütununun **Quraşdırma** bölməsindən App ID və iOS API açarı (`ios_…`).
- Push üçün: Apple Developer hesabı və APNs açarı ([Push açarları](08-push-keys.md)).

## Quraşdırma

### Swift Package Manager

Xcode-da: **File → Add Package Dependencies**, `https://github.com/clomni/clomni-mobile-sdk.git` ünvanını yazın,
`1.0.0`-dan "Up to Next Major Version" qaydasını seçin və `ClomniMessenger` məhsulunu tətbiq hədəfinə əlavə edin.

`Package.swift`-də:

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

SDK CocoaPods trunk-da yoxdur. CocoaPods layihəsi pod-u repozitoriyanın tag-indən götürür:

```ruby
# Podfile, tətbiqin target-ində
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
```

### Info.plist

İstifadəçilər söhbətdə şəkil göndərə bilir. iOS-un icazə istəyəndə göstərdiyi mətnləri əlavə edin:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Dəstəyə şəkil göndərmək üçün</string>
<key>NSCameraUsageDescription</key>
<string>Şəkil çəkib dəstəyə göndərmək üçün</string>
<key>NSMicrophoneUsageDescription</key>
<string>Dəstəyə səsli mesaj göndərmək üçün</string>
```

- `NSCameraUsageDescription` yoxdursa, Messenger kamera seçimini göstərmir.
- `NSMicrophoneUsageDescription` səsli mesaj üçündür, SDK 1.0.2-dən lazımdır.

## Başlatma

`initialize`-i tətbiq açılanda bir dəfə çağırın.

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

SwiftUI: tətbiqə `@UIApplicationDelegateAdaptor` ilə `AppDelegate` verin. Push üçün onsuz da lazımdır.

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

`Clomni`-nin hər metodunu istənilən thread-dən çağırmaq olar. Callback-lər əsas thread-də gəlir. İkinci
`initialize` nəzərə alınmır.

## İstifadəçi

```swift
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: hashFromYourServer)   // serverinizdən gələn hash

Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])

// Tətbiqin öz çıxışı ilə birlikdə:
Clomni.logout()
```

Hash üçün bax: [İstifadəçinin tanıdılması](02-identity.md).

Tətbiq hər açılanda, istifadəçi daxil olubsa, `loginUser`-i yenidən çağırın, istifadəçi təzə daxil olmuş kimi. Eyni
istifadəçi üçün SDK saxlanmış sessiyanı işlədir.

## Messenger-i açmaq

```swift
// SwiftUI
Button("Dəstək") { Clomni.present(source: "profile_support") }

// UIKit
@objc private func supportTapped() {
    Clomni.present(source: "profile_support")
}
```

| Çağırış | Nə edir |
|---|---|
| `Clomni.present(source:)` | Ana səhifəni açır |
| `Clomni.presentNewConversation(source:)` | Birbaşa yeni söhbət açır |
| `Clomni.presentConversation(_:)` | Məlum söhbəti açır; ID `onConversationStarted`-dən gəlir |
| `Clomni.dismiss()` | Messenger-i koddan bağlayır |

Messenger tətbiqin ən üstdəki ekranının üzərində açılır. `present`-i ekran görünəndən sonra çağırın,
`didFinishLaunching`-də yox.

### Oxunmamış mesajların sayı

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
                Text("Dəstək")
                Spacer()
                if unread > 0 { Text("\(unread)").foregroundStyle(.red) }
            }
        }
        .onAppear { token = Clomni.addUnreadCountListener { count in unread = count } }
        .onDisappear { if let token { Clomni.removeUnreadCountListener(token) } }
    }
}
```

Dinləyici cari sayı dərhal, sonra hər dəyişikliyi eşidir.

### Üzən düymə (istəyə bağlı)

Standart olaraq sönülüdür. Panel onu yandıra bilər, kodda verilən dəyər isə paneldən üstündür. `setBottomPadding`
düyməni tab bar-ın üstünə qaldırır, point ilə.

```swift
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Tətbiqin başlatdığı flow-lar

Paneldə "Tətbiq hadisəsi" trigger-i və hadisə adı ilə flow qurun, onu dərc edin, sonra:

```swift
Clomni.startFlow("ride_problem", data: ["ride_id": "R-1923"], openMessenger: true, source: "ride_screen")
```

Flow-un mətnləri datanı `{{data.ride_id}}` kimi işlədə bilər. Hadisəyə bağlı dərc olunmuş flow yoxdursa, heç nə baş
vermir. İstifadəçinin özünün basmadığı hadisə üçün `openMessenger: false` saxlayın.

**Hadisənin adı flow-un adı deyil.** `startFlow`-a paneldəki Flow-lar bölməsində flow-un altındakı "Hadisə: …"
sətrindəki adı verin. Flow "Tətbiq hadisəsi" trigger-i ilə qurulmalıdır: "Söhbət başlayanda" trigger-li flow `startFlow`
ilə başlamır.

## Hadisələr

```swift
Clomni.onMessengerOpened = { source in print("opened from \(source ?? "-")") }
Clomni.onMessengerClosed = { print("closed") }
Clomni.onConversationStarted = { id in print("conversation \(id)") }
Clomni.onFlowCompleted = { flowId in print("flow \(flowId) completed") }
Clomni.onUnreadCountChanged = { count in print("unread \(count)") }
```

Hər hadisənin bir dinləyicisi olur, `nil` onu silir.

## Linklər

Xəbərin düyməsində veb ünvanı və ya tətbiqinizin deep link-i ola bilər. `onLink` təyin olunubsa, hər link tətbiqinizə
gəlir və onu tətbiq açır. Təyin olunmayıbsa, linkləri sistem açır.

```swift
Clomni.onLink = { url in
    if url.scheme == "example" {
        // tətbiqin içində yönləndirin
    } else {
        UIApplication.shared.open(url)
    }
}
```

## Dil, səslər və görünüş

```swift
Clomni.setLanguage("en")          // az, en və ya ru; nil telefonun dilinə uyğunlaşır
Clomni.setSoundsEnabled(false)
Clomni.setTheme(primaryColor: "#0A66C2", typeface: "Montserrat", mode: .dark)
```

- `setLanguage` paneldə yandırılmış dillərdən birini seçir. `nil` və ya sönülü dil verilsə, telefonun dili, o da
  yoxdursa panelin əsas dili işlənir.
- `setTheme`: rəng `#RRGGBB`, rejim `.light`, `.dark` və ya `.system`. Hər çağırış əvvəlkini əvəz edir, verilməyən
  dəyər panelinki qalır.
- Şrift tətbiqin bundle-ındakı və `Info.plist`-də `UIAppFonts` altında yazılmış şriftin ailə adıdır
  (`Montserrat-Regular.ttf` → `"Montserrat"`). Mətn Dynamic Type-a yenə tabedir. Yalnız şrift üçün:
  `Clomni.setTypeface("Montserrat")`.

## Push bildirişləri

Clomni iOS push-larını `.p8` açarınızla birbaşa APNs-ə göndərir. iOS-da Firebase iştirak etmir.

Lazım olanlar:

1. Panelə yüklənmiş APNs açarı ([Push açarları](08-push-keys.md)). Açar **Sandbox & Production** üçün
   yaradılmalıdır.
2. Tətbiqdə Push Notifications capability-si.
3. Aşağıdakı kod.

### 1. Capability

Xcode-da: tətbiq hədəfini seçin → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.

> **Yol:** `Xcode → Project navigator → layihə → TARGETS → tətbiq → Signing & Capabilities → + Capability → Push Notifications`
>
> Konfiqurasiya: **All**. **Push Notifications**-u kitabxanada iki dəfə klikləyin, o, **Signing** bölməsinin altında görünür.
>
> Sənəd: [developer.apple.com/documentation/xcode/adding-capabilities-to-your-app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app#Add-a-capability)

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

    // Tətbiq açıq olanda gələn push. Messenger açıqdırsa, Clomni push-ları göstərilmir.
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // Bildirişə toxunuş: Clomni push-u öz söhbətini açır.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // tətbiqin öz push-u
    }
}
```

- Hər iki delegate metodunu `nonisolated` yox, `@MainActor` saxlayın. Sistem onları arxa planda olan queue-dan
  çağıra bilər, Swift isə sistemin completion handler-ini metodun bitdiyi yerdə çağırır. Əsas thread-dən kənarda
  bitəndə UIKit tətbiqi "Call must be made on main thread" xətası ilə dayandırır.
- Bildiriş icazəsini istifadəçilərinizə uyğun anda istəyin. Nümunə qısalıq üçün açılışda istəyir.
- `Clomni.isClomniPush(userInfo)` push-u emal etmədən onun Clomni-yə, yoxsa sizə aid olduğunu deyir.

### 3. Sandbox və production

SDK hər cihazın APNs mühitini özü bildirir:

| Tətbiq necə quraşdırılıb | APNs mühiti |
|---|---|
| Xcode-dan işə salınıb (development profili) | sandbox |
| TestFlight, App Store, Ad Hoc | production |

Bir `.p8` açarı hər ikisinə xidmət edir, bir şərtlə ki **Sandbox & Production** üçün yaradılsın. Bir mühitlə
məhdudlaşan açar o biri mühitdə `BadEnvironmentKeyInToken` xətası verir. Paneldəki Test bildirişi siyahısı hər cihazın
mühitini göstərir.

### 4. Operatorun şəkli (istəyə bağlı)

Əlavə heç nə etmədən Clomni bildirişi başlığı ("Leyla · Example") və mətni göstərir. Notification Service Extension
operatorun şəklini əlavə edir.

1. Xcode-da: **File → New → Target → Notification Service Extension**. Deployment target iOS 15 və ya daha yeni.

   > **Yol:** `Xcode → File → New → Target… → iOS → Notification Service Extension → Next → Product Name → Finish`
   >
   > Sənəd: [developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)

2. Yaranan `NotificationService.swift`-i aşağıdakı faylla əvəz edin. Extension-a Clomni SDK lazım deyil.
3. Tətbiqdə artıq Notification Service Extension varsa, onu saxlayın və Clomni qolunu əlavə edin: `"clomni": "1"`
   və `avatar_url` olan push-lar.

Clomni hər push-u `mutable-content: 1` ilə göndərir, başqa heç nə lazım deyil.

```swift
// NotificationService.swift, extension hədəfində
import Foundation
import UserNotifications

/// Puts the operator's photo on Clomni notifications. Clomni sends its pushes with `mutable-content: 1` and an
/// `avatar_url`, which lets this extension download the photo before iOS shows the notification. Other pushes pass
/// through unchanged, and so does a Clomni push whose photo does not arrive in time: the text never waits for it.
///
/// Uses Foundation and UserNotifications only; the extension does not link the Clomni SDK. Its state is behind a
/// lock: the download finishes on URLSession's queue, the deadline on another.
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
            // The downloaded file is deleted when this closure returns, so it is moved first.
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

    /// The system's deadline (about 30 seconds) is near: the notification goes out without the photo.
    override func serviceExtensionTimeWillExpire() {
        lock.lock()
        let download = self.download
        lock.unlock()
        download?.cancel()
        finish(with: nil)
    }

    /// Hands the notification to iOS once, whichever of the download and the deadline comes first.
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

    /// iOS recognises an image attachment by its file extension: JPEG, PNG or GIF.
    private static func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let types = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"]
        let fromPath = response?.url?.pathExtension.lowercased()
        guard let ext = response?.mimeType.flatMap({ types[$0] })
                ?? (["jpg", "jpeg", "png", "gif"].contains(fromPath ?? "") ? fromPath : nil) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            // iOS moves the file into its own store; it is not ours to delete afterwards.
            return try UNNotificationAttachment(identifier: "avatar", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }
}
```

### Yoxlama

1. Tətbiqi real iPhone-da işə salın (simulyator Clomni-dən APNs push-u qəbul edə bilmir), bildirişlərə icazə verin
   və Messenger-i bir dəfə açın.
2. Paneldə: ayarlar sütununda **Push** → **Test bildirişi** → cihazı seçin → **Göndər**.

## Problemlər

| Əlamət | Nə etməli |
|---|---|
| `api_key səhvdir və ya bu platforma üçün deyil` | Android açarını yox, `ios_…` açarını işlədin |
| Messenger açılmır, logda `no window to present the messenger from yet` | `present`-i ekran göstəriləndən sonra çağırın |
| `font family "…" is not in the app; the system font stays` | Şrift faylını hədəfə və `UIAppFonts`-a əlavə edin |
| Test bildirişi `BadEnvironmentKeyInToken` deyir | APNs açarı bir mühitlə məhdudlaşıb. Sandbox & Production açarı yaradın ([Push açarları](08-push-keys.md)) |
| Test bildirişi `DeviceTokenNotForTopic` deyir | **Push** bölməsindəki Bundle ID tətbiqin Bundle ID-si deyil |
| Test bildirişi siyahısında cihaz yoxdur | Telefonda bildirişlərə icazə verilməyib və ya `setDeviceToken` heç çağırılmır |
| Bildirişə toxunanda tətbiq "Call must be made on main thread" ilə dayanır | Delegate metodlarını yuxarıdakı kimi `@MainActor` edin |

Loglar Xcode konsolunda və Console.app-dədir: subsystem `ai.clomni.messenger`, category `Clomni`. Daha çoxu:
[Problemlərin həlli](09-troubleshooting.md).
