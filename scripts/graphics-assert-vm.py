#!/usr/bin/env python3
"""Reject graphics setup unless the selected local VM uses an isolated disk."""
import os
from pathlib import Path
import sys

work = Path(os.environ.get('WORK_DIR', str(Path.home() / 'darkos-qemu-work')))
expected = Path(os.environ.get('DISK_IMAGE', str(work / 'images/graphics.qcow2'))).resolve()
base = Path(os.environ.get('BASE_DISK_IMAGE', str(work / 'images/darkos.qcow2'))).resolve()
raw = Path(os.environ.get('RAW_IMAGE', str(work / 'images/dArkOS_RG353m_trixie_01312026.img'))).resolve()
if expected in (base, raw):
    sys.exit('Refusing graphics changes to the base/primary disk; select its isolated copy')
if os.environ.get('SSH_HOST', '127.0.0.1') not in ('localhost', '127.0.0.1'):
    sys.exit('Graphics helper verifies local WSL QEMU instances only')
forward = 'hostfwd=tcp:127.0.0.1:' + os.environ.get('SSH_PORT', '2222') + '-:22'
matches = []
for process in Path('/proc').glob('[0-9]*'):
    try:
        arguments = (process / 'cmdline').read_bytes().decode().split('\0')
        if not arguments or Path(arguments[0]).name != 'qemu-system-aarch64':
            continue
        drives = [arguments[i+1] for i, value in enumerate(arguments[:-1]) if value == '-drive']
        images = [part[5:] for drive in drives for part in drive.split(',') if part.startswith('file=')]
        paths = [(Path(image) if Path(image).is_absolute() else (process / 'cwd') / image).resolve() for image in images]
        if expected in paths and any(forward in argument for argument in arguments):
            if not any('virtio-gpu-gl-pci' in argument for argument in arguments):
                sys.exit('Selected VM needs gtk-gl / VirtIO GPU mode')
            matches.append(process.name)
    except (OSError, UnicodeError):
        continue
if len(matches) != 1:
    sys.exit(f'Expected one running gtk-gl VM using {expected} and the selected SSH port; found {len(matches)}')
print(f'Isolated graphics VM verified: PID {matches[0]}, disk {expected}', file=sys.stderr)
