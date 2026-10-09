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
        let composer = composer(snapshot, known: phase == .ready)
        return ChatScreen(
            phase: phase,
            header: header(snapshot),
            // No reply while a flow waits for a choice: there is no composer to write the answer in.
            items: items(snapshot, canReply: composer.mode == .open),
            composer: composer,
            offline: snapshot.isOffline ? strings[.offline] : nil,
            connected: strings[.connected],
            failure: phase == .failed ? HomeScreen.Failure(message: strings[.error], retry: strings[.retry]) : nil,
            announcement: lastIncoming.map { Announcement(id: $0.id, text: label($0, snapshot)) },
            loadingLabel: strings[.loading], replyLabel: strings[.reply], copyLabel: strings[.copy],
            newMessageLabel: strings[.newMessage])
    }

    // MARK: - Header

    private func header(_ snapshot: ChatSnapshot) -> ChatHeader {
        let config = snapshot.config
        let brand = config?.brand.name ?? ""
        let conversation = snapshot.conversation
        // Who answers, whatever the status: the assignee; without one, the last operator who wrote (no dot: nothing
        // says they are online).
        let wrote = snapshot.messages.last { $0.sender.type == .operator && !($0.sender.name ?? "").isEmpty }?.sender
        let person: (name: String, avatarUrl: URL?, online: Bool)? = conversation?.assignee
            .map { ($0.name, $0.avatarUrl, $0.online ?? true) } ?? wrote.map { ($0.name ?? "", $0.avatarUrl, false) }
        if let person {
            return ChatHeader(
                lead: .person(ChatAvatar(url: person.avatarUrl, initial: initial(person.name), isBot: false),
                              online: person.online),
                // Only the company: being online is the green dot on the avatar, not a word (operator, 2026-10-05).
                title: person.name, subtitle: brand,
                backLabel: strings[.goBack], closeLabel: strings[.close])
        }
        let hours = config?.team.officeHours
        let away = hours?.openNow == false
        let back = hours?.nextOpenAt.map { strings.format(.awayUntil, time.upcoming($0, now: now)) } ?? strings[.away]
        let subtitle = away ? back
            : conversation?.status == .queued ? config?.team.replyTime ?? strings[.headerSubtitle] : strings[.headerSubtitle]
        // No operator has taken it or written (the bot or a flow answers): the company, by its logo and name.
        return ChatHeader(lead: .brand(ChatAvatar(url: config?.brand.logoUrl, initial: initial(brand), isBot: true)),
                          title: brand, subtitle: subtitle,
                          backLabel: strings[.goBack], closeLabel: strings[.close])
    }

    private func teamAvatars(_ config: MessengerConfig?) -> [URL] {
        config?.team.show == false ? [] : Array((config?.team.avatars ?? []).prefix(3))
    }

    // MARK: - Composer

    private func composer(_ snapshot: ChatSnapshot, known: Bool) -> ChatComposer {
        let config = snapshot.config
        var mode = ChatComposer.Mode.open
        if !known {
            // Not "shown" by default (DESIGN-PASS-3 C5): until the messages and their buttons are known there is none,
            // so a flow's step never finds one to take away.
            mode = .hidden
        } else if snapshot.conversation?.status == .closed {
            mode = .closed(text: strings[.closed], action: strings[.startNewConversation])
        } else if snapshot.conversation?.flow?.holdsTheComposer == true, !snapshot.flowStalled {
            // The server says whether a flow drives the conversation (operator, 2026-10-05): while it waits for a
            // button, a form or its next step there is no field; it waits for typed text, or it is over, and the field
            // is back. So it is when it waits for a choice that is no longer there (`flowStalled`).
            mode = .hidden
        }
        return ChatComposer(
            mode: mode, placeholder: strings[.composerPlaceholder],
            showsAttach: config?.composer.attachments ?? true, showsEmoji: config?.composer.emoji ?? true,
            limit: config?.limits.textChars ?? 4_000, sendLabel: strings[.send], attachLabel: strings[.attach],
            emojiLabel: strings[.emoji], emojiRecentLabel: strings[.emojiRecent],
            emojiCategoryLabels: ClomniStrings.emojiCategories.map { strings[$0] },
            mediaLabel: strings[.pickMedia], cameraLabel: strings[.pickCamera],
            fileLabel: strings[.pickFile], removeAttachmentLabel: strings[.removeAttachment],
            quote: mode == .open ? snapshot.replyingTo.flatMap { id in snapshot.messages.first { $0.id == id } }
                .map { quote($0, snapshot) } : nil,
            cancelQuoteLabel: strings[.close])
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
        var avatar: ChatAvatar?
        /// Who wrote it, over an incoming run: the brand for the bot, the operator's name; nil for the user.
        let author: String?
        var status: Bubble.Status?
        let accessibilityLabel: String
        var quote: Bubble.Quote?
        var messageId: String?
        var replyable = false
        var copyText: String?
        /// Who wrote it; nil for the user's pending messages.
        var from: Sender?
    }

    private enum Entry {
        case time(String, String)
        case draft(Draft)
        case system(SystemLine)
        case replies(QuickReplyBlock)
        case typing(TypingLine)
    }

    private func items(_ snapshot: ChatSnapshot, canReply: Bool) -> [ChatItem] {
        var entries: [Entry] = []
        var previous: Date?
        func separate(_ id: String, _ date: Date) {
            if previous.map({ date.timeIntervalSince($0) > Self.separatorPause }) ?? true {
                entries.append(.time("time-\(id)", time.day(date, now: now)))
            }
            previous = date
        }

        let choicesFor = Self.liveChoices(snapshot)

        for message in Self.joinedFirst(snapshot.messages) {
            separate(key(message), message.createdAt)
            if case .system(let system) = message.content {
                entries.append(.system(SystemLine(id: message.id, text: system.text,
                                                  avatars: systemAvatars(system.event, snapshot))))
                continue
            }
            if let body = body(message, snapshot) {
                var draft = draft(message, body, snapshot)
                draft.quote = message.replyTo.map { quote($0, snapshot) }
                draft.messageId = message.id
                // A form or a rating is answered in its card, not quoted.
                switch body {
                case .form, .rating: break
                default: draft.replyable = canReply
                }
                draft.copyText = copyText(message.content)
                entries.append(.draft(draft))
            }
            if case .quickReplies(let replies) = message.content, message.id == choicesFor {
                entries.append(.replies(block(message.id, replies)))
            }
        }
        for pending in snapshot.pending {
            guard let body = body(pending, snapshot) else { continue }
            separate(pending.id, pending.createdAt)
            let text = pending.preview ?? (pending.upload?.fileName ?? strings[.back])
            entries.append(.draft(Draft(
                id: pending.id, side: .outgoing, sender: "user", date: pending.createdAt, body: body, avatar: nil,
                author: nil, status: status(pending),
                accessibilityLabel: "\(strings[.you]), \(time.clock(pending.createdAt)): \(text)",
                quote: pending.message.replyTo.map { id in
                    snapshot.messages.first { $0.id == id }.map { quote($0, snapshot) }
                        ?? Bubble.Quote(messageId: id, author: "", excerpt: strings[.quoteDeleted])
                },
                copyText: pending.preview)))
        }
        // A row of its own at the end; none while a flow waits for a choice.
        if let sender = snapshot.typing, !snapshot.awaitsChoice {
            let who = person(sender, snapshot)
            // One face: the run the typing continues gives its avatar to the typing row.
            if case .draft(var last)? = entries.last, last.from?.isTyping(sender) == true {
                last.avatar = nil
                entries[entries.count - 1] = .draft(last)
            }
            entries.append(.typing(TypingLine(avatar: who.avatar, accessibilityLabel: "\(who.name) \(strings[.typing])")))
        }
        markStatuses(&entries, snapshot)
        return runs(entries)
    }

    /// Only the newest bot message's choices, while nothing has answered it (operator, 2026-10-04, 72): a choice
    /// made, here or on another device, or anything the user wrote after it, and the choices are gone; old ones in the
    /// history are never drawn. The id of the message whose choices show, if any.
    static func liveChoices(_ snapshot: ChatSnapshot) -> String? {
        let lastOther = snapshot.messages.last { $0.sender.type != .user && $0.sender.type != .system }
        guard let last = lastOther, snapshot.pending.isEmpty,
              !snapshot.messages.contains(where: { $0.sender.type == .user && $0.seq > last.seq }),
              case .quickReplies = last.content, snapshot.answerable.contains(last.id) else { return nil }
        return last.id
    }

    /// How long before "Leyla söhbətə qoşuldu" her first messages may have been written for the line to go before them.
    static let joinReach: TimeInterval = 300

    /// The panel assigns an operator when she first replies, so the server numbers "Leyla söhbətə qoşuldu" after her
    /// first messages (CM-087: the RN test on Android). The line goes before them: before the run of her messages
    /// right in front of it, written within `joinReach` of it, when she wrote nothing earlier (then she joins again,
    /// and the line stays where it is).
    static func joinedFirst(_ messages: [Message]) -> [Message] {
        var shown: [Message] = []
        for message in messages {
            guard case .system(let system) = message.content, system.event == .operatorJoined else {
                shown.append(message)
                continue
            }
            func hers(_ other: Message) -> Bool {
                guard other.sender.type == .operator, let name = other.sender.name, !name.isEmpty else { return false }
                return system.text.contains(name)
            }
            var start = shown.count
            while start > 0, hers(shown[start - 1]),
                  message.createdAt.timeIntervalSince(shown[start - 1].createdAt) <= joinReach {
                start -= 1
            }
            if start < shown.count, !shown[..<start].contains(where: hers) {
                shown.insert(message, at: start)
            } else {
                shown.append(message)
            }
        }
        return shown
    }

    /// Every message of the user's has its mark after its time, in the bubble (G7): the clock while it goes, then ✓,
    /// two once read; VoiceOver reads "Göndərilir", "Göndərildi" or "Oxundu". A failure is in words instead.
    private func markStatuses(_ entries: inout [Entry], _ snapshot: ChatSnapshot) {
        let pending = Set(snapshot.pending.map(\.id))
        let seqs = Dictionary(snapshot.messages.map { (key($0), $0.seq) }, uniquingKeysWith: { first, _ in first })
        for index in entries.indices {
            guard case .draft(var draft) = entries[index], draft.side == .outgoing, draft.status == nil else { continue }
            let mark: Bubble.Status.Mark
            if pending.contains(draft.id) {
                mark = .sending
            } else {
                let seq = seqs[draft.id] ?? 0
                mark = snapshot.readUpTo.map { $0 >= seq } == true ? .read : .sent
            }
            let text: String
            switch mark {
            case .sending: text = strings[.sending]
            case .sent: text = strings[.sent]
            case .read: text = strings[.read]
            }
            draft.status = Bubble.Status(text: text, isFailure: false, retryId: nil, mark: mark)
            entries[index] = .draft(draft)
        }
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
                // Who is over its first; when is in every bubble.
                let opensRun = (offset == 0) && draft.side == .incoming
                let status = draft.status.flatMap { $0.isFailure ? nil : $0.text }
                items.append(.bubble(Bubble(id: draft.id, side: draft.side, body: draft.body, position: position,
                                            avatar: closesRun ? draft.avatar : nil,
                                            nameLine: opensRun ? draft.author : nil, time: time.clock(draft.date),
                                            status: draft.status,
                                            accessibilityLabel: draft.accessibilityLabel + (status.map { ". \($0)" } ?? ""),
                                            accessibilityHint: hint(draft.body), quote: draft.quote,
                                            messageId: draft.messageId, replyable: draft.replyable,
                                            copyText: draft.copyText)))
            }
            index += run.count
        }
        return items
    }

    /// A message's place in the transcript: its `client_id` when it has one, so the user's message keeps it from the
    /// moment it is written to the server's copy, and only its status changes; otherwise its id.
    private func key(_ message: Message) -> String {
        message.clientId ?? message.id
    }

    private func draft(_ message: Message, _ body: Bubble.Body, _ snapshot: ChatSnapshot) -> Draft {
        let outgoing = message.sender.type == .user
        let who = person(message.sender, snapshot)
        return Draft(
            id: key(message), side: outgoing ? .outgoing : .incoming,
            sender: outgoing ? "user" : "\(message.sender.type.rawValue) \(message.sender.id ?? message.sender.name ?? "")",
            date: message.createdAt, body: body, avatar: outgoing ? nil : who.avatar,
            author: outgoing ? nil : who.name,
            status: nil, accessibilityLabel: label(message, snapshot), from: message.sender)
    }

    private func hint(_ body: Bubble.Body) -> String? {
        switch body {
        case .image: return strings[.opensImage]
        case .file(let file): return file.url == nil ? nil : strings[.opensFile]
        case .text, .form, .rating: return nil
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
        case .rating(let rating): return LimitedMarkdown.plainText(rating.text)
        default: return message.fallbackText
        }
    }

    /// What a message shows in its bubble; nil for quick replies without text (only the buttons show).
    private func body(_ message: Message, _ snapshot: ChatSnapshot) -> Bubble.Body? {
        switch message.content {
        case .text(let text):
            return .text(rich(text))
        case .quickReplies(let replies):
            return replies.text.map { .text(rich($0)) }
        case .image(let image):
            let box = Media.imageBox(width: image.width, height: image.height)
            return .image(Bubble.ImageBody(url: image.thumbUrl ?? image.url, fullUrl: image.url, localFile: nil,
                                           width: box.width, height: box.height, sizeKnown: box.known,
                                           caption: image.caption.map(rich)))
        case .file(let file):
            return .file(Bubble.FileBody(name: file.name, size: Media.fileSize(file.size, language: strings.language),
                                         symbol: Media.fileSymbol(mime: file.mime), url: file.url))
        case .form(let form):
            return .form(card(message.id, form, snapshot))
        case .rating(let rating):
            return .rating(card(message.id, rating, snapshot))
        case .system:
            return nil
        case .card, .unknown:
            // Phase 2 types and anything unknown read as a plain bot bubble with the fallback text.
            return .text(TextLinks.linkify([TextRun(message.fallbackText)]))
        }
    }

    /// A message's text: its markdown, and the addresses, emails and phone numbers written in it, tappable.
    private func rich(_ text: String) -> [TextRun] {
        TextLinks.linkify(LimitedMarkdown.parse(text))
    }

    /// A pending message's bubble: its text, the button's title, "← Geri", or the file being sent. A submitted form
    /// or rating has none: the form itself shows it was sent.
    private func body(_ pending: PendingMessage, _ snapshot: ChatSnapshot) -> Bubble.Body? {
        switch pending.message.content {
        case .text(let text):
            return .text(TextLinks.linkify([TextRun(text)]))
        case .buttonReply:
            return .text([TextRun(pending.preview ?? strings[.back])])
        case .attachment(_, let caption):
            guard let upload = pending.upload else { return caption.map { .text([TextRun($0)]) } }
            if Media.isImage(mime: upload.mime) {
                let box = Media.imageBox(width: nil, height: nil)
                return .image(Bubble.ImageBody(url: nil, fullUrl: nil, localFile: snapshot.localFiles[pending.id],
                                               width: box.width, height: box.height, sizeKnown: false,
                                               caption: caption.map { TextLinks.linkify([TextRun($0)]) }))
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
        // The flow's own "Yenidən başla" (or back) already takes the user back: no second one from the SDK.
        let back = replies.allowBack && !replies.buttons.contains { Self.isRestart($0.title) }
            ? ReplyButton(id: "back", title: strings[.back], accessibilityLabel: strings[.goBack])
            : nil
        return QuickReplyBlock(messageId: messageId, layout: replies.layout, buttons: buttons, back: back)
    }

    /// A flow button with one of these titles (letters only, lower case) restarts or steps back by itself.
    private static let restartTitles: Set<String> = [
        "yenidən başla", "yenidən başlat", "əvvələ qayıt", "başa qayıt", "geri", "geri qayıt",
        "start over", "restart", "back", "go back", "начать заново", "сначала", "назад",
    ]

    static func isRestart(_ title: String) -> Bool {
        let letters = title.lowercased().filter { $0.isLetter || $0 == " " }
        return restartTitles.contains(letters.split(separator: " ").joined(separator: " "))
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
                               initialValue: prefill[field.key] ?? "",
                               shownLabel: field.required ? field.label : "\(field.label) \(strings[.optional])")
            },
            submitTitle: form.submitTitle,
            readOnly: sent || !snapshot.answerable.contains(messageId),
            submitted: FormInput.submittedLines(form).map { FormCard.Line(label: $0.label, value: $0.value) },
            sentLabel: sent ? strings[.sent] : nil)
    }

    /// The faces as the web widget has them, worst to best.
    private static let faces = ["😞", "😑", "😐", "😀", "😍"]

    private func card(_ messageId: String, _ rating: MessageContent.Rating, _ snapshot: ChatSnapshot) -> RatingCard {
        let words: [ClomniStrings.Key] = [.rating1, .rating2, .rating3, .rating4, .rating5]
        let options = (1...5).map { score in
            RatingCard.Option(score: score, face: rating.scale == .emoji5 ? Self.faces[score - 1] : nil,
                              accessibilityLabel: rating.scale == .emoji5 ? strings[words[score - 1]]
                                  : strings.format(.ratingStars, score))
        }
        // What the server says first (it answers a rating_submit with the rating, `submitted` filled); then the answer
        // on its way, offline too (open again if it failed).
        let pending = snapshot.pending.last { entry in
            if case .ratingSubmit(let replyTo, _, _) = entry.message.content { return replyTo == messageId }
            return false
        }
        let state: RatingCard.State
        if let submitted = rating.submitted {
            state = .sent(score: submitted["score"]?.intValue.flatMap { (1...5).contains($0) ? $0 : nil },
                          comment: submitted["comment"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 })
        } else if let pending, case .ratingSubmit(_, let score, let comment) = pending.message.content {
            state = pending.state == .failed ? .open : .sent(score: score, comment: comment)
        } else {
            state = snapshot.answerable.contains(messageId) ? .open : .sent(score: nil, comment: nil)
        }
        let field = rating.comment == .hidden ? nil : FormCard.Field(
            id: "comment", type: .textarea, label: strings[.ratingComment], required: rating.comment == .required,
            placeholder: nil, maxLength: Self.commentLimit, options: [],
            accessibilityLabel: rating.comment == .required ? "\(strings[.ratingComment]), \(strings[.required])"
                : strings[.ratingComment],
            initialValue: "",
            shownLabel: rating.comment == .required ? strings[.ratingComment]
                : "\(strings[.ratingComment]) \(strings[.optional])")
        var sentLabel: String?
        if case .sent(let score?, let comment) = state {
            sentLabel = [strings.format(.ratingYours, options[score - 1].accessibilityLabel), comment,
                         strings[.ratingThanks]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
        }
        return RatingCard(messageId: messageId, text: rich(rating.text), options: options, commentField: field,
                          state: state, submitTitle: strings[.send], thanks: strings[.ratingThanks],
                          sentAccessibilityLabel: sentLabel)
    }

    /// A rating's comment is a client message's text: at most this long.
    package static let commentLimit = 4_000

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

    // MARK: - Replies

    /// The server's description of the quoted message.
    private func quote(_ ref: ReplyRef, _ snapshot: ChatSnapshot) -> Bubble.Quote {
        let excerpt = ref.excerpt.map(oneLine) ?? ""
        return Bubble.Quote(messageId: ref.id, author: ref.sender.map { author($0, snapshot) } ?? "",
                            excerpt: excerpt.isEmpty ? strings[.quoteDeleted] : excerpt)
    }

    /// A message here being quoted: over the field, and in the user's bubble until the server's copy comes.
    private func quote(_ message: Message, _ snapshot: ChatSnapshot) -> Bubble.Quote {
        let excerpt: String
        switch message.content {
        case .image(let image): excerpt = image.caption ?? strings[.image]
        case .file(let file): excerpt = file.name
        default: excerpt = readable(message)
        }
        return Bubble.Quote(messageId: message.id, author: author(message.sender, snapshot),
                            excerpt: String(oneLine(excerpt).prefix(Self.excerptLength)))
    }

    private func author(_ sender: Sender, _ snapshot: ChatSnapshot) -> String {
        sender.type == .user ? strings[.you] : person(sender, snapshot).name
    }

    private func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// What "Kopyala" copies.
    private func copyText(_ content: MessageContent) -> String? {
        switch content {
        case .text(let text): return LimitedMarkdown.plainText(text)
        case .image(let image): return image.caption
        case .quickReplies(let replies): return replies.text.map(LimitedMarkdown.plainText)
        default: return nil
        }
    }

    /// The server's excerpts are at most this long; a local quote is cut to the same.
    private static let excerptLength = 120

    /// The name and face of a sender as the conversation shows them.
    private func person(_ sender: Sender, _ snapshot: ChatSnapshot) -> (name: String, avatar: ChatAvatar) {
        let config = snapshot.config
        let brand = config?.brand.name ?? ""
        switch sender.type {
        case .bot:
            // The bot speaks as the brand (DESIGN-PASS-3 B2): its own name in the panel is not shown.
            let name = brand.isEmpty ? sender.name ?? config?.bot.name ?? "" : brand
            // The bot is the company: its logo first.
            return (name, ChatAvatar(url: config?.brand.logoUrl ?? config?.bot.avatarUrl ?? sender.avatarUrl, initial: initial(name),
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
