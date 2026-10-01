import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// The SDK's facade: everything an app calls is a static member of `Clomni`.
public enum Clomni {
    /// This SDK's version.
    public static let version = SDKInfo.version
}

/// The app's user, for `Clomni.loginUser`. Clomni knows the user by `userId`, else by `email`.
public struct ClomniUser: Sendable, Equatable {
    public var userId: String?
    public var email: String?
    public var phone: String?
    public var name: String?

    public init(userId: String? = nil, email: String? = nil, phone: String? = nil, name: String? = nil) {
        self.userId = userId
        self.email = email
        self.phone = phone
        self.name = name
    }

    var identity: UserIdentity {
        UserIdentity(userId: userId, email: email, phone: phone, name: name)
    }
}
