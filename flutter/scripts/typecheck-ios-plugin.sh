#!/bin/bash
# Type-checks ios/clomni_flutter/Sources/clomni_flutter/ClomniFlutterPlugin.swift where there is no Xcode (Linux,
# Swift 5.9+): against the iOS SDK's public API (ios/Sources of this repository, built as the one ClomniMessenger
# module CocoaPods makes) and against scripts/FlutterStub.swift for Flutter's API. UIKit is not used and is taken out.
# An app's build is the real check.
#   SWIFTC=/path/to/swiftc flutter/scripts/typecheck-ios-plugin.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
swiftc=${SWIFTC:-swiftc}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$swiftc" -parse-as-library -module-name ClomniMessenger -package-name ClomniMessenger -emit-module \
  -emit-module-path "$work/ClomniMessenger.swiftmodule" $(find ios/Sources -name '*.swift')
"$swiftc" -parse-as-library -module-name Flutter -emit-module -emit-module-path "$work/Flutter.swiftmodule" \
  flutter/scripts/FlutterStub.swift
sed -e '/^import UIKit$/d' flutter/ios/clomni_flutter/Sources/clomni_flutter/ClomniFlutterPlugin.swift \
  > "$work/ClomniFlutterPlugin.swift"
"$swiftc" -typecheck -I "$work" "$work/ClomniFlutterPlugin.swift"
echo "ClomniFlutterPlugin.swift type-checks against ClomniMessenger and Flutter's plugin API"
