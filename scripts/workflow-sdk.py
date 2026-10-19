"""Record and validate SDK content independently of its absolute location."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

def inventory(root):
    h = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            target = os.readlink(path)
            if target.startswith('/') or not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'Sysroot symlink escapes SDK: {relative} -> {target}')
            h.update(f'{relative}\0{target}\0'.encode())
        elif path.is_file():
            h.update(relative.encode() + b'\0')
            with path.open('rb') as stream:
                while block := stream.read(1024 * 1024):
                    h.update(block)
    return h.hexdigest()

def main():
    sdk = Path(os.environ['WORK_DIR']) / 'sdk'
    root = Path(os.environ['ES_SYSROOT'])
    lib = root / 'opt/darkos-graphics/usr/lib/aarch64-linux-gnu'
    for name in ['libSDL2.so', 'libEGL.so.1', 'libOpenGL.so.0', 'libGLESv2.so.2', 'libgbm.so.1']:
        path = lib / name
        output = subprocess.check_output(['aarch64-linux-gnu-readelf', '-h', str(path)], text=True)
        if 'AArch64' not in output:
            raise ValueError(f'Not ARM64: {path}')
    data = {'format': 1, 'runtime_id': (sdk / 'runtime-id').read_text().strip(), 'sysroot_sha256': inventory(root)}
    runtime = Path(os.environ['WORK_DIR']) / 'state/runtime-id'
    if runtime.exists() and runtime.read_text().strip() != data['runtime_id']:
        raise ValueError('SDK does not match this runtime; run bash sdk.sh prepare')
    if sys.argv[1] == 'record':
        (sdk / 'manifest.json').write_text(json.dumps(data, indent=2) + '\n')
    elif json.loads((sdk / 'manifest.json').read_text()) != data:
        raise ValueError('SDK content differs from its manifest; run bash sdk.sh prepare')
    print('SDK verified: ' + data['runtime_id'])

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f'Error: {error}')
