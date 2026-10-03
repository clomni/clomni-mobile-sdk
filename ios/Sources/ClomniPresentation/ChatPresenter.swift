import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

package struct ChatPresenter: Sendable {
    /// Messages of one sender less than this far apart share a run: one avatar, one meta line.
    package static let groupWindow: TimeInterval = 60
    /// A longer pause gets a new time separator.
    package static let separatorPause: TimeInterval = 3_600

    package let strings: ClomniStrings
    private let time: TimeText
    private let now: Date

    package init(strings: ClomniStrings, timeZone: TimeZone = .current, now: Date) {
        self.strings = strings
        time = TimeText(strings: strings, timeZone: timeZone)
        self.now = now
    }

    /// The send button shows for text that is not blank and within the limit.
    package static func canSend(_ text: String, limit: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= limit
    }

    package func screen(_ snapshot: ChatSnapshot) -> ChatScreen {
        let hasContent = !snapshot.messages.isEmpty || !snapshot.pending.isEmpty
        let phase: HomeScreen.Phase = hasContent || snapshot.load == .loaded ? .ready
            : snapshot.load == .failed ? .failed : .loading
        let lastIncoming = snapshot.messages.last { $0.sender.type != .user && $0.type != "system" }
        return ChatScreen(
            phase: phase,
            header: header(snapshot),
            items: items(snapshot),
            composer: composer(snapshot),
            offline: snapshot.isOffline ? strings[.offline] : nil,
            failure: phase == .failed ? HomeScreen.Failure(message: strings[.error], retry: strings[.retry]) : nil,
            announcement: lastIncoming.map { Announcement(id: $0.id, text: label($0, snapshot)) },
            loadingLabel: strings[.loading])
    }

    // MARK: - Header

    private func header(_ snapshot: ChatSnapshot) -> ChatHeader {
        let config = snapshot.config
        let brand = config?.brand.name ?? ""
        let conversation = snapshot.conversation
        if let assignee = conversation?.assignee, conversation?.status != .bot, conversation?.status != .queued {
            let online = assignee.online ?? true
            return ChatHeader(
                lead: .person(ChatAvatar(url: assignee.avatarUrl, initial: initial(assignee.name), isBot: false),
                              online: online),
                title: assignee.name, subtitle: online ? "\(brand) · \(strings[.online])" : brand,
                backLabel: strings[.goBack], closeLabel: strings[.close])
        }
        let hours = config?.team.officeHours
        let away = hours?.openNow == false
        let back = hours?.nextOpenAt.map { strings.format(.awayUntil, time.upcoming($0, now: now)) } ?? strings[.away]
        let subtitle = away ? back
            : conversation?.status == .queued ? config?.team.replyTime ?? strings[.headerSubtitle] : strings[.headerSubtitle]
        return ChatHeader(lead: .team(teamAvatars(config)), title: brand, subtitle: subtitle,
                          backLabel: strings[.goBack], closeLabel: strings[.close])
    }

    private func teamAvatars(_ config: MessengerConfig?) -> [URL] {
        config?.team.show == false ? [] : Array((config?.team.avatars ?? []).prefix(3))
    }

    // MARK: - Composer

    private func composer(_ snapshot: ChatSnapshot) -> ChatComposer {
        let config = snapshot.config
        let waiting = snapshot.messages.last { snapshot.answerable.contains($0.id) }
        var mode = ChatComposer.Mode.open
        if snapshot.conversation?.status == .closed {
            mode = .closed(text: strings[.closed], action: strings[.startNewConversation])
        } else if case .quickReplies(let replies)? = waiting?.content, replies.inputDisabled {
            mode = .locked(strings[.chooseAbove])
        }
        return ChatComposer(
            mode: mode, placeholder: strings[.composerPlaceholder],
            showsAttach: config?.composer.attachments ?? true, showsEmoji: config?.composer.emoji ?? true,
            limit: config?.limits.textChars ?? 4_000, sendLabel: strings[.send], attachLabel: strings[.attach],
            emojiLabel: strings[.emoji], mediaLabel: strings[.pickMedia], cameraLabel: strings[.pickCamera],
            fileLabel: strings[.pickFile], removeAttachmentLabel: strings[.removeAttachment])
    }

    // MARK: - Transcript

    /// A bubble before the runs are known.
    private struct Draft {
        let id: String
        let side: Bubble.Side
        /// Same key, same run.
        let sender: String
        let date: Date
        let body: Bubble.Body
        let avatar: ChatAvatar?
        let metaName: String?
        var status: Bubble.Status?
        let accessibilityLabel: String
    }

    private enum Entry {
        case time(String, String)
        case draft(Draft)
        case system(SystemLine)
        case replies(QuickReplyBlock)
        case typing(TypingLine)
    }

    private func items(_ snapshot: ChatSnapshot) -> [ChatItem] {
        var entries: [Entry] = []
        var previous: Date?
        func separate(_ id: String, _ date: Date) {
            if previous.map({ date.timeIntervalSince($0) > Self.separatorPause }) ?? true {
                entries.append(.time("time-\(id)", time.day(date, now: now)))
            }
            previous = date
        }

        for message in snapshot.messages {
            separate(message.id, message.createdAt)
            if case .system(let system) = message.content {
                entries.append(.system(SystemLine(id: message.id, text: system.text,
                                                  avatars: systemAvatars(system.event, snapshot))))
                continue
            }
            if let body = body(message, snapshot) {
                entries.append(.draft(draft(message, body, snapshot)))
            }
            if case .quickReplies(let replies) = message.content, snapshot.answerable.contains(message.id) {
                entries.append(.replies(block(message.id, replies)))
            }
        }
        for pending in snapshot.pending {
            guard let body = body(pending, snapshot) else { continue }
            separate(pending.id, pending.createdAt)
            let text = pending.preview ?? (pending.upload?.fileName ?? strings[.back])
            entries.append(.draft(Draft(
                id: pending.id, side: .outgoing, sender: "user", date: pending.createdAt, body: body, avatar: nil,
                metaName: nil, status: status(pending),
                accessibilityLabel: "\(strings[.you]), \(time.clock(pending.createdAt)): \(text)")))
        }
        if let sender = snapshot.typing {
            let who = person(sender, snapshot)
            entries.append(.typing(TypingLine(avatar: who.avatar, accessibilityLabel: "\(who.name) \(strings[.typing])")))
        }
        markLastStatus(&entries, snapshot)
        return runs(entries)
    }

    /// The status of the user's last message shows when nothing came after it: "Göndərilir", "Göndərildi" or
    /// "Oxundu". A failure shows on its own message wherever it is.
    private func markLastStatus(_ entries: inout [Entry], _ snapshot: ChatSnapshot) {
        guard let index = entries.lastIndex(where: { if case .draft = $0 { return true }; return false }),
              case .draft(var last) = entries[index], last.side == .outgoing, last.status == nil else { return }
        let text: String
        if snapshot.pending.contains(where: { $0.id == last.id }) {
            text = strings[.sending]
        } else {
            let seq = snapshot.messages.first { $0.id == last.id }?.seq ?? 0
            text = snapshot.readUpTo.map { $0 >= seq } == true ? strings[.read] : strings[.sent]
        }
        last.status = Bubble.Status(text: text, isFailure: false, retryId: nil)
        entries[index] = .draft(last)
    }

    /// Bubbles of one sender within a minute of each other, with nothing between them, form a run.
    private func runs(_ entries: [Entry]) -> [ChatItem] {
        var items: [ChatItem] = []
        var index = 0
        while index < entries.count {
            guard case .draft(let first) = entries[index] else {
                switch entries[index] {
                case .time(let id, let text): items.append(.time(id: id, text: text))
                case .system(let line): items.append(.system(line))
                case .replies(let block): items.append(.replies(block))
                case .typing(let line): items.append(.typing(line))
                case .draft: break
                }
                index += 1
                continue
            }
            var run = [first]
            while index + run.count < entries.count, case .draft(let next) = entries[index + run.count],
                  next.sender == first.sender, let last = run.last,
                  next.date.timeIntervalSince(last.date) <= Self.groupWindow {
                run.append(next)
            }
            for (offset, draft) in run.enumerated() {
                let position: Bubble.Position = run.count == 1 ? .single
                    : offset == 0 ? .first : offset == run.count - 1 ? .last : .middle
                let closesRun = offset == run.count - 1 && draft.side == .incoming
                let meta = draft.metaName.map { "\($0) · \(time.ago(draft.date, now: now))" }
                let status = draft.status.flatMap { $0.isFailure ? nil : $0.text }
                items.append(.bubble(Bubble(id: draft.id, side: draft.side, body: draft.body, position: position,
                                            avatar: closesRun ? draft.avatar : nil, meta: closesRun ? meta : nil,
                                            status: draft.status,
                                            accessibilityLabel: draft.accessibilityLabel + (status.map { ". \($0)" } ?? ""),
                                            accessibilityHint: hint(draft.body))))
            }
            index += run.count
        }
        return items
    }

    private func draft(_ message: Message, _ body: Bubble.Body, _ snapshot: ChatSnapshot) -> Draft {
        let outgoing = message.sender.type == .user
        let who = person(message.sender, snapshot)
        return Draft(
            id: message.id, side: outgoing ? .outgoing : .incoming,
            sender: outgoing ? "user" : "\(message.sender.type.rawValue) \(message.sender.id ?? message.sender.name ?? "")",
            date: message.createdAt, body: body, avatar: outgoing ? nil : who.avatar,
            metaName: outgoing ? nil : message.sender.type == .bot ? "\(who.name) · \(strings[.bot])" : who.name,
            status: nil, accessibilityLabel: label(message, snapshot))
    }

    private func hint(_ body: Bubble.Body) -> String? {
        switch body {
        case .image: return strings[.opensImage]
        case .file(let file): return file.url == nil ? nil : strings[.opensFile]
        case .text, .form: return nil
        }
    }

    /// "Clomni bot, 10:30: Salam…" (brief 8 · 7.6).
    private func label(_ message: Message, _ snapshot: ChatSnapshot) -> String {
        let who: String
        switch message.sender.type {
        case .user: who = strings[.you]
        case .bot: who = "\(person(message.sender, snapshot).name) \(strings[.bot].lowercased())"
        default: who = person(message.sender, snapshot).name
        }
        return "\(who), \(time.clock(message.createdAt)): \(readable(message))"
    }

    private func readable(_ message: Message) -> String {
        switch message.content {
        case .text(let text): return LimitedMarkdown.plainText(text)
        case .image(let image): return strings[.image] + (image.caption.map { ": \($0)" } ?? "")
        case .file(let file): return "\(strings[.file]): \(file.name), \(Media.fileSize(file.size, language: strings.language))"
        case .quickReplies(let replies): return replies.text.map(LimitedMarkdown.plainText) ?? message.fallbackText
        case .form(let form): return form.text.map(LimitedMarkdown.plainText) ?? message.fallbackText
        default: return message.fallbackText
        }
    }

    /// What a message shows in its bubble; nil for quick replies without text (only the buttons show).
    private func body(_ message: Message, _ snapshot: ChatSnapshot) -> Bubble.Body? {
        switch message.content {
        case .text(let text):
            return .text(LimitedMarkdown.parse(text))
        case .quickReplies(let replies):
            return replies.text.map { .text(LimitedMarkdown.parse($0)) }
        case .image(let image):
            let box = Media.imageBox(width: image.width, height: image.height)
            return .image(Bubble.ImageBody(url: image.thumbUrl ?? image.url, fullUrl: image.url, localFile: nil,
                                           width: box.width, height: box.height, sizeKnown: box.known,
                                           caption: image.caption.map(LimitedMarkdown.parse)))
        case .file(let file):
            return .file(Bubble.FileBody(name: file.name, size: Media.fileSize(file.size, language: strings.language),
                                         symbol: Media.fileSymbol(mime: file.mime), url: file.url))
        case .form(let form):
            return .form(card(message.id, form, snapshot))
        case .system:
            return nil
        case .card, .rating, .unknown:
            // Phase 2 types and anything unknown read as a plain bot bubble with the fallback text.
            return .text([TextRun(message.fallbackText)])
        }
    }

    /// A pending message's bubble: its text, the button's title, "← Geri", or the file being sent. A submitted form
    /// or rating has none: the form itself shows it was sent.
    private func body(_ pending: PendingMessage, _ snapshot: ChatSnapshot) -> Bubble.Body? {
        switch pending.message.content {
        case .text(let text):
            return .text([TextRun(text)])
        case .buttonReply:
            return .text([TextRun(pending.preview ?? strings[.back])])
        case .attachment(_, let caption):
            guard let upload = pending.upload else { return caption.map { .text([TextRun($0)]) } }
            if Media.isImage(mime: upload.mime) {
                let box = Media.imageBox(width: nil, height: nil)
                return .image(Bubble.ImageBody(url: nil, fullUrl: nil, localFile: snapshot.localFiles[pending.id],
                                               width: box.width, height: box.height, sizeKnown: false,
                                               caption: caption.map { [TextRun($0)] }))
            }
            return .file(Bubble.FileBody(name: upload.fileName,
                                         size: Media.fileSize(upload.size, language: strings.language),
                                         symbol: Media.fileSymbol(mime: upload.mime), url: nil))
        case .formSubmit, .ratingSubmit:
            return nil
        }
    }

    private func status(_ pending: PendingMessage) -> Bubble.Status? {
        guard pending.state == .failed else { return nil }
        return Bubble.Status(text: "\(strings[.failed]) · \(strings[.retry])", isFailure: true, retryId: pending.id)
    }

    private func block(_ messageId: String, _ replies: MessageContent.QuickReplies) -> QuickReplyBlock {
        let buttons = replies.buttons.enumerated().map { index, button -> ReplyButton in
            let title = [button.icon, button.title].compactMap { $0 }.joined(separator: " ")
            return ReplyButton(id: button.id, title: title,
                               accessibilityLabel: strings.buttonPosition(title: button.title, index: index + 1,
                                                                          count: replies.buttons.count))
        }
        let back = replies.allowBack
            ? ReplyButton(id: "back", title: strings[.back], accessibilityLabel: strings[.goBack])
            : nil
        return QuickReplyBlock(messageId: messageId, layout: replies.layout, buttons: buttons, back: back)
    }

    private func card(_ messageId: String, _ form: MessageContent.Form, _ snapshot: ChatSnapshot) -> FormCard {
        let prefill = FormInput.prefill(form, known: snapshot.known)
        let sent = form.submitted != nil
        return FormCard(
            messageId: messageId, text: form.text.map(LimitedMarkdown.parse),
            fields: form.fields.map { field in
                FormCard.Field(id: field.key, type: field.type, label: field.label, required: field.required,
                               placeholder: field.placeholder, maxLength: field.maxLength, options: field.options,
                               accessibilityLabel: field.required ? "\(field.label), \(strings[.required])" : field.label,
                               initialValue: prefill[field.key] ?? "")
            },
            submitTitle: form.submitTitle,
            readOnly: sent || !snapshot.answerable.contains(messageId),
            submitted: FormInput.submittedLines(form).map { FormCard.Line(label: $0.label, value: $0.value) },
            sentLabel: sent ? strings[.sent] : nil)
    }

    private func systemAvatars(_ event: MessageContent.SystemEvent, _ snapshot: ChatSnapshot) -> [ChatAvatar] {
        switch event {
        case .operatorJoined:
            guard let assignee = snapshot.conversation?.assignee else { return [] }
            return [ChatAvatar(url: assignee.avatarUrl, initial: initial(assignee.name), isBot: false)]
        case .waitingInQueue, .assignedToTeam:
            return teamAvatars(snapshot.config).map { ChatAvatar(url: $0, initial: "", isBot: false) }
        default:
            return []
        }
    }

    /// The name and face of a sender as the conversation shows them.
    private func person(_ sender: Sender, _ snapshot: ChatSnapshot) -> (name: String, avatar: ChatAvatar) {
        let config = snapshot.config
        let brand = config?.brand.name ?? ""
        let botName = config?.bot.name.isEmpty == false ? config?.bot.name : nil
        switch sender.type {
        case .bot:
            let name = sender.name ?? botName ?? brand
            return (name, ChatAvatar(url: config?.bot.avatarUrl ?? sender.avatarUrl ?? config?.brand.logoUrl, initial: initial(name),
                                     isBot: true))
        case .operator:
            let assignee = snapshot.conversation?.assignee
            let name = sender.name ?? assignee?.name ?? brand
            return (name, ChatAvatar(url: sender.avatarUrl ?? assignee?.avatarUrl, initial: initial(name), isBot: false))
        case .user:
            return (strings[.you], ChatAvatar(url: nil, initial: initial(strings[.you]), isBot: false))
        case .system, .unknown:
            return (brand, ChatAvatar(url: nil, initial: initial(brand), isBot: true))
        }
    }

    private func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? ""
    }
}
