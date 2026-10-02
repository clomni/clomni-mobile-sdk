# The iOS side of clomni_flutter (CocoaPods; Flutter's Swift Package Manager support uses clomni_flutter/Package.swift).
Pod::Spec.new do |s|
  s.name             = 'clomni_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Clomni Messenger for Flutter: the native iOS and Android SDKs behind one Dart API.'
  s.homepage         = 'https://clomni.ai'
  s.license          = { :type => 'Commercial', :text => 'Copyright (c) Clomni. All rights reserved.' }
  s.author           = 'Clomni'
  s.source           = { :path => '.' }
  s.source_files     = 'clomni_flutter/Sources/clomni_flutter/**/*.swift'
  s.dependency 'Flutter'
  # The iOS SDK. Before it is published, the app's Podfile takes it from a checkout (README.md).
  s.dependency 'ClomniMessenger', '~> 1.0'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
