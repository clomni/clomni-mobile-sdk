Pod::Spec.new do |s|
  s.name = 'ClomniMessenger'
  s.version = '1.0.0'
  s.summary = 'Clomni Messenger for iOS apps: native chat, flow buttons and push replies.'
  s.description = <<~DESC
    Opens the Clomni Messenger inside your own iOS app. Your users write to your team in Clomni, the flows built for
    your website chat run with native buttons, and operator replies arrive as push notifications.
  DESC
  s.homepage = 'https://clomni.ai'
  s.license = { :type => 'Commercial', :text => 'Copyright (c) Clomni. All rights reserved.' }
  s.author = 'Clomni'
  s.source = { :git => 'https://github.com/rzayevkenann/clomni-mobile-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions = ['5.9']

  # All four SwiftPM targets compile into this one module; system frameworks only. What is not the app's to use is
  # declared `package` (SwiftPM shares it between its four modules); here the package is this module alone, so
  # the app sees only the `public` facade.
  s.source_files = 'ios/Sources/**/*.swift'
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name ClomniMessenger' }
  # What the SDK collects and which required-reason APIs it calls (none), for the app's privacy report.
  s.resource_bundles = { 'ClomniMessenger_Privacy' => ['ios/Sources/ClomniMessenger/PrivacyInfo.xcprivacy'] }
  s.frameworks = 'Foundation', 'Security', 'UIKit', 'SwiftUI', 'PhotosUI', 'UniformTypeIdentifiers', 'UserNotifications'
end
