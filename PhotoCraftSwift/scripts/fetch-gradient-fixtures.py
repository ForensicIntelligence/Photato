#!/usr/bin/env python3
"""Verify or fetch pinned, unmodified psd-tools gradient interoperability fixtures."""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'artifacts/psd-gradient-fixture-manifest.json').read_text())
base = f"https://raw.githubusercontent.com/{manifest['repository']}/{manifest['commit']}/"
for item in manifest['files']:
    destination = root / item['fixture_path']
    content = destination.read_bytes() if destination.exists() else b''
    if hashlib.sha256(content).hexdigest() != item['sha256']:
        with urlopen(base + item['path'], timeout=30) as response:
            content = response.read(4 * 1024 * 1024)
    assert len(content) == item['bytes']
    assert hashlib.sha256(content).hexdigest() == item['sha256']
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(content)
    print('Verified', item['path'])
