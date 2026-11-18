#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraToolbarTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Sources/SaveSummary.swift Sources/AppPreferences.swift Sources/ArchiveDocument.swift Sources/NativeToolbar.swift Sources/ArchiveColumnPreferences.swift Sources/ArchiveBreadcrumbs.swift Tests/ToolbarTests.swift -o "$test_dir/ToolbarTests" -framework SwiftUI -framework AppKit -framework QuickLookUI -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
TABAJARA_7ZZ="$PWD/TabajaraZip.app/Contents/Resources/Tools/7zz" "$test_dir/ToolbarTests" "$PWD/TabajaraZip.app/Contents/Resources/AppIcon.icns"
