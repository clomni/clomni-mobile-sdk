# Clomni Example (iOS)

A ride app's profile screen with the messenger behind its own buttons: "Dəstək" (`present`), "Problem bildir"
(`startFlow` with the ride), login and logout, the unread count on the button, the optional launcher, and push with the
operator's photo ([../Examples/NotificationService](../Examples/NotificationService)). The integration code in
[ClomniExample](ClomniExample) is the one the customer documentation shows, and CI compiles it.

```sh
brew install xcodegen
cd ios/Example
xcodegen generate
open ClomniExample.xcodeproj
```

Before running: the App ID and iOS API key from Clomni (Channels → Mobile app) in `AppDelegate.swift`, and a team for
signing. Push needs a real device or a Simulator on macOS 13+, and the APNs key (.p8) in the Clomni panel.
