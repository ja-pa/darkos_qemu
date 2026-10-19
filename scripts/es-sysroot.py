"""Normalize absolute symlinks in a copied guest sysroot, never the guest."""
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
if root == Path('/') or not (root / 'usr/include').is_dir():
    raise SystemExit('Expected a copied sysroot containing usr/include')
for directory, dirs, files in os.walk(root, followlinks=False):
    for name in dirs + files:
        path = Path(directory) / name
        if path.is_symlink():
            target = os.readlink(path)
            if target.startswith('/'):
                path.unlink()
                path.symlink_to(os.path.relpath(root / target.lstrip('/'), path.parent))
# Prefer the guest's runtime over Ubuntu's newer cross runtime at link time.
lib = root / 'usr/lib/aarch64-linux-gnu'
loader = root / 'usr/lib/ld-linux-aarch64.so.1'
if not loader.exists() and not loader.is_symlink() and (lib / loader.name).exists():
    loader.symlink_to('aarch64-linux-gnu/' + loader.name)
for development, runtime in [('libstdc++.so', 'libstdc++.so.6'), ('libgcc_s.so', 'libgcc_s.so.1')]:
    path = lib / development
    if not path.exists() and not path.is_symlink() and (lib / runtime).exists():
        path.symlink_to(runtime)
# Extracted Debian packages retain /usr in .pc files. Relocate only private
# metadata so generic pkg-config builds use the isolated SDL/Mesa headers/libs.
private = root / 'opt/darkos-graphics/usr/lib/aarch64-linux-gnu/pkgconfig'
for path in private.glob('*.pc'):
    text = re.sub(r'^(prefix|exec_prefix|libdir|includedir)=/usr(?=/|$)',
                  r'\1=/opt/darkos-graphics/usr', path.read_text(), flags=re.MULTILINE)
    path.write_text(text)
