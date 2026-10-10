Pod::Spec.new do |s|
  s.name = 'ClomniMessenger'
  s.version = '1.0.3'
  s.summary = 'Clomni Messenger for iOS apps: native chat, flow buttons and push replies.'
  s.description = <<~DESC
    Opens the Clomni Messenger inside your own iOS app. Your users write to your team in Clomni, the flows built for
    your website chat run with native buttons, and operator replies arrive as push notifications.
  DESC
  s.homepage = 'https://clomni.ai'
  s.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author = 'Clomni'
  s.source = { :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  # The language mode, as Package.swift builds it (tools 5.9, Swift 5 mode). Xcode's SWIFT_VERSION takes only 4.0,
  # 4.2, 5.0 or 6.0; the compiler must still be Swift 5.9 or later (Xcode 15): the sources use `package` access.
  s.swift_versions = ['5.0']
  s.cocoapods_version = '>= 1.12'
  s.readme = "https://github.com/clomni/clomni-mobile-sdk/blob/#{s.version}/README.md"
  s.changelog = "https://github.com/clomni/clomni-mobile-sdk/blob/#{s.version}/ios/CHANGELOG.md"

  # All four SwiftPM targets compile into this one module; system frameworks only. What is not the app's to use is
  # declared `package` (SwiftPM shares it between its four modules); here the package is this module alone, so
  # the app sees only the `public` facade.
  s.source_files = 'ios/Sources/**/*.swift'
  # Release is optimised for size: the SDK lives inside someone else's app (DoD 11, at most 3.5 MB).
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name ClomniMessenger',
                            'SWIFT_OPTIMIZATION_LEVEL[config=Release]' => '-Osize' }
  # What the SDK collects and which required-reason APIs it calls (none), for the app's privacy report.
  # The message sound (Universfield, Pixabay Content License; see NOTICE).
  s.resource_bundles = {
    'ClomniMessenger_Privacy' => ['ios/Sources/ClomniMessenger/PrivacyInfo.xcprivacy'],
    'ClomniMessenger_Sounds' => ['ios/Sources/ClomniMessenger/Sounds/*.mp3'],
    # The launcher's mascot: the operator's line drawing, shrunk to 30, 60 and 90 px.
    'ClomniMessenger_Media' => ['ios/Sources/ClomniMessenger/Media.xcassets'],
  }
  s.frameworks = 'Foundation', 'Security', 'UIKit', 'SwiftUI', 'PhotosUI', 'UniformTypeIdentifiers', 'UserNotifications', 'AVFoundation', 'Network'
end
