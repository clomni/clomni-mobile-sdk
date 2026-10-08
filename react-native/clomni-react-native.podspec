require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# The iOS side of @clomni/react-native: RCTClomni (the native module "Clomni") and ClomniBridge, over the iOS SDK.
Pod::Spec.new do |s|
  s.name         = "ClomniReactNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = { :type => "Commercial", :text => "Copyright (c) Clomni. All rights reserved." }
  s.author       = "Clomni"
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/clomni/clomni-mobile-sdk.git", :tag => "react-native-#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.swift_version = "5.0"
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES" }

  s.dependency "ClomniMessenger", "~> 1.0"

  # React Native 0.71+: React-Core, and in the New Architecture codegen's ClomniSpec and the TurboModule headers.
  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency "React-Core"
  end
end
