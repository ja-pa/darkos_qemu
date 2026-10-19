#!/usr/bin/env python3
"""Boot an offline development overlay, validate via SSH, then power it off."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--name', default='boot-validation')
    args = parser.parse_args()
    work = Path(os.environ.get('WORK_DIR', str(Path.home() / 'darkos-qemu-work')))
    logs = work / 'logs'
    logs.mkdir(parents=True, exist_ok=True)
    key = work / 'ssh/id_ed25519'
    if not key.is_file():
        parser.error('Generate WORK_DIR/ssh/id_ed25519 and run prepare-guest.sh first')
    port = os.environ.get('SSH_PORT', '2222')
    known_hosts = logs / (args.name + '.known_hosts')
    ssh = ['ssh', '-i', str(key), '-p', port, '-o', 'IdentitiesOnly=yes',
           '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3',
           '-o', 'StrictHostKeyChecking=accept-new',
           '-o', 'UserKnownHostsFile=' + str(known_hosts), 'ark@127.0.0.1']
    launcher = Path(__file__).resolve().with_name('run-qemu.sh')
    with (logs / (args.name + '.serial.log')).open('wb') as serial:
        vm = subprocess.Popen(['bash', str(launcher), 'serial'], stdin=subprocess.PIPE,
                              stdout=serial, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                if vm.poll() is not None:
                    raise RuntimeError('QEMU exited before SSH became available')
                probe = subprocess.run(ssh + ['true'], capture_output=True, timeout=10)
                if probe.returncode == 0:
                    break
                (logs / (args.name + '.ssh-probe.log')).write_bytes(probe.stderr)
                time.sleep(3)
            else:
                raise RuntimeError('Timed out waiting for key-authenticated SSH')
            commands = r'''set -eu
echo '=== QEMU GUEST VALIDATION ==='
uname -a
test "$(cat /proc/1/comm)" = systemd
cat /proc/1/comm
findmnt /
findmnt /boot
test "$(findmnt -n -o FSTYPE /)" = btrfs
test -b /dev/vda4
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
systemctl is-active multi-user.target NetworkManager.service ssh.service
ip -4 address
ip route
ip -4 route show default | grep -q default
ping -c 1 -W 5 10.0.2.2
getent ahostsv4 deb.debian.org
echo '=== VALIDATION PASSED ==='
'''
            result = subprocess.run(ssh + [commands], capture_output=True, timeout=90)
            (logs / (args.name + '.guest.log')).write_bytes(result.stdout + result.stderr)
            sys.stdout.buffer.write(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError('Guest checks failed; see guest log')
            # The dArkOS ark account has passwordless sudo; do not change its password.
            subprocess.run(ssh + ['sudo -n /sbin/poweroff'], capture_output=True, timeout=20)
            try:
                vm.wait(timeout=90)
            except subprocess.TimeoutExpired:
                raise RuntimeError('Guest did not power off cleanly')
            if vm.returncode != 0:
                raise RuntimeError('QEMU returned a nonzero status')
        finally:
            if vm.poll() is None:
                vm.terminate()
                try:
                    vm.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    vm.kill()
                    vm.wait()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print('Validation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
