import ClomniMessenger
import SwiftUI

/// A ride app's profile screen: the app's own buttons open the messenger, there is no Clomni element of its own.
@MainActor
struct ContentView: View {
    @StateObject private var support = SupportBadge()
    @State private var loggedIn = false
    @State private var launcherOn = false

    var body: some View {
        NavigationView {
            List {
                Section("Profil") {
                    if loggedIn {
                        Button("Çıxış", action: logOut)
                    } else {
                        Button("Daxil ol: Aysel", action: logIn)
                    }
                }

                Section("Son gediş") {
                    Text("Gənclik → 28 May · 2.40 ₼")
                    // A button with context: the flow bound to "ride_problem" gets the ride.
                    Button("Problem bildir") {
                        Clomni.startFlow("ride_problem", data: ["ride_id": "R-1042", "amount": 2.40],
                                         openMessenger: true, source: "ride_detail")
                    }
                }

                Section("Kömək") {
                    Button {
                        Clomni.present(source: "profile_support")
                    } label: {
                        HStack {
                            Text("Dəstək")
                            Spacer()
                            if support.unread > 0 {
                                Text("\(support.unread)")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                    }
                    Button("Yeni sual") {
                        Clomni.presentNewConversation(source: "profile_new_question")
                    }
                    Toggle("Üzən düymə", isOn: $launcherOn)
                        .onChange(of: launcherOn) { Clomni.setLauncherVisible($0) }
                }
            }
            .navigationTitle("Apar")
        }
        .onAppear { if UITestMode.isOn { UITestMode.start() } }
    }

    private func logIn() {
        // userHash is hex(HMAC-SHA256(identity_secret, user_id)), made on the app's server. identity_secret never
        // goes into the app.
        let user = ClomniUser(userId: "5", email: "aysel@example.com", name: "Aysel")
        Clomni.loginUser(user, userHash: YourServer.clomniUserHash(for: user))
        Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])
        loggedIn = true
    }

    private func logOut() {
        // Without this the next user of the phone sees Aysel's conversations.
        Clomni.logout()
        loggedIn = false
    }
}

/// The unread count on the app's own "Dəstək" row.
@MainActor
final class SupportBadge: ObservableObject {
    @Published private(set) var unread = 0

    init() {
        Clomni.addUnreadCountListener { [weak self] count in
            self?.unread = count
        }
    }
}

/// Stands for the app's backend, which knows identity_secret.
enum YourServer {
    static func clomniUserHash(for user: ClomniUser) -> String? {
        nil
    }
}
