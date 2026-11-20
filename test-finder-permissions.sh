#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraFinderTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
export TABAJARA_7ZZ="$PWD/Resources/Tools/7zz"
export TABAJARA_LOG_DIRECTORY="$test_dir/logs"
swiftc -target arm64-apple-macosx14.0 -parse-as-library Sources/ArchiveEngine.swift Tests/FinderPermissionsTests.swift -o "$test_dir/Tests" -module-cache-path "$test_dir/cache"
"$test_dir/Tests"
