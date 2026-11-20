#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraBulkTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
export BULK_TEST_ROOT="$test_dir"
export TABAJARA_LOG_DIRECTORY="$test_dir/logs"
export REAL_7ZZ="$PWD/Resources/Tools/7zz"
python3 - <<'PY'
import os,pathlib,zipfile
root=pathlib.Path(os.environ['BULK_TEST_ROOT'])
with zipfile.ZipFile(root/'many.zip','w',zipfile.ZIP_DEFLATED) as z:
 for n in reversed(range(2000)):
  name=f'pasta {n%15}/ação[{n}]*.txt'
  z.writestr(name,'content:'+name)
 z.writestr('vazia/',b'')
 z.writestr('zero.bin',b'')
(root/'tool').write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$BULK_TEST_ROOT/calls"\nif [ "$BULK_CORRUPT_STREAM" = "1" ] && [ "$1" = "x" ]; then exec python3 "$BULK_TEST_ROOT/corrupt.py" "$@"; fi\nexec "$REAL_7ZZ" "$@"\n')
(root/'tool').chmod(0o700)
(root/'corrupt.py').write_text("import os,sys,subprocess\np=subprocess.run([os.environ['REAL_7ZZ']]+sys.argv[1:],stdout=subprocess.PIPE)\nif p.returncode: sys.exit(p.returncode)\ndata=bytearray(p.stdout)\nif data: data[0]^=1\nsys.stdout.buffer.write(data)\n")
PY
export TABAJARA_7ZZ="$test_dir/tool"
swiftc -parse-as-library Sources/ArchiveEngine.swift Tests/BulkExtractionTests.swift -o "$test_dir/BulkExtractionTests" -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
"$test_dir/BulkExtractionTests"
