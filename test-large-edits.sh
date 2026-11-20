#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraEditTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
export EDIT_TEST_ROOT="$test_dir"
export TABAJARA_LOG_DIRECTORY="$test_dir/logs"
export REAL_7ZZ="$PWD/Resources/Tools/7zz"
python3 - <<'PY'
import os,pathlib,zipfile
root=pathlib.Path(os.environ['EDIT_TEST_ROOT'])
with zipfile.ZipFile(root/'large.zip','w',zipfile.ZIP_DEFLATED) as z:
 z.writestr('Grande ação/',b'');z.writestr('Manter/',b'')
 for n in range(4000):
  name='Grande ação/item-'+f'{n:05d}'+'-'+'x'*150+'.txt';z.writestr(name,'content:'+name)
 for n in range(100):
  name=f'Manter/keep-{n:05d}.txt';z.writestr(name,'content:'+name)
(root/'tool').write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$EDIT_TEST_ROOT/calls"\nexec "$REAL_7ZZ" "$@"\n')
(root/'tool').chmod(0o700)
PY
export TABAJARA_7ZZ="$test_dir/tool"
swiftc -parse-as-library Sources/ArchiveEngine.swift Sources/SaveSummary.swift Sources/AppPreferences.swift Sources/ArchiveDocument.swift Tests/LargeEditTests.swift -o "$test_dir/LargeEditTests" -framework SwiftUI -framework AppKit -framework QuickLookUI -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
"$test_dir/LargeEditTests"
