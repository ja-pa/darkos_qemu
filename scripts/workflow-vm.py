"""Local VM lifecycle. Verify /proc identity before using SSH or stopping a VM."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import socket
import subprocess as sp
import sys
import time

PROJECT = Path(__file__).resolve().parents[1]
WORK = Path(os.environ['WORK_DIR'])
DISK = Path(os.environ['DISK_IMAGE']).resolve()
PORT = int(os.environ.get('SSH_PORT', '2222'))
STATE = WORK / 'state/vm.json'
LOG = WORK / 'logs/workflow/serial.log'

def run(*args, **kw):
    return sp.run(args, check=True, **kw)

def processes():
    result = []
    for p in Path('/proc').glob('[0-9]*'):
        try:
            args = (p / 'cmdline').read_bytes().decode().split('\0')
            if Path(args[0]).name != 'qemu-system-aarch64':
                continue
            drives = [args[i+1] for i, a in enumerate(args[:-1]) if a == '-drive']
            disks = [Path(v[5:]).resolve() for d in drives for v in d.split(',') if v.startswith('file=')]
            forward = f'hostfwd=tcp:127.0.0.1:{PORT}-:22'
            if DISK in disks or any(forward in a for a in args):
                result.append((int(p.name), DISK in disks, any(forward in a for a in args), args))
        except (OSError, UnicodeError, IndexError):
            continue
    return result

def identity(required=True):
    found = processes()
    if len(found) == 1 and found[0][1] and found[0][2]:
        return found[0]
    if found:
        raise RuntimeError('Disk or SSH port belongs to another VM; use a separate disk and SSH_PORT')
    if required:
        raise RuntimeError(f'VM is stopped; run bash vm.sh start (logs: {LOG})')
    return None

def ssh(*args, **kw):
    return run('bash', str(PROJECT / 'scripts/graphics-ssh.sh'), *args, **kw)

def wait_ssh(pid):
    deadline = time.monotonic() + int(os.environ.get('VM_TIMEOUT', '240'))
    while time.monotonic() < deadline:
        current = identity()
        if current[0] != pid:
            raise RuntimeError('VM identity changed while waiting for SSH')
        try:
            ssh('true', stdin=sp.DEVNULL, stdout=sp.DEVNULL, stderr=sp.DEVNULL,
                timeout=min(10, max(1, deadline - time.monotonic())))
            return
        except (sp.CalledProcessError, sp.TimeoutExpired):
            time.sleep(1)
    raise RuntimeError(f'SSH timed out; inspect {LOG}. VM left running for diagnosis')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'stop', 'status', 'verify', 'check'])
    parser.add_argument('mode', nargs='?', default='gtk-gl', choices=['serial', 'gtk-gl'])
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()
    if not 1 <= PORT <= 65535:
        raise RuntimeError('SSH_PORT must be between 1 and 65535')
    if os.environ.get('SSH_HOST', '127.0.0.1') not in ('localhost', '127.0.0.1'):
        raise RuntimeError('Managed VM requires localhost SSH')
    if args.action == 'status':
        current = identity(False)
        if not args.quiet:
            print(f'Running PID {current[0]}: {DISK}' if current else f'Stopped: {DISK}')
        return 0 if current else 1
    if args.action == 'start':
        current = identity(False)
        if current:
            if args.mode == 'gtk-gl' and not any('virtio-gpu-gl-pci' in a for a in current[3]):
                raise RuntimeError('VM is in serial mode; stop it before starting gtk-gl')
            wait_ssh(current[0])
            return 0
        # A listening non-QEMU service must never be mistaken for our guest.
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', PORT))
        with LOG.open('ab') as out:
            process = sp.Popen(['bash', str(PROJECT / 'scripts/run-qemu.sh'), args.mode],
                               stdin=sp.DEVNULL, stdout=out, stderr=out, start_new_session=True)
        STATE.write_text(json.dumps({'pid': process.pid, 'disk': str(DISK), 'port': PORT, 'mode': args.mode}))
        time.sleep(1)
        if process.poll() is not None:
            raise RuntimeError(f'QEMU exited {process.returncode}; inspect {LOG}')
        wait_ssh(identity()[0])
        print(f'VM ready: SSH 127.0.0.1:{PORT}; log {LOG}')
    elif args.action == 'stop':
        current = identity(False)
        if not current:
            print('VM already stopped')
            return 0
        ssh('sudo -n systemctl poweroff', stdin=sp.DEVNULL, timeout=20)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if not identity(False):
                STATE.unlink(missing_ok=True)
                print('Guest shut down cleanly')
                return 0
            time.sleep(1)
        raise RuntimeError(f'Poweroff timed out; VM left running. Inspect {LOG}')
    elif args.action == 'verify':
        current = identity()
        wait_ssh(current[0])
    elif args.action == 'check':
        if identity(False):
            raise RuntimeError('Stop the VM before checking the disk')
        run('qemu-img', 'check', '-f', 'qcow2', str(DISK))
    return 0

if __name__ == '__main__':
    try:
        if len(sys.argv) > 1 and sys.argv[1] in ('start', 'stop', 'check'):
            with (WORK / 'state/vm.lock').open('w') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError('Another VM lifecycle operation is in progress')
                sys.exit(main())
        else:
            sys.exit(main())
    except (RuntimeError, OSError, sp.CalledProcessError, sp.TimeoutExpired, ValueError) as error:
        sys.exit(f'Error: {error}')
