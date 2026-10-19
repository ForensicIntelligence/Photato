#!/usr/bin/env python3
"""Reproduce the pinned, unmodified MIT-licensed adjustment test references."""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

root = Path(__file__).resolve().parent.parent
for name in ['psd-adjustment-fixture-manifest.json', 'psd-tonal-step-fixture-manifest.json']:
    manifest = json.loads((root / 'artifacts' / name).read_text())
    base = f"https://raw.githubusercontent.com/{manifest['repository']}/{manifest['commit']}/"
    for item in manifest['files']:
        local = root / item['local_path']
        content = local.read_bytes() if local.exists() else b''
        if hashlib.sha256(content).hexdigest() != item['sha256']:
            with urlopen(base + item['path'], timeout=30) as response:
                content = response.read(4 * 1024 * 1024)
        assert len(content) == item['bytes']
        assert hashlib.sha256(content).hexdigest() == item['sha256']
        for destination in [local, root / item['fixture_path']]:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        print('Verified', item['path'])
