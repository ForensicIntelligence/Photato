#!/usr/bin/env python3
"""Acquire pinned BSD-3 model data and compile it with Apple's Xcode tool.

Development/build-time only. The shipped Swift app never runs Python or downloads
a model. Existing generated model resources are verified and never overwritten.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
URL = 'https://github.com/hanxiao/real-esrgan-coreml/releases/download/v1.0.0/RealESRGAN_general_522_fp16.zip'
SHA = '41368af9dcbcc300c0fe0442202acbf98d30dc07c28d49bf656883f7fef3656a'

def main():
    root = ROOT / 'Assets/GeneratedModels'
    root.mkdir(parents=True, exist_ok=True)
    verifier = importlib.util.spec_from_file_location('verify_upscale', ROOT / 'scripts/verify-upscale-model.py')
    module = importlib.util.module_from_spec(verifier); verifier.loader.exec_module(module)
    target = root / 'LocalUpscale.mlmodelc'
    if target.exists() or (root / 'LocalUpscale.provenance.json').exists():
        module.verify(root)
        print('Existing optional local model verified.'); return
    with tempfile.TemporaryDirectory(prefix='photato-upscale-model-') as folder:
        work = Path(folder)
        with urllib.request.urlopen(URL, timeout=60) as response:
            data = response.read(2286476)
        assert len(data) == 2286475 and hashlib.sha256(data).hexdigest() == SHA, 'Model download changed'
        archive = work / 'model.zip'; archive.write_bytes(data)
        with zipfile.ZipFile(archive) as z:
            assert len(z.infolist()) <= 16 and sum(x.file_size for x in z.infolist()) <= 8*1024*1024
            for item in z.infolist():
                relative = Path(item.filename)
                assert not relative.is_absolute() and '..' not in relative.parts
                assert ((item.external_attr >> 16) & 0o170000) != 0o120000
                if not item.is_dir():
                    dest = work / relative
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.open('xb').write(z.read(item))
        compiled = work / 'compiled'; compiled.mkdir()
        subprocess.run(['xcrun','coremlcompiler','compile',str(work/'RealESRGAN_general_522_fp16.mlpackage'),str(compiled)],check=True)
        model = compiled / 'RealESRGAN_general_522_fp16.mlmodelc'
        files = {str(p.relative_to(model)): module.digest(p) for p in model.rglob('*') if p.is_file()}
        assert set(files) == module.FILES
        record = {'schema':1,'identifier':module.IDENTIFIER,'archive_sha256':SHA,'archive_url':URL,
                  'conversion_commit':'15ab3bf80a577cecb93bb2b7ed48711ba7d894d5',
                  'weights_project':'https://github.com/xinntao/Real-ESRGAN','license':'BSD-3-Clause',
                  'license_sha256':module.digest(ROOT/'LICENSE-RealESRGAN'),
                  'model_minimum_macOS':'15.0','Photato_runtime_policy':'macOS26+ARM','compiled_sha256':files}
        # Each generated name is new. Ordinary source builds may omit the model.
        shutil.copytree(model, target)
        (root / 'LocalUpscale.provenance.json').open('x').write(json.dumps(record,indent=2)+'\n')
        module.verify(root)
    print('Optional local super-resolution model prepared.')

if __name__ == '__main__':
    main()
