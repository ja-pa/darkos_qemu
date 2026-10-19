"""Directory bundles with verified checksums and no external qcow2 backing paths."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess as sp
import sys

PROJECT = Path(__file__).resolve().parents[1]
WORK = Path(os.environ['WORK_DIR'])
DISK = Path(os.environ['DISK_IMAGE'])
KERNEL = Path(os.environ['KERNEL_IMAGE'])

def run(*args, **kwargs):
    return sp.run(args, check=True, **kwargs)

def checksum(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(4 * 1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def seal(directory, kind):
    files = {}
    for path in sorted(directory.rglob('*')):
        if path != directory / 'bundle.json' and path.is_file() and not path.is_symlink():
            files[str(path.relative_to(directory))] = checksum(path)
    (directory / 'bundle.json').write_text(json.dumps({'format': 1, 'kind': kind, 'files': files}, indent=2) + '\n')

def verify(directory, kind):
    data = json.loads((directory / 'bundle.json').read_text())
    if data['format'] != 1 or data['kind'] != kind:
        raise ValueError('Unexpected bundle format/type')
    for name, expected in data['files'].items():
        path = directory / name
        if path.is_symlink() or not path.resolve().is_relative_to(directory.resolve()) or checksum(path) != expected:
            raise ValueError(f'Bundle checksum/path failure: {name}')
    if kind == 'runtime':
        for name in ['runtime.qcow2', 'Image', 'runtime-id', 'provenance.json', 'LICENSES.txt']:
            if name not in data['files']:
                raise ValueError(f'Missing bundle member: {name}')
    return data

def main():
    action, argument = sys.argv[1:]
    destination = Path(argument).resolve()
    if action.startswith('export'):
        stage = destination.with_name(destination.name + '.partial')
        if destination.exists() or stage.exists():
            raise ValueError('Export destination or .partial already exists; move it aside explicitly')
        if action == 'export-sdk':
            run(sys.executable, str(PROJECT / 'scripts/workflow-sdk.py'), 'check')
            stage.mkdir(parents=True)
            shutil.copytree(WORK / 'sdk/sysroot', stage / 'sysroot', symlinks=True)
            for name in ['runtime-id', 'manifest.json', 'environment.sh', 'toolchain.cmake', 'packages.tsv']:
                shutil.copy2(WORK / 'sdk' / name, stage / name)
            # SDK carries target development files; compiler is installed on host.
            (stage / 'LICENSES.txt').write_text('Target package versions: packages.tsv. Target licenses: sysroot/usr/share/doc.\nCompiler: host GCC 12, installed by setup.sh. Project recipes: accompanying repository; no new license grant is implied.\n')
            seal(stage, 'sdk')
        else:
            stage.mkdir(parents=True)
            run('qemu-img', 'convert', '-p', '-T', 'none', '-t', 'none', '-f', 'qcow2', '-O', 'qcow2', str(DISK), str(stage / 'runtime.qcow2'))
            command = ['bash', str(PROJECT / 'scripts/workflow-sanitize.sh'), str(stage / 'runtime.qcow2')]
            run(*((['sudo'] if os.geteuid() else []) + command))
            run('qemu-img', 'check', str(stage / 'runtime.qcow2'))
            shutil.copy2(KERNEL, stage / 'Image')
            shutil.copy2(WORK / 'state/runtime-id', stage / 'runtime-id')
            (stage / 'provenance.json').write_text(json.dumps({
                'format': 1, 'repository': 'https://github.com/ja-pa/darkos_qemu',
                'revision': sp.check_output(['git', '-C', str(PROJECT), 'rev-parse', 'HEAD'], text=True).strip(),
                'worktree_dirty': bool(sp.check_output(['git', '-C', str(PROJECT), 'status', '--porcelain'], text=True).strip()),
                'recipe_sha256': {str(p.relative_to(PROJECT)): checksum(p) for p in sorted(
                    [PROJECT / n for n in ['setup.sh', 'sdk.sh', 'build.sh', 'vm.sh']] +
                    [p for folder in ['scripts', 'patches', 'configs', 'fixtures', 'demos']
                     for p in (PROJECT / folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts])},
                'upstream_image': 'https://github.com/christianhaitian/dArkOS/releases#release-v01302026',
                'kernel_commit': 'bef65b1793524bc7bd27c4d70d0ce59cbebee032',
                'runtime_id': (stage / 'runtime-id').read_text().strip()}, indent=2) + '\n')
            (stage / 'LICENSES.txt').write_text('Local development export; no public distribution performed.\n'
                'Original dArkOS: provenance.json. Package copyright notices remain in /usr/share/doc inside the image.\n'
                'Linux kernel: GPL-2.0, pinned source https://github.com/ja-pa/kernel_5_10_226/tree/bef65b1793524bc7bd27c4d70d0ce59cbebee032\n'
                'ES, Peanut-GB and game sources/licenses: docs/emulationstation.md and docs/gameboy.md in the project.\n'
                'Tobu Tobu Girl: Tangram Games; music potato-tan. Game code MIT; assets CC BY 4.0.\n'
                'https://github.com/SimonLarsen/tobutobugirl https://creativecommons.org/licenses/by/4.0/\n'
                'Review all original-image components and source obligations before any public distribution.\n')
            seal(stage, 'runtime')
        stage.rename(destination)
        print(f'Export complete: {destination}')
    elif action == 'import-runtime':
        verify(destination, 'runtime')
        info = json.loads(sp.check_output(['qemu-img', 'info', '--output=json', str(destination / 'runtime.qcow2')]))
        if info['format'] != 'qcow2' or 'backing-filename' in info:
            raise ValueError('Runtime bundle must be standalone qcow2')
        if KERNEL.exists() and checksum(KERNEL) != checksum(destination / 'Image'):
            raise ValueError('Existing kernel differs; use a new WORK_DIR')
        marker = WORK / 'state/imported-runtime.json'
        identity = checksum(destination / 'bundle.json')
        if DISK.exists():
            if not marker.exists() or json.loads(marker.read_text())['bundle_sha256'] != identity:
                raise ValueError('Working disk already exists and is not this imported bundle')
        else:
            temporary = DISK.with_suffix('.partial')
            if temporary.exists():
                raise ValueError('Interrupted disk import; move .partial aside')
            run('qemu-img', 'convert', '-T', 'none', '-t', 'none', '-f', 'qcow2', '-O', 'qcow2', str(destination / 'runtime.qcow2'), str(temporary))
            temporary.rename(DISK)
            marker.write_text(json.dumps({'bundle_sha256': identity}))
        KERNEL.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(destination / 'Image', KERNEL)
        shutil.copy2(destination / 'runtime-id', WORK / 'state/runtime-id')
        (WORK / 'state/import-profile').touch()
    elif action == 'import-sdk':
        verify(destination, 'sdk')
        target = WORK / 'sdk'
        if target.exists():
            if (target / 'bundle.json').exists() and checksum(target / 'bundle.json') == checksum(destination / 'bundle.json'):
                verify(target, 'sdk')
                print('This SDK is already imported')
                return
            raise ValueError('SDK destination exists; use a new WORK_DIR or move SDK aside')
        # Validate links before copying, including directory symlinks.
        for path in destination.rglob('*'):
            if path.is_symlink() and (os.readlink(path).startswith('/') or not path.resolve().is_relative_to(destination)):
                raise ValueError(f'SDK symlink escapes bundle: {path}')
        shutil.copytree(destination, target, symlinks=True)
    else:
        raise ValueError('Unknown bundle action')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, sp.CalledProcessError) as error:
        sys.exit(f'Error: {error}')
