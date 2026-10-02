import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// What the Home and Messages tabs read; `ClomniEngine` is one, tests use a fake.
package protocol MessengerDataSource: Sendable {
    var config: MessengerConfig? { get async }
    func refreshConfig(language: String?) async -> MessengerConfig?
    func conversations() async -> [Conversation]
    func refreshConversations() async throws
    var unreadTotal: Int { get async }
    func draftConversation(openedFrom: String?) async -> String
    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID
    func stopObserving(_ token: UUID) async
}

extension ClomniEngine: MessengerDataSource {}

/// Keeps the Home and Messages screens current: what is cached at once, then the server's answer, then every change
/// the engine reports. The SwiftUI views observe it through `onChange`.
@MainActor
package final class HomeController {
    package private(set) var home: HomeScreen
    package private(set) var messages: MessagesScreen
    /// Called after `home` or `messages` changed.
    package var onChange: (() -> Void)?

    /// For the theme: the brand's colours and appearance.
    package var config: MessengerConfig? { snapshot.config }

    package var userName: String? {
        didSet { render() }
    }

    /// The thin yellow strip; set from the app's reachability.
    package var isOffline = false {
        didSet { render() }
    }

    private let source: MessengerDataSource
    private let language: String?
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private var snapshot: MessengerSnapshot
    private var observation: UUID?

    package init(source: MessengerDataSource, language: String?, userName: String?, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.language = language
        self.timeZone = timeZone
        self.now = now
        snapshot = MessengerSnapshot(userName: userName)
        self.userName = userName
        let presenter = HomePresenter(strings: ClomniStrings(language: language), timeZone: timeZone, now: now())
        home = presenter.home(snapshot)
        messages = presenter.messages(snapshot)
    }

    /// Shows the cache at once, then asks the server for the config and the conversations.
    package func load() async {
        await read()
        render()
        if observation == nil {
            observation = await source.observe { [weak self] change in
                Task { @MainActor in await self?.changed(change) }
            }
        }
        let config = await source.refreshConfig(language: language)
        snapshot.configLoad = config == nil ? .failed : .loaded
        do {
            try await source.refreshConversations()
            snapshot.conversationsLoad = .loaded
        } catch {
            snapshot.conversationsLoad = .failed
        }
        await read()
        render()
    }

    /// Stops following the engine's changes, when the messenger closes.
    package func stop() async {
        guard let observation else { return }
        self.observation = nil
        await source.stopObserving(observation)
    }

    /// "Yenidən cəhd et".
    package func retry() async {
        snapshot.configLoad = .loading
        snapshot.conversationsLoad = .loading
        render()
        await load()
    }

    /// "Bizə mesaj göndərin": a draft's id. The server creates the conversation with its first message.
    package func startConversation(openedFrom: String?) async -> String {
        await source.draftConversation(openedFrom: openedFrom)
    }

    func changed(_ change: ClomniChange) async {
        switch change {
        case .typing, .read:
            return
        default:
            await read()
            render()
        }
    }

    private func read() async {
        snapshot.config = await source.config
        snapshot.conversations = await source.conversations()
        snapshot.unreadTotal = await source.unreadTotal
    }

    private func render() {
        snapshot.userName = userName
        snapshot.isOffline = isOffline
        let strings = ClomniStrings(language: language ?? snapshot.config?.languages.first,
                                    overrides: snapshot.config?.strings ?? [:])
        let presenter = HomePresenter(strings: strings, timeZone: timeZone, now: now())
        home = presenter.home(snapshot)
        messages = presenter.messages(snapshot)
        onChange?()
    }
}
