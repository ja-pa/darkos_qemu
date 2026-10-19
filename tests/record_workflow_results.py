"""Collect small validation artifacts; never copy images, ROMs or the SDK."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess as sp
import sys
import tarfile

source, imported, runtime, sdk = [Path(p) for p in sys.argv[1:]]
evidence = Path(__file__).resolve().parents[1] / 'docs/evidence/workflow'
evidence.mkdir(parents=True, exist_ok=True)

def copy(path, name=None):
    shutil.copy2(path, evidence / (name or path.name))

for name in ['setup-repeat.log', 'sdk-prepare.log', 'sdk-repeat.log', 'build-all.log',
             'build-app.log', 'deploy-all.log', 'es-run.log', 'es-audit.log',
             'es-after-cycles.log', 'gb-audit.log', 'gb-cycle2-audit.log',
             'gb-cycle3-audit.log', 'gles-regression.log', 'profile-validation.log',
             'redeploy-all.log', 'reset-profile.log', 'rejected-active-deploy.log',
             'rejected-foreign-vm.log', 'rejected-active-check.log',
             'rejected-sdk-mismatch.log', 'rejected-serial-es.log', 'source-cleanup.log',
             'export-sdk.log', 'export-runtime.log', 'image-check.log', 'shutdown.log']:
    copy(source / 'logs/workflow' / name)
for name in ['import-sdk.log', 'relocated-build.log', 'import-runtime.log',
             'import-validation.log', 'reimport-sdk.log', 'offline-sdk-check.log',
             'imported-es.log', 'imported-es-repeat.log', 'image-check.log', 'shutdown.log']:
    copy(imported / 'logs/workflow' / name, 'import-' + name)
for name in ['archive.sha256', 'archive-test.log', 'archive-extract.log', 'base-image.sha256']:
    copy(source / 'logs' / name)
copy(source / 'sdk/manifest.json', 'sdk-manifest.json')
copy(source / 'sdk/packages.tsv', 'guest-packages.tsv')
copy(source / 'logs/es/build-manifest.log', 'es-build-manifest.log')
copy(source / 'logs/es/elf.log', 'es-elf.log')
copy(source / 'logs/gb/build-manifest.log', 'gb-build-manifest.log')
copy(source / 'logs/gb/elf.log', 'gb-elf.log')
copy(runtime / 'bundle.json', 'runtime-bundle.json')
copy(runtime / 'provenance.json', 'runtime-provenance.json')
copy(imported / 'apps/sdk-app/compile_commands.json', 'relocated-compile-commands.json')

for work, prefix, members in [
    (source, '', ['opt/darkos-emulators/peanut-gb/logs/emulator.maps',
                  'opt/darkos-emulators/peanut-gb/logs/emulator.ldd',
                  'opt/darkos-graphics/logs/packages.sha256',
                  'opt/darkos-es/logs/desktop-gl.sha256']),
    (imported, 'import-', ['opt/darkos-es/logs/es.maps', 'opt/darkos-es/logs/es.ldd',
                          'opt/darkos-workflow/logs/runtime.log']),
]:
    with tarfile.open(work / 'logs/workflow/guest-logs.tar') as archive:
        for name in members:
            stream = archive.extractfile(name)
            assert stream is not None
            (evidence / (prefix + Path(name).name)).write_bytes(stream.read())

text = (source / 'logs/workflow/es-run.log').read_text()
cycles = re.findall(r'Emulator PID=(\d+).*?Presented frames=(\d+) elapsed_ms=(\d+).*?Emulator exit status: (\d+)', text, re.S)
assert len(cycles) >= 3
accepted = [{'pid': int(pid), 'frames': int(frames), 'elapsed_ms': int(ms), 'exit': int(code)}
            for pid, frames, ms, code in cycles[:3]]
assert all(c['elapsed_ms'] >= 60000 and c['exit'] == 0 for c in accepted)
demo = re.search(r'^frames=(\d+) elapsed_ms=(\d+)$', text, re.M)
assert demo is not None
info = json.loads(sp.check_output(['qemu-img', 'info', '--output=json', str(runtime / 'runtime.qcow2')]))
assert 'backing-filename' not in info

def size(path):
    return int(sp.check_output(['du', '-s', '-B1', str(path)], text=True).split()[0])

result = {
    'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
    'source_work_dir': str(source), 'imported_work_dir': str(imported),
    'runtime_id': (source / 'sdk/runtime-id').read_text().strip(),
    'runtime_directory_physical_bytes': size(runtime),
    'sdk_directory_physical_bytes': size(sdk),
    'runtime_qcow2_virtual_bytes': info['virtual-size'],
    'runtime_qcow2_file_bytes': info['actual-size'],
    'runtime_has_backing_file': False,
    'accepted_game_cycles': accepted,
    'additional_navigation_launches_not_counted': len(cycles) - 3,
    'sdl_demo': {'frames': int(demo[1]), 'elapsed_ms': int(demo[2])},
    'sdk_bundle_manifest_sha256': hashlib.sha256((sdk / 'bundle.json').read_bytes()).hexdigest(),
}
(evidence / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
tools = [('compiler', ['aarch64-linux-gnu-g++-12', '--version']),
         ('cmake', ['cmake', '--version']), ('ninja', ['ninja', '--version']),
         ('qemu', ['qemu-system-aarch64', '--version']), ('wsl_kernel', ['uname', '-a'])]
(evidence / 'host-tools.log').write_text('\n'.join(
    name + ': ' + sp.check_output(command, text=True).splitlines()[0] for name, command in tools) + '\n')
print(json.dumps(result, indent=2))
