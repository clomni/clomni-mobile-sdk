#if canImport(UIKit) && !os(watchOS)
import UIKit

extension ClomniEngine {
    /// Closes the socket when the app goes to the background and opens it again in the foreground (brief 8 · 4).
    func observeApplicationState() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.applicationDidEnterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.applicationWillEnterForeground() }
            },
        ]
    }
}
#endif
