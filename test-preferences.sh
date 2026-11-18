#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraPreferenceTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Sources/SaveSummary.swift Sources/AppPreferences.swift Sources/ArchiveDocument.swift Tests/PreferencesTests.swift -o "$test_dir/PreferencesTests" -framework SwiftUI -framework AppKit -framework QuickLookUI -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
TABAJARA_7ZZ="$PWD/TabajaraZip.app/Contents/Resources/Tools/7zz" "$test_dir/PreferencesTests"
