import Foundation

/// How far the conversation lifts its bottom (the composer) for the keyboard (KeyboardProbe, CM-087).
package enum KeyboardInset {
    /// The bottom padding that puts the composer on the keyboard's top. `keyboardHeight`: how far a docked keyboard
    /// reaches up from the screen's bottom (its suggestions, the emoji keyboard's search field, a hardware keyboard's
    /// bar included), nil while it is down or floats. `safeAreaBottom`: how far the screen's content already ends
    /// over the screen's bottom (the home indicator). The keyboard covers that part too, so it is taken off once: added
    /// on top of the keyboard it is the ~40 pt band the operator's iPhone showed over the emoji keyboard.
    package static func padding(keyboardHeight: Double?, safeAreaBottom: Double) -> Double {
        guard let keyboardHeight else { return 0 }
        return max(0, keyboardHeight - safeAreaBottom)
    }
}
