#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraViewTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -D SNAPSHOT_TEST -target arm64-apple-macosx14.0 -parse-as-library Sources/*.swift Tests/ViewModeSnapshots.swift -o "$test_dir/ViewModeSnapshots" -framework SwiftUI -framework AppKit -framework QuickLookUI -framework PDFKit -framework AppIntents -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
"$test_dir/ViewModeSnapshots" "${1:-/private/tmp/TabajaraViewModes}"
