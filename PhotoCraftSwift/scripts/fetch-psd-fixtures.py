#!/usr/bin/env python3
"""Fetch the seven pinned, MIT-licensed PSD references; verify every fixture digest."""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'artifacts/psd-fixture-manifest.json').read_text())
base = f"https://raw.githubusercontent.com/{manifest['repository']}/{manifest['commit']}/"
destination = root / 'corpus/psd-tools'
destination.mkdir(parents=True, exist_ok=True)
for item in manifest['files']:
    path = destination / item['path']
    content = path.read_bytes() if path.exists() else b''
    if hashlib.sha256(content).hexdigest() != item['sha256']:
        with urlopen(base + 'tests/psd_files/' + item['path'], timeout=30) as response:
            content = response.read(16 * 1024 * 1024)
        assert len(content) == item['bytes'] and hashlib.sha256(content).hexdigest() == item['sha256'], item['path']
        path.write_bytes(content)
    print('Verified', item['path'])
license_path = destination / 'LICENSE'
if not license_path.exists():
    with urlopen(base + 'LICENSE', timeout=30) as response:
        license_path.write_bytes(response.read(64 * 1024))
