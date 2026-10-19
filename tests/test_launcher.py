"""Launcher contract checks; requires host QEMU, never starts a VM."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

LAUNCHER = Path(__file__).resolve().parents[1] / 'scripts/run-qemu.sh'


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='darkos launcher ')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.kernel = self.path / 'kernel Image'
        self.kernel.write_bytes(b'test kernel artifact')
        self.raw = self.path / 'base.img'
        self.raw.write_bytes(bytes(4096))
        self.overlay = self.path / 'disk.qcow2'
        subprocess.run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'raw', '-b',
                        str(self.raw), str(self.overlay)], check=True, capture_output=True)
        self.env = dict(os.environ, KERNEL_IMAGE=str(self.kernel),
                        DISK_IMAGE=str(self.overlay), SSH_PORT='2222')

    def run_launcher(self, *arguments, **env):
        return subprocess.run(['bash', str(LAUNCHER), *arguments],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_serial_and_space_paths(self):
        result = self.run_launcher('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-accel tcg', result.stdout)
        self.assertIn('-display none', result.stdout)
        self.assertIn('127.0.0.1:2222-:22', result.stdout)
        self.assertIn('rootfstype=btrfs', result.stdout)
        self.assertNotIn('gtk', result.stdout)

    def test_graphics_command_preserved(self):
        result = self.run_launcher('gtk-gl', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('virtio-gpu-gl-pci', result.stdout)
        self.assertIn('hostmem=512M', result.stdout)
        self.assertIn('gtk', result.stdout)

    def test_rejects_raw_image(self):
        result = self.run_launcher('--dry-run', DISK_IMAGE=str(self.raw))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('qcow2 overlay', result.stderr)

    def test_missing_artifacts(self):
        for variable, expected in [('KERNEL_IMAGE', 'Missing kernel'), ('DISK_IMAGE', 'Missing overlay')]:
            with self.subTest(variable=variable):
                result = self.run_launcher('--dry-run', **{variable: str(self.path / 'absent')})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)

    def test_bad_ports(self):
        for port in ['0', '65536', '-1', 'abc', '2222,hostfwd=tcp::1-:1']:
            with self.subTest(port=port):
                result = self.run_launcher('--dry-run', SSH_PORT=port)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('SSH_PORT', result.stderr)

    def test_unknown_argument(self):
        result = self.run_launcher('--invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown argument', result.stderr)


if __name__ == '__main__':
    unittest.main()
