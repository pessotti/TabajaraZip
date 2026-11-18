#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraWorkspaceTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -D SNAPSHOT_TEST -target arm64-apple-macosx14.0 -parse-as-library Sources/*.swift Tests/WorkspaceTests.swift -o "$test_dir/WorkspaceTests" -framework SwiftUI -framework AppKit -framework QuickLookUI -framework PDFKit -framework AppIntents -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
TABAJARA_7ZZ="$PWD/TabajaraZip.app/Contents/Resources/Tools/7zz" "$test_dir/WorkspaceTests"
