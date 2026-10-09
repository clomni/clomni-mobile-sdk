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

#if canImport(Network)
import Network
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

extension ClomniEngine {
    /// The phone's way to the network: when it comes back, what waits in the outbox goes at once (CM-087), not at the
    /// next try of its backoff, and the socket reconnects.
    func observeNetwork() {
        guard networkObserver == nil else { return }
        let monitor = NWPathMonitor()
        let seen = Locked<NWPath.Status?>(nil)
        monitor.pathUpdateHandler = { [weak self] path in
            let before = seen.write { seen -> NWPath.Status? in
                defer { seen = path.status }
                return seen
            }
            // Only a way back: the first report, and every one while it lasts, is not news.
            guard path.status == .satisfied, let before, before != .satisfied else { return }
            Task { await self?.networkAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "ai.clomni.engine.network"))
        networkObserver = monitor
    }
}
#endif
