# The iOS side of clomni_flutter under CocoaPods. With Swift Package Manager (on by default in current Flutter, from
# 3.24 behind a flag) Flutter uses clomni_flutter/Package.swift instead, and this file is not read.
Pod::Spec.new do |s|
  s.name             = 'clomni_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Clomni Messenger for Flutter: the native iOS and Android SDKs behind one Dart API.'
  s.homepage         = 'https://clomni.ai'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = 'Clomni'
  s.source           = { :path => '.' }
  s.source_files     = 'clomni_flutter/Sources/clomni_flutter/**/*.swift'
  s.dependency 'Flutter'
  # The iOS SDK is a Swift package, not a CocoaPods trunk pod: with CocoaPods the app's Podfile takes the
  # ClomniMessenger pod from the repository's tag (README.md). Without that line, say so instead of "not found".
  s.dependency 'ClomniMessenger', '~> 1.0'
  podfile = defined?(Pod::Config) ? Pod::Config.instance.podfile : nil
  if podfile && podfile.dependencies.none? { |d| d.root_name == 'ClomniMessenger' }
    raise Pod::Informative, "clomni_flutter: the iOS SDK is not on CocoaPods trunk. Add to ios/Podfile, in target " \
      "'Runner': pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0' " \
      "(or turn on Swift Package Manager: flutter config --enable-swift-package-manager)"
  end
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
