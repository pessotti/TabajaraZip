#!/usr/bin/env python3
"""Package the generated artwork into standard macOS icon sizes without changing its design."""
from pathlib import Path
import struct
import subprocess
import tempfile

project = Path(__file__).resolve().parents[1]
source = project / 'Assets/Tabajara-AppIcon.png'
resources = project / 'TabajaraZip.app/Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
# PNG representations are natively supported in ICNS, including Retina variants.
representations = [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128),
                   ('ic08', 256), ('ic09', 512), ('ic10', 1024),
                   ('ic11', 32), ('ic12', 64), ('ic13', 256), ('ic14', 512)]
chunks = []
with tempfile.TemporaryDirectory(prefix='TabajaraIcon-') as temp:
    for tag, size in representations:
        output = Path(temp) / (tag + '.png')
        subprocess.run(['/usr/bin/sips', '-z', str(size), str(size), str(source), '--out', str(output)], check=True, stdout=subprocess.DEVNULL)
        png = output.read_bytes()
        chunks.append(tag.encode('ascii') + struct.pack('>I', len(png) + 8) + png)
        if size == 1024:
            (resources / 'AppIconPreview.png').write_bytes(png)
    data = b''.join(chunks)
    (resources / 'AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(data) + 8) + data)
