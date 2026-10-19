"""Fetch the author's free original DMG ROM; retain archive and provenance."""
import hashlib
import html
import http.cookiejar
import io
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request
import zipfile

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
page = 'https://tangramgames.itch.io/tobutobugirl'
upload = '678889'
expected_archive = 'c5ec138071079b9cad227d6fb875ad4e58a77f173ed3cd8758c04c0ab166d6e7'
expected_rom = '5d3871cae77db2287807e8914fd21f76203e73aa3fec20955489d45cb4571d8f'
archive = root / 'tobutobugirl.zip'
rom = root / 'Tobu Tobu Girl.gb'
manifest = root / 'rom-manifest.json'
if manifest.exists() and archive.exists() and rom.exists():
    saved = json.loads(manifest.read_text())
    for path, key, expected in [(archive, 'archive_sha256', expected_archive), (rom, 'rom_sha256', expected_rom)]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != saved[key] or saved[key] != expected:
            raise SystemExit(f'Checksum mismatch: {path}')
    print('Existing archive and ROM checksums verified')
    sys.exit(0)

opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
opener.addheaders = [('User-Agent', 'darkos-qemu-development')]

def get(url):
    return opener.open(url, timeout=60).read()

def token(document):
    return html.unescape(re.search(r'name="csrf_token" value="([^"]+)"', document)[1])

def post(url, values):
    return json.loads(opener.open(url, urllib.parse.urlencode(values).encode(), timeout=60).read())

document = get(page).decode()
download = post(page + '/download_url', {'csrf_token': token(document)})['url']
document = get(download).decode()
if f'data-upload_id="{upload}"' not in document:
    raise SystemExit('Pinned original Game Boy download is no longer listed')
url = post(page + '/file/' + upload, {'csrf_token': token(document)})['url']
payload = get(url)
if hashlib.sha256(payload).hexdigest() != expected_archive:
    raise SystemExit('Official archive changed; inspect before changing the pinned checksum')
with zipfile.ZipFile(io.BytesIO(payload)) as package:
    members = [n for n in package.namelist() if n.lower().endswith('.gb') and not n.startswith('__MACOSX/')]
    if len(members) != 1:
        raise SystemExit(f'Expected exactly one original DMG ROM, got {members}')
    game = package.read(members[0])
    if len(game) < 0x150 or game[0x143] == 0xC0:
        raise SystemExit('Not a DMG-compatible cartridge')
    if hashlib.sha256(game).hexdigest() != expected_rom:
        raise SystemExit('Unexpected ROM checksum')
archive.write_bytes(payload)
rom.write_bytes(game)
metadata = {
    'source': page, 'upload_id': upload, 'archive_member': members[0],
    'archive_sha256': hashlib.sha256(payload).hexdigest(),
    'rom_sha256': hashlib.sha256(game).hexdigest(),
    'rom_bytes': len(game), 'source_code_license': 'MIT',
    'assets_license': 'CC BY 4.0', 'author': 'Tangram Games; music by potato-tan',
    'license_source': 'https://github.com/SimonLarsen/tobutobugirl/blob/master/README.md',
}
manifest.write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata, indent=2))
