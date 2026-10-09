# iOS

## Требования

- iOS 15 или новее, Xcode 15 или новее.
- App ID и API-ключ iOS (`ios_…`) из раздела **Installation** в колонке настроек канала.
- Для push: аккаунт Apple Developer и ключ APNs ([Ключи для push](08-push-keys.md)).

## Установка

### Swift Package Manager

В Xcode: **File → Add Package Dependencies**, введите `https://github.com/clomni/clomni-mobile-sdk.git`, выберите
правило «Up to Next Major Version» от `1.0.0` и добавьте продукт `ClomniMessenger` в таргет приложения.

В `Package.swift`:

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

SDK не опубликован в CocoaPods trunk. Проект на CocoaPods берёт pod по тегу репозитория:

```ruby
# Podfile, в таргете приложения
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
```

### Info.plist

Пользователи могут отправлять в диалог фотографии. Добавьте два текста, которые iOS показывает при запросе доступа:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Чтобы отправлять фото в поддержку</string>
<key>NSCameraUsageDescription</key>
<string>Чтобы снимать и отправлять фото в поддержку</string>
```

## Инициализация

Вызовите `initialize` один раз при запуске приложения.

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

SwiftUI: подключите к приложению `AppDelegate` через `@UIApplicationDelegateAdaptor`. Для push он всё равно нужен.

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

Любой метод `Clomni` можно вызывать из любого потока. Колбэки приходят в главном потоке. Повторный `initialize`
игнорируется.

## Пользователь

```swift
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: hashFromYourServer)   // хеш от вашего сервера

Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])

// Вместе с выходом из вашего приложения:
Clomni.logout()
```

О хеше — в главе [Идентификация пользователей](02-identity.md).

## Открытие Messenger

```swift
// SwiftUI
Button("Поддержка") { Clomni.present(source: "profile_support") }

// UIKit
@objc private func supportTapped() {
    Clomni.present(source: "profile_support")
}
```

| Вызов | Что делает |
|---|---|
| `Clomni.present(source:)` | Открывает главный экран |
| `Clomni.presentNewConversation(source:)` | Сразу открывает новый диалог |
| `Clomni.presentConversation(_:)` | Открывает известный диалог; ID приходит из `onConversationStarted` |
| `Clomni.dismiss()` | Закрывает Messenger из кода |

Messenger показывается поверх верхнего экрана приложения. Вызывайте `present`, когда экран уже виден, а не в
`didFinishLaunching`.

### Счётчик непрочитанных

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
                Text("Поддержка")
                Spacer()
                if unread > 0 { Text("\(unread)").foregroundStyle(.red) }
            }
        }
        .onAppear { token = Clomni.addUnreadCountListener { count in unread = count } }
        .onDisappear { if let token { Clomni.removeUnreadCountListener(token) } }
    }
}
```

Слушатель сразу получает текущее значение, а затем каждое изменение.

### Плавающая кнопка (необязательно)

По умолчанию выключена. Её можно включить в панели; значение из кода важнее. `setBottomPadding` поднимает её над
tab bar, в пунктах.

```swift
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

## Сценарии, запускаемые приложением

Соберите в панели сценарий с триггером «App event» и именем события, опубликуйте его, затем:

```swift
Clomni.startFlow("ride_problem", data: ["ride_id": "R-1923"], openMessenger: true, source: "ride_screen")
```

Тексты сценария могут использовать данные как `{{data.ride_id}}`. Если к событию не привязан опубликованный
сценарий, ничего не происходит. Для события, которое пользователь не вызывал сам, оставьте `openMessenger: false`.

## События

```swift
Clomni.onMessengerOpened = { source in print("opened from \(source ?? "-")") }
Clomni.onMessengerClosed = { print("closed") }
Clomni.onConversationStarted = { id in print("conversation \(id)") }
Clomni.onFlowCompleted = { flowId in print("flow \(flowId) completed") }
Clomni.onUnreadCountChanged = { count in print("unread \(count)") }
```

У каждого события один слушатель; `nil` удаляет его.

## Ссылки

Кнопка новости может содержать веб-адрес или deep link вашего приложения. Если задан `onLink`, каждая ссылка приходит
в приложение, и открывает её приложение. Если нет — ссылки открывает система.

```swift
Clomni.onLink = { url in
    if url.scheme == "example" {
        // навигация внутри приложения
    } else {
        UIApplication.shared.open(url)
    }
}
```

## Язык, звуки и оформление

```swift
Clomni.setLanguage("en")          // az, en или ru; nil — как на телефоне
Clomni.setSoundsEnabled(false)
Clomni.setTheme(primaryColor: "#0A66C2", typeface: "Montserrat", mode: .dark)
```

- `setLanguage` выбирает один из языков, включённых в панели. `nil` или выключенный язык — и Messenger берёт язык
  телефона, а затем основной язык панели.
- `setTheme`: цвет — `#RRGGBB`, режим — `.light`, `.dark` или `.system`. Каждый вызов заменяет предыдущий;
  неуказанное значение остаётся из панели.
- Шрифт — это имя семейства шрифта из бандла приложения, указанного в `UIAppFonts` в `Info.plist`
  (`Montserrat-Regular.ttf` → `"Montserrat"`). Текст по-прежнему учитывает Dynamic Type. Только для шрифта:
  `Clomni.setTypeface("Montserrat")`.

## Push-уведомления

Clomni отправляет push для iOS напрямую в APNs с вашим ключом `.p8`. Firebase на iOS не участвует.

Понадобятся:

1. Ключ APNs, загруженный в панель ([Ключи для push](08-push-keys.md)). Ключ должен быть создан для
   **Sandbox & Production**.
2. Capability Push Notifications в приложении.
3. Код ниже.

### 1. Capability

В Xcode: выберите таргет приложения → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.

> **Путь:** `Xcode → Project navigator → проект → TARGETS → приложение → Signing & Capabilities → + Capability → Push Notifications`
>
> Конфигурация: **All**. Дважды щёлкните **Push Notifications** в библиотеке; capability появится под разделом
> **Signing**.
>
> Документация: [developer.apple.com/documentation/xcode/adding-capabilities-to-your-app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app#Add-a-capability)

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

    // Push при открытом приложении. Пока открыт Messenger, push от Clomni не показываются.
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // Нажатие на уведомление: push от Clomni открывает свой диалог.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // собственный push приложения
    }
}
```

- Оставьте оба метода делегата `@MainActor`, а не `nonisolated`. Система может вызвать их из фоновой очереди, а
  Swift вызывает системный completion handler там, где метод завершился. Если это произошло не в главном потоке,
  UIKit остановит приложение с ошибкой «Call must be made on main thread».
- Запрашивайте разрешение на уведомления в подходящий для пользователей момент. В примере запрос при запуске — ради
  краткости.
- `Clomni.isClomniPush(userInfo)` отличает push от Clomni от ваших собственных, не обрабатывая его.

### 3. Sandbox и production

SDK сам сообщает окружение APNs каждого устройства:

| Как установлено приложение | Окружение APNs |
|---|---|
| Запуск из Xcode (development-профиль) | sandbox |
| TestFlight, App Store, Ad Hoc | production |

Один ключ `.p8` обслуживает оба окружения, если он создан для **Sandbox & Production**. Ключ, ограниченный одним
окружением, в другом выдаёт `BadEnvironmentKeyInToken`. Список Test push в панели показывает окружение каждого
устройства.

### 4. Фото оператора (необязательно)

Без дополнительных шагов уведомление Clomni показывает заголовок («Leyla · Example») и текст. Notification Service
Extension добавляет фото оператора.

1. В Xcode: **File → New → Target → Notification Service Extension**. Deployment target — iOS 15 или новее.

   > **Путь:** `Xcode → File → New → Target… → iOS → Notification Service Extension → Next → Product Name → Finish`
   >
   > Документация: [developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)

2. Замените сгенерированный `NotificationService.swift` файлом ниже. Расширению не нужен Clomni SDK.
3. Если в приложении уже есть Notification Service Extension, оставьте его и добавьте ветку для Clomni: push с
   `"clomni": "1"` и `avatar_url`.

Clomni отправляет каждый push с `mutable-content: 1`, больше ничего не нужно.

```swift
// NotificationService.swift, в таргете расширения
import Foundation
import UserNotifications

/// Добавляет фото оператора в уведомления Clomni. Clomni отправляет push с `mutable-content: 1` и `avatar_url`,
/// поэтому расширение успевает скачать фото до того, как iOS покажет уведомление. Остальные push проходят без
/// изменений, как и push от Clomni, фото для которого не пришло вовремя: текст никогда его не ждёт.
///
/// Использует только Foundation и UserNotifications; расширение не подключает Clomni SDK. Состояние защищено
/// блокировкой: загрузка завершается в очереди URLSession, а срок — в другой.
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
            // Скачанный файл удаляется, когда замыкание завершится, поэтому сначала его перемещаем.
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

    /// Системный срок (около 30 секунд) на исходе: уведомление уходит без фото.
    override func serviceExtensionTimeWillExpire() {
        lock.lock()
        let download = self.download
        lock.unlock()
        download?.cancel()
        finish(with: nil)
    }

    /// Отдаёт уведомление iOS один раз — по тому, что наступит раньше: загрузка или срок.
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

    /// iOS распознаёт вложение-картинку по расширению файла: JPEG, PNG или GIF.
    private static func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let types = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"]
        let fromPath = response?.url?.pathExtension.lowercased()
        guard let ext = response?.mimeType.flatMap({ types[$0] })
                ?? (["jpg", "jpeg", "png", "gif"].contains(fromPath ?? "") ? fromPath : nil) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            // iOS переносит файл в своё хранилище; удалять его потом не нам.
            return try UNNotificationAttachment(identifier: "avatar", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }
}
```

### Проверка

1. Запустите приложение на реальном iPhone (симулятор не получает APNs-push от Clomni), разрешите уведомления и один
   раз откройте Messenger.
2. В панели: **Push** в колонке настроек → **Test push** → выберите устройство → **Send**.

## Проблемы

| Симптом | Что делать |
|---|---|
| `api_key səhvdir və ya bu platforma üçün deyil` | Используйте ключ `ios_…`, а не ключ Android |
| Messenger не открывается, в логе `no window to present the messenger from yet` | Вызывайте `present` после того, как экран показан |
| `font family "…" is not in the app; the system font stays` | Добавьте файл шрифта в таргет и в `UIAppFonts` |
| Test push отвечает `BadEnvironmentKeyInToken` | Ключ APNs ограничен одним окружением. Создайте ключ для Sandbox & Production ([Ключи для push](08-push-keys.md)) |
| Test push отвечает `DeviceTokenNotForTopic` | Bundle ID в разделе **Push** не совпадает с Bundle ID приложения |
| В списке Test push нет устройства | На телефоне не разрешены уведомления или `setDeviceToken` не вызывается |
| Приложение падает при нажатии на уведомление с «Call must be made on main thread» | Пометьте методы делегата `@MainActor`, как выше |

Логи — в консоли Xcode и в Console.app: subsystem `ai.clomni.messenger`, category `Clomni`. Подробнее — в главе
[Решение проблем](09-troubleshooting.md).
