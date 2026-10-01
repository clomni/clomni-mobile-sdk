import Foundation
import UserNotifications

/// Puts the operator's photo on Clomni notifications. Clomni sends its pushes with `mutable-content: 1` and an
/// `avatar_url`, which lets this extension download the photo before iOS shows the notification. Other pushes pass
/// through unchanged, and so does a Clomni push whose photo does not arrive in time: the text never waits for it.
///
/// Uses Foundation and UserNotifications only; the extension does not link the Clomni SDK.
final class NotificationService: UNNotificationServiceExtension {
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
        self.contentHandler = contentHandler
        self.content = content
        let download = URLSession.shared.downloadTask(with: avatar) { [weak self] location, response, _ in
            // The downloaded file is deleted when this closure returns, so it is moved first.
            let attachment = location.flatMap { Self.attachment(from: $0, response: response) }
            self?.finish(with: attachment)
        }
        self.download = download
        download.resume()
    }

    /// The system's deadline (about 30 seconds) is near: the notification goes out without the photo.
    override func serviceExtensionTimeWillExpire() {
        download?.cancel()
        finish(with: nil)
    }

    /// Hands the notification to iOS once, whichever of the download and the deadline comes first.
    private func finish(with attachment: UNNotificationAttachment?) {
        lock.lock()
        let handler = contentHandler
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
