#if canImport(SwiftUI) && canImport(UIKit)
import Foundation
#if canImport(Network)
import Network
#endif

/// Whether the phone has a way to the network, for the offline capsule (CM-077): "İnternet yoxdur"
/// while it has none, the screens staying as the cache has them. One system monitor for the whole SDK, started the
/// first time a screen asks.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOffline = false
    private var listeners: [(isGone: () -> Bool, call: (Bool) -> Void)] = []
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    #endif

    private init() {
        #if canImport(Network)
        monitor.pathUpdateHandler = { path in
            let offline = path.status != .satisfied
            Task { @MainActor in NetworkMonitor.shared.update(offline) }
        }
        monitor.start(queue: DispatchQueue(label: "ai.clomni.network"))
        #endif
    }

    /// Tells `owner` the state now and at every change, for as long as it lives.
    func follow<Owner: AnyObject>(_ owner: Owner, _ apply: @escaping (Owner, Bool) -> Void) {
        listeners.removeAll { $0.isGone() }
        weak var weakOwner = owner
        listeners.append((isGone: { weakOwner == nil }, call: { offline in
            if let owner = weakOwner { apply(owner, offline) }
        }))
        apply(owner, isOffline)
    }

    private func update(_ offline: Bool) {
        guard offline != isOffline else { return }
        isOffline = offline
        listeners.removeAll { $0.isGone() }
        listeners.forEach { $0.call(offline) }
    }
}
#endif
