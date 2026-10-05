import Foundation
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif
#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
#endif

/// Clomni's two short tones (DESIGN-PASS-3 A7): a ding for a message that arrives while the conversation is open, a
/// ping for one the user sends. They play in the `.ambient` audio category: the silent switch mutes them and music
/// keeps playing. An app that set its own category (playback, a call) is left alone and hears nothing. Off when the
/// panel says `sounds: false` or the app calls `Clomni.setSoundsEnabled(false)`.
enum MessageSounds {
    /// `Clomni.setSoundsEnabled`; read and written on the main thread.
    static var appEnabled = true

    #if canImport(AVFoundation) && canImport(UIKit)
    private static var players: [ChatSound: AVAudioPlayer] = [:]

    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        // CocoaPods: the ClomniMessenger_Sounds resource bundle next to the code.
        let host = Bundle(for: BundleToken.self)
        return host.url(forResource: "ClomniMessenger_Sounds", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? host
        #endif
    }

    #endif

    @MainActor
    static func play(_ sound: ChatSound) {
        guard appEnabled else { return }
        #if canImport(AVFoundation) && canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient {
            try? session.setCategory(.ambient)
        }
        guard session.category == .ambient else { return }
        if players[sound] == nil {
            let name = sound == .incoming ? "clomni_ding" : "clomni_ping"
            players[sound] = bundle.url(forResource: name, withExtension: "wav")
                .flatMap { try? AVAudioPlayer(contentsOf: $0) }
            players[sound]?.prepareToPlay()
        }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
        #endif
    }
}

#if canImport(AVFoundation) && canImport(UIKit) && !SWIFT_PACKAGE
private final class BundleToken {}
#endif
