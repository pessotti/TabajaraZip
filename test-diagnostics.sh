#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraLogTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library Sources/ArchiveEngine.swift Tests/DiagnosticsTests.swift -o "$test_dir/DiagnosticsTests" -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
"$test_dir/DiagnosticsTests"
