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

  # All four SwiftPM targets compile into this one module; system frameworks only.
  s.source_files = 'ios/Sources/**/*.swift'
  s.frameworks = 'Foundation', 'Security', 'UIKit', 'SwiftUI'
end
