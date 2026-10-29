"""Export Chrome raster icons from the approved Nextshot Icon Composer source."""
from pathlib import Path
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
tool = Path('/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool')
output = root / 'browser-extension/public/icons'
output.mkdir(parents=True, exist_ok=True)
for size in (16, 24, 32, 48, 128):
    target = output / f'nextshot-{size}.png'
    subprocess.run([str(tool), str(root / 'Branding/Nextshot.icon'), '--export-image',
        '--output-file', str(target), '--platform', 'macOS', '--rendition', 'Default',
        '--width', str(size), '--height', str(size), '--scale', '1'], check=True, capture_output=True)
    data = target.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (size, size):
        raise SystemExit(f'Invalid exported icon: {target}')
    print(f'{target.relative_to(root)}: {size} by {size}')
