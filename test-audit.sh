#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/TabajaraAudit.XXXXXX")"
trap 'chmod -R u+rwX "$test_dir"; rm -rf "$test_dir"' EXIT
export AUDIT_TEST_ROOT="$test_dir"
export TABAJARA_7ZZ="$PWD/Resources/Tools/7zz"
export TABAJARA_LOG_DIRECTORY="$test_dir/logs"
python3 - <<'PY'
import os,pathlib,zipfile,tarfile,io
p=pathlib.Path(os.environ['AUDIT_TEST_ROOT'])
with tarfile.open(p/'dots.tar','w') as t:
 i=tarfile.TarInfo('./');i.type=tarfile.DIRTYPE;t.addfile(i)
 for n in range(12):
  path=f'folder/ação-{n}.txt';data=('content:'+path).encode();i=tarfile.TarInfo('./'+path);i.size=len(data);t.addfile(i,io.BytesIO(data))
with zipfile.ZipFile(p/'dots.zip','w') as z:
 z.writestr('./',b'')
 for n in range(12):
  path=f'folder/ação-{n}.txt';z.writestr('./'+path,'content:'+path)
with zipfile.ZipFile(p/'windows.zip','w') as z:
 for n in range(12):
  path=f'folder/ação-{n}.txt';i=zipfile.ZipInfo(path.replace('/','\\'));i.create_system=0;z.writestr(i,'content:'+path)
for name,path in [('traversal.zip','folder\\..\\outside'),('absolute.zip','\\\\host\\outside'),('drive.zip','C:\\outside')]:
 with zipfile.ZipFile(p/name,'w') as z:
  i=zipfile.ZipInfo(path);i.create_system=0;z.writestr(i,b'unsafe')
with zipfile.ZipFile(p/'aliases.zip','w') as z:
 for name in ['folder\\same.txt','folder/same.txt']:
  i=zipfile.ZipInfo(name);i.create_system=0;z.writestr(i,b'alias')
with tarfile.open(p/'traversal.tar','w') as t:
 i=tarfile.TarInfo('./../outside');i.size=1;t.addfile(i,io.BytesIO(b'x'))
with tarfile.open(p/'fifo.tar','w') as t:
 i=tarfile.TarInfo('pipe');i.type=tarfile.FIFOTYPE;t.addfile(i)
(p/'invalid.zip').write_bytes(b'not an archive')
PY
swiftc -parse-as-library Sources/ArchiveEngine.swift Sources/SaveSummary.swift Sources/AppPreferences.swift Sources/ArchiveDocument.swift Tests/AuditRegressionTests.swift -o "$test_dir/AuditRegressionTests" -framework SwiftUI -framework AppKit -framework QuickLookUI -module-cache-path "${TMPDIR:-/tmp}/zipdesk-module-cache"
"$test_dir/AuditRegressionTests"
