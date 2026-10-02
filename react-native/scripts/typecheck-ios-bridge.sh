#!/bin/bash
# Type-checks ios/ClomniBridge.swift against the iOS SDK's public API where there is no Xcode (Linux, Swift 5.9+):
# builds ios/Sources as the one ClomniMessenger module CocoaPods makes, then checks the bridge with its @objc
# attributes taken out (Linux has no Objective-C runtime). RCTClomni.mm needs Xcode and React Native's headers.
#   SWIFTC=/path/to/swiftc react-native/scripts/typecheck-ios-bridge.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
swiftc=${SWIFTC:-swiftc}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$swiftc" -parse-as-library -module-name ClomniMessenger -package-name ClomniMessenger -emit-module \
  -emit-module-path "$work/ClomniMessenger.swiftmodule" $(find ios/Sources -name '*.swift')
sed -E -e '/^[[:space:]]*@objc\(.*\)[[:space:]]*$/d' -e 's/@objc //' react-native/ios/ClomniBridge.swift \
  > "$work/ClomniBridge.swift"
"$swiftc" -typecheck -I "$work" "$work/ClomniBridge.swift"
echo "ClomniBridge.swift type-checks against ClomniMessenger"
