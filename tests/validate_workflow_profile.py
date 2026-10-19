"""Integration check: redeploy preserves data; explicit reset retains a backup."""
import os
from pathlib import Path
import subprocess

work = Path(os.environ['WORK_DIR'])
logs = work / 'logs/workflow'

def guest(code):
    result = subprocess.run(['bash', 'vm.sh', 'ssh', 'sudo -n python3 -'], input=code,
                            text=True, capture_output=True, check=True)
    assert result.stdout.strip(), 'Guest Python did not receive stdin'
    print(result.stdout, end='')

guest('''
from pathlib import Path
import xml.etree.ElementTree as E
p=Path('/opt/darkos-es/home/.emulationstation/es_settings.cfg')
t=E.parse(p)
item=t.getroot().find("bool[@name='FavoritesFirst']")
if item is None: item=E.SubElement(t.getroot(),'bool',name='FavoritesFirst')
item.set('value','true'); t.write(p,encoding='utf-8',xml_declaration=True)
Path('/opt/darkos-emulators/peanut-gb/roms/Preservation test.gb').write_bytes(b'test-marker-not-a-ROM')
Path('/opt/darkos-emulators/peanut-gb/saves/preservation-test.sav').write_bytes(b'test-save-marker')
print('Test preference, ROM marker and save marker written')
''')
with (logs / 'redeploy-all.log').open('w') as f:
    subprocess.run(['bash', 'build.sh', 'deploy', 'all'], stdout=f, stderr=subprocess.STDOUT, check=True)
guest('''
from pathlib import Path
import xml.etree.ElementTree as E
t=E.parse('/opt/darkos-es/home/.emulationstation/es_settings.cfg')
assert t.getroot().find("bool[@name='FavoritesFirst']").get('value')=='true'
assert Path('/opt/darkos-emulators/peanut-gb/roms/Preservation test.gb').read_bytes()==b'test-marker-not-a-ROM'
assert Path('/opt/darkos-emulators/peanut-gb/saves/preservation-test.sav').read_bytes()==b'test-save-marker'
print('Redeploy preserved preference, ROM and save markers')
''')
with (logs / 'reset-profile.log').open('w') as f:
    subprocess.run(['bash', 'build.sh', 'deploy', 'es', '--reset-profile'], stdout=f, stderr=subprocess.STDOUT, check=True)
guest('''
from pathlib import Path
import xml.etree.ElementTree as E
p=Path('/opt/darkos-es/home/.emulationstation')
t=E.parse(p/'es_settings.cfg')
assert t.getroot().find("bool[@name='FavoritesFirst']").get('value')=='false'
assert any(E.parse(b/'es_settings.cfg').getroot().find("bool[@name='FavoritesFirst']").get('value')=='true' for b in p.parent.glob('.emulationstation.backup.*'))
assert E.parse(p/'es_systems.cfg').getroot().find("system[name='gb']") is not None
assert Path('/opt/darkos-emulators/peanut-gb/saves/preservation-test.sav').exists()
print('Explicit reset restored defaults, retained Game Boy, kept backup and saves')
''')
