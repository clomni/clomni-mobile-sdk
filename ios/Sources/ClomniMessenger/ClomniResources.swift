#if canImport(SwiftUI) && canImport(UIKit)
import Foundation

/// Where the SDK's files are: SwiftPM's bundle of the module, or under CocoaPods the resource bundle `pod` names
/// (ClomniMessenger_Sounds, ClomniMessenger_Media) next to the code.
enum ClomniResources {
    static func bundle(_ pod: String) -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let host = Bundle(for: BundleToken.self)
        return host.url(forResource: pod, withExtension: "bundle").flatMap(Bundle.init(url:)) ?? host
        #endif
    }
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif
#endif
