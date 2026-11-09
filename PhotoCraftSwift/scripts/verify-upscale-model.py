#!/usr/bin/env python3
"""Verify optional locally generated Real-ESRGAN resources before bundling."""
import hashlib
import json
from pathlib import Path
import sys

ARCHIVE_SHA256 = '41368af9dcbcc300c0fe0442202acbf98d30dc07c28d49bf656883f7fef3656a'
IDENTIFIER = 'realesr-general-x4v3-coreml-fp16'
FILES = {'metadata.json', 'model.mil', 'coremldata.bin', 'weights/weight.bin', 'analytics/coremldata.bin'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(root):
    model = root / 'LocalUpscale.mlmodelc'
    assert model.is_dir() and not model.is_symlink(), 'Missing local upscale model'
    record = json.loads((root / 'LocalUpscale.provenance.json').read_text())
    assert record['identifier'] == IDENTIFIER and record['archive_sha256'] == ARCHIVE_SHA256
    assert set(record['compiled_sha256']) == FILES
    actual = {str(p.relative_to(model)): digest(p) for p in model.rglob('*') if p.is_file()}
    assert actual == record['compiled_sha256'], 'Local model differs from its provenance'
    assert not any(p.is_symlink() for p in model.rglob('*')), 'Model symlinks are unsupported'
    assert all((model / p).stat().st_size <= 16 * 1024 * 1024 for p in FILES)
    return record

if __name__ == '__main__':
    result = verify(Path(sys.argv[1]))
    print(json.dumps({'verified': True, 'identifier': result['identifier'], 'files': len(FILES)}))
