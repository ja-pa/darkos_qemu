"""Guest-only profile: dArkOS presentation, verified QEMU applications."""
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

base = Path('/opt/darkos-es/home/.emulationstation')
marker = base / '.qemu-profile-v1'
base.mkdir(parents=True, exist_ok=True)
if not marker.exists():
    original = Path('/home/ark/.emulationstation/es_settings.cfg')
    # dArkOS uses sibling XML elements rather than a single document root.
    text = original.read_text().replace('<?xml version="1.0"?>', '')
    defaults = ET.fromstring('<config>' + text + '</config>')
    source_theme = next((p for p in [Path('/etc/emulationstation/themes/es-theme-nes-box'),
                                    Path('/roms/themes/es-theme-nes-box'), Path('/tempthemes/es-theme-nes-box'),
                                    Path('/home/ark/.emulationstation/themes/es-theme-nes-box')]
                         if p.is_dir()), None)
    if source_theme is None:
        raise SystemExit('Original es-theme-nes-box theme not found; inspect dArkOS theme layout')
    target = base / 'themes/es-theme-nes-box'
    shutil.copytree(source_theme, target, symlinks=False, dirs_exist_ok=True)
    settings = ET.parse(base / 'es_settings.cfg')
    allowed = {'DrawClock', 'FavoritesFirst', 'QuickSystemSelect', 'MaxVRAM',
               'FolderViewMode', 'SaveGamelistsMode', 'ScreenSaverBehavior',
               'ThemeRegionName', 'TransitionStyle'}
    for item in defaults:
        if item.get('name') in allowed or item.get('name', '').startswith('subset.'):
            old = settings.getroot().find(f"{item.tag}[@name='{item.get('name')}']")
            if old is not None:
                settings.getroot().remove(old)
            settings.getroot().append(item)
    overrides = [('string', 'ThemeSet', 'es-theme-nes-box'), ('string', 'GamelistViewStyle', 'automatic'),
                 ('bool', 'HideWindow', 'true'), ('bool', 'EnableSounds', 'false'),
                 ('bool', 'VideoAudio', 'false'), ('bool', 'BackgroundMusic', 'false')]
    for tag, name, value in overrides:
        item = settings.getroot().find(f"{tag}[@name='{name}']")
        if item is None:
            item = ET.SubElement(settings.getroot(), tag, name=name)
        item.set('value', value)
    settings.write(base / 'es_settings.cfg', encoding='utf-8', xml_declaration=True)
    roms = base.parent / 'roms'
    roms.mkdir(exist_ok=True)
    for name in ['First graphics test.demo', 'Second graphics test.demo']:
        (roms / name).unlink(missing_ok=True)
    (roms / 'SDL OpenGL triangle.demo').touch()
    marker.touch()

systems = ET.parse(base / 'es_systems.cfg')
for system in systems.getroot():
    if system.findtext('name') == 'gb':
        system.find('theme').text = 'gb'
    elif system.findtext('name') == 'qemu-test':
        system.find('theme').text = 'ports'
        system.find('fullname').text = 'QEMU test applications'
        system.find('command').text = '/bin/bash /opt/darkos-apps/sdl-demo/es-env.sh /opt/darkos-apps/sdl-demo/sdl-demo'
systems.write(base / 'es_systems.cfg', encoding='utf-8', xml_declaration=True)
print('dArkOS QEMU profile ready; existing user settings preserved')
