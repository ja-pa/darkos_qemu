"""Guest-only integration into the existing isolated ES profile."""
from pathlib import Path
import xml.etree.ElementTree as ET

profile = Path('/opt/darkos-es/home/.emulationstation')
path = profile / 'es_systems.cfg'
tree = ET.parse(path)
systems = tree.getroot()
had_gameboy = any(system.findtext('name') == 'gb' for system in systems)
for system in list(systems):
    if system.findtext('name') == 'gb':
        systems.remove(system)
gameboy = ET.Element('system')
for name, value in {
    'name': 'gb', 'fullname': 'Game Boy / Peanut-GB',
    'path': '/opt/darkos-emulators/peanut-gb/roms', 'extension': '.gb',
    'command': '/bin/bash /opt/darkos-emulators/peanut-gb/scripts/gb-run.sh %ROM%',
    'platform': 'gb', 'theme': 'qemu-test',
}.items():
    ET.SubElement(gameboy, name).text = value
systems.insert(0, gameboy)
tree.write(path, encoding='utf-8', xml_declaration=True)
path = profile / 'es_settings.cfg'
tree = ET.parse(path)
for tag, name, value in [('bool', 'HideWindow', 'true'), ('string', 'StartupSystem', 'gb')]:
    item = tree.getroot().find(f"{tag}[@name='{name}']")
    if name == 'StartupSystem' and item is not None and had_gameboy:
        continue
    if item is None:
        item = ET.SubElement(tree.getroot(), tag, name=name)
    item.set('value', value)
tree.write(path, encoding='utf-8', xml_declaration=True)
