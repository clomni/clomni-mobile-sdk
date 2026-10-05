import Foundation
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif
#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
#endif

/// One short sound (Universfield, Pixabay Content License): at full volume for a message that arrives while the
/// conversation is open, at 40% for one the user sends (DESIGN-PASS-3 A7, B4). It plays in the `.ambient` audio category: the silent switch mutes them and music
/// keeps playing. An app that set its own category (playback, a call) is left alone and hears nothing. Off when the
/// panel says `sounds: false` or the app calls `Clomni.setSoundsEnabled(false)`.
enum MessageSounds {
    /// `Clomni.setSoundsEnabled`; read and written on the main thread.
    static var appEnabled = true

    /// A message the user sends.
    static let sentVolume: Float = 0.4

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
            // One player each, so a reply that comes while the sent sound plays still sounds.
            players[sound] = bundle.url(forResource: "clomni_message", withExtension: "mp3")
                .flatMap { try? AVAudioPlayer(contentsOf: $0) }
            players[sound]?.volume = sound == .sent ? sentVolume : 1
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
