require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# The iOS side of @clomni/react-native: RCTClomni (the native module "Clomni") and ClomniBridge, over the iOS SDK.
Pod::Spec.new do |s|
  s.name         = "ClomniReactNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author       = "Clomni"
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/clomni/clomni-mobile-sdk.git", :tag => "react-native-#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.swift_version = "5.0"
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES" }

  # The iOS SDK is a Swift package (the repository's Package.swift, tags 1.0.0 …), not a CocoaPods trunk pod.
  # React Native 0.75+ adds it to the Pods project with spm_dependency. An app whose Podfile names the
  # ClomniMessenger pod itself (from git or a checkout, e.g. the Expo plugin's localSdk) gets that pod instead.
  # The Podfile's text, not Pod::Config#podfile: use_native_modules! loads this podspec while the Podfile is still
  # being evaluated, and asking CocoaPods for the Podfile then fails ("undefined method '[]' for nil", 37778737706).
  podfile_path = defined?(Pod::Config) ? File.join(Pod::Config.instance.installation_root.to_s, "Podfile") : nil
  sdk_pod = podfile_path && File.exist?(podfile_path) &&
            File.read(podfile_path).match?(/^\s*pod\s+["']ClomniMessenger["']/)
  if sdk_pod
    s.dependency "ClomniMessenger", "~> 1.0"
  elsif respond_to?(:spm_dependency, true)
    spm_dependency(s,
      url: "https://github.com/clomni/clomni-mobile-sdk.git",
      requirement: { "kind" => "upToNextMajorVersion", "minimumVersion" => "1.0.3" },
      products: ["ClomniMessenger"])
  else
    raise Pod::Informative, "@clomni/react-native needs React Native 0.75 or later: the iOS SDK comes through Swift " \
      "Package Manager (spm_dependency). On an older version, add to the Podfile: " \
      "pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.3'"
  end

  # React Native 0.71+: React-Core, and in the New Architecture codegen's ClomniSpec and the TurboModule headers.
  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency "React-Core"
  end
end
