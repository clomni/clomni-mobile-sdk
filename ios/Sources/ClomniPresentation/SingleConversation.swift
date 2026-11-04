import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// CM-346 § 5.4: with `config.conversation.single` (the inbox's lock_to_single_conversation), "Bizə mesaj göndərin",
/// the list's new conversation and `Clomni.presentNewConversation` open the conversation the server would resume, with
/// its history. A new, empty one jumped to the old one at its first message, when the server put the message there
/// (TestFlight #21). Which one is the server's to say (`resume_conversation_id` of GET /conversations): it leaves out a
/// bot conversation idle for over 30 minutes and one a flow has finished (CM-291), which a rule here would have
/// reopened at an old menu. Should the server still answer with another conversation, the screen follows it as before.
package enum SingleConversation {
    /// The conversation a new one gives way to: `resume` with the setting on; nil (a new one) otherwise.
    package static func existing(resume: String?, config: MessengerConfig?) -> String? {
        config?.singleConversation == true ? resume : nil
    }
}
