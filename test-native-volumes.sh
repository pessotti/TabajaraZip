#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export TABAJARA_7ZZ="$PWD/Resources/Tools/7zz"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraVolumes.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library Sources/ArchiveEngine.swift Tests/NativeVolumeTests.swift -framework Security -o "$test_dir/NativeVolumeTests" -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
"$test_dir/NativeVolumeTests"
