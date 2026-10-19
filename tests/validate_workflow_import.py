"""Check a running imported ES image; optionally clean source test markers."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

work = Path(os.environ['WORK_DIR'])

def guest(code):
    result = subprocess.run(['bash', 'vm.sh', 'ssh', 'sudo -n python3 -'], input=code,
                            text=True, capture_output=True, check=True)
    assert result.stdout.strip(), 'Guest Python did not receive stdin'
    return json.loads(result.stdout)

if len(sys.argv) > 1 and sys.argv[1] == 'cleanup':
    guest('''
import json
from pathlib import Path
Path('/opt/darkos-emulators/peanut-gb/roms/Preservation test.gb').unlink(missing_ok=True)
Path('/opt/darkos-emulators/peanut-gb/saves/preservation-test.sav').unlink(missing_ok=True)
print(json.dumps({'cleaned':True}))
''')
    print('Source test markers removed; real game saves retained')
    raise SystemExit(0)

source = Path(sys.argv[1])
data = guest('''
import json
from pathlib import Path
import xml.etree.ElementTree as E
p=Path('/opt/darkos-es/home/.emulationstation')
t=E.parse(p/'es_settings.cfg').getroot()
assert t.find("string[@name='ThemeSet']").get('value')=='es-theme-nes-box'
assert t.find("bool[@name='HideWindow']").get('value')=='true'
assert E.parse(p/'es_systems.cfg').getroot().find("system[name='gb']/theme").text=='gb'
assert not list(p.parent.glob('.emulationstation.backup.*'))
root=Path('/opt/darkos-emulators/peanut-gb')
assert sorted(q.name for q in (root/'roms').glob('*.gb'))==['Tobu Tobu Girl.gb']
assert not list((root/'saves').iterdir())
assert Path('/etc/machine-id').read_text().strip()
print(json.dumps({'authorized':Path('/home/ark/.ssh/authorized_keys').read_text().strip(),
 'host_key':Path('/etc/ssh/ssh_host_ed25519_key.pub').read_text().split()[1],
 'runtime_id':Path('/opt/darkos-graphics/runtime-id').read_text().strip()}))
''')
new_key = (work / 'ssh/id_ed25519.pub').read_text().strip()
assert data['authorized'] == new_key
assert new_key != (source / 'ssh/id_ed25519.pub').read_text().strip()
old_hosts = {line.split()[2] for line in (source / 'ssh/graphics_known_hosts').read_text().splitlines() if line.strip()}
assert data['host_key'] not in old_hosts
assert data['runtime_id'] == (work / 'sdk/runtime-id').read_text().strip()
print('Imported UI/theme, clean ROM/save/profile directories and runtime ID verified')
print('Fresh user SSH key SHA256: ' + hashlib.sha256(new_key.encode()).hexdigest())
print('Only the new user key is authorized; SSH server host key differs from source')
result = subprocess.run(['bash', 'vm.sh', 'ssh', 'sudo -n bash /opt/darkos-es/scripts/es-audit.sh'],
                        text=True, capture_output=True, check=True)
print(result.stdout, end='')
