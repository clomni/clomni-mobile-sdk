#!/bin/bash
# Before an iOS release: one version everywhere. The tag (SwiftPM resolves the package by it, CocoaPods fetches the
# source by it), ClomniMessenger.podspec, SDKInfo.version (sdk_version and the X-Clomni-SDK header) and a section of
# ios/CHANGELOG.md must agree. With --release the section must no longer say "(unreleased)".
#   scripts/ios-release-check.sh 1.0.0 [--release]
# Prints the changelog section, the release notes. Runs anywhere (bash, grep, sed).
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:?version, e.g. 1.0.0}
release=${2:-}

fail() { echo "ios-release-check: $*" >&2; exit 1; }

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "\"$version\" is not MAJOR.MINOR.PATCH (SwiftPM reads tags as semantic versions)"
podspec=$(sed -n "s/^ *s\.version *= *'\(.*\)'.*/\1/p" ClomniMessenger.podspec)
[ "$podspec" = "$version" ] || fail "ClomniMessenger.podspec says $podspec, not $version"
sdk=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' ios/Sources/ClomniCore/SDKInfo.swift)
[ "$sdk" = "$version" ] || fail "SDKInfo.version says $sdk, not $version"
heading=$(grep -E "^## ${version//./\\.}( |$)" ios/CHANGELOG.md || true)
[ -n "$heading" ] || fail "ios/CHANGELOG.md has no \"## $version\" section"
if [ "$release" = "--release" ] && [[ $heading == *unreleased* ]]; then
  fail "ios/CHANGELOG.md still calls $version unreleased"
fi
# The section's text, up to the next version.
awk -v start="$heading" '$0 == start { found = 1; next } found && /^## / { exit } found { print }' ios/CHANGELOG.md
