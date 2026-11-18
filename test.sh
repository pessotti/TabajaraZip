#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export TABAJARA_7ZZ="$PWD/TabajaraZip.app/Contents/Resources/Tools/7zz"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cache="${TMPDIR:-/tmp}/zipdesk-module-cache"
swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Tests/EngineTests.swift -o "$test_dir/EngineTests" -module-cache-path "$cache"
"$test_dir/EngineTests"
swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Sources/SaveSummary.swift Sources/AppPreferences.swift Sources/ArchiveDocument.swift Tests/DocumentTests.swift -o "$test_dir/DocumentTests" -framework SwiftUI -framework AppKit -framework QuickLookUI -module-cache-path "$cache"
"$test_dir/DocumentTests"
swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Sources/ArchiveIntents.swift Tests/IntentTests.swift -o "$test_dir/IntentTests" -framework AppIntents -module-cache-path "$cache"
"$test_dir/IntentTests"

swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Tests/DSStoreTests.swift -o "$test_dir/DSStoreTests" -module-cache-path "$cache"
"$test_dir/DSStoreTests"

swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Tests/ZIPCompatibilityTests.swift -o "$test_dir/ZIPCompatibilityTests" -module-cache-path "$cache"
"$test_dir/ZIPCompatibilityTests"

swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Sources/SaveSummary.swift Tests/SaveSummaryTests.swift -o "$test_dir/SaveSummaryTests" -module-cache-path "$cache"
"$test_dir/SaveSummaryTests"
