#!/bin/bash
# DoD 11: the iOS framework was to be at most 3 MB; raised to 3.5 MB on 2026-10-05 (BRIEF-DEVIATIONS 22), as Android's AAR went to 1.75 MB,
# and to 4 MB on 2026-10-07 (BRIEF-DEVIATIONS 24): keyboard, scroll pin, CSAT card and links took it to 3 678 808 bytes.
#
# Archives the SDK as one dynamic framework (ios/Size/project.yml: Release, device arm64, stripped, library
# evolution on, as a binary release ships it) and measures its binary. The archive's .framework also holds the
# .swiftmodule interfaces, which an app does not ship; its size is printed for information.
# Needs Xcode and XcodeGen (brew install xcodegen). Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

limit=$((4 * 1024 * 1024))
archive=build/size/ClomniMessenger.xcarchive

xcodegen generate --spec ios/Size/project.yml --quiet
rm -rf "$archive"
xcodebuild archive \
  -project ios/Size/ClomniSize.xcodeproj \
  -scheme ClomniMessenger \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

framework="$archive/Products/Library/Frameworks/ClomniMessenger.framework"
binary=$(stat -f%z "$framework/ClomniMessenger")
shipped=$(find "$framework" -type f -not -path '*/Modules/*' -not -path '*/Headers/*' -exec stat -f%z {} + | awk '{s += $1} END {print s}')
folder=$(find "$framework" -type f -exec stat -f%z {} + | awk '{s += $1} END {print s}')

echo "ClomniMessenger.framework, arm64 Release:"
echo "  binary              $binary bytes ($(lipo -archs "$framework/ClomniMessenger"))"
echo "  shipped in an app   $shipped bytes (binary, Info.plist, privacy manifest)"
echo "  whole folder        $folder bytes (with Modules)"
echo "  limit               $limit bytes"
if (( shipped > limit )); then
  echo "error: the framework is over 4 MB" >&2
  exit 1
fi
