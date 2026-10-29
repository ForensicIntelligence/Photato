#!/usr/bin/env python3
"""Reproduce the optional native Core ML resource; no Python runtime ships in Photato."""
from pathlib import Path
import hashlib, json, os, shutil, subprocess, sys, tempfile, urllib.request

root=Path(__file__).resolve().parent.parent
cache=root/'.build/people-model-source';cache.mkdir(parents=True,exist_ok=True)
tools=root/'scripts/people-model';generated=root/'Assets/GeneratedModels';generated.mkdir(parents=True,exist_ok=True)
source_url='https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite'
source_hash='c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def run(args):subprocess.run([str(x) for x in args],check=True,cwd=root)
source=cache/'selfie_multiclass_256x256.tflite'
if not source.exists():
    with urllib.request.urlopen(source_url,timeout=60) as response:data=response.read(16_371_838)
    if len(data)!=16_371_837 or hashlib.sha256(data).hexdigest()!=source_hash:raise SystemExit('Unexpected model artifact; download rejected.')
    source.write_bytes(data)
if sha(source)!=source_hash:raise SystemExit('Cached model checksum failed; preserve and inspect the cache before retrying.')
venv=root/'.build/people-model-tools'
python=venv/'bin/python'
if not python.exists():
    interpreter=shutil.which('python3.11') or shutil.which('python3.12')
    if not interpreter:raise SystemExit('Install Python3.11 or3.12 for optional build-time model conversion.')
    run([interpreter,'-m','venv',venv])
run([python,'-m','pip','install','-r',tools/'requirements.txt'])
package=cache/'PeopleParts.mlpackage'
if package.exists():
    backup=Path(tempfile.mkdtemp(prefix='people-model-prior-',dir=root/'.build'))
    shutil.move(str(package),backup/package.name)
run([python,tools/'convert.py',cache]);run([python,tools/'validate.py',cache])
stage=Path(tempfile.mkdtemp(prefix='people-model-compiled-',dir=root/'.build'))
run(['xcrun','coremlcompiler','compile',package,stage])
compiled=stage/'PeopleParts.mlmodelc'
files={str(p.relative_to(compiled)):sha(p) for p in sorted(compiled.rglob('*')) if p.is_file()}
if not files:raise SystemExit('Core ML compilation produced no resource.')
manifest={'format':1,'model':'people-parts-v1','sourceURL':source_url,'sourceSHA256':source_hash,
          'modelCard':'https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf',
          'license':'Apache-2.0','author':'Google / MediaPipe; model card author Adel Ahmadyan',
          'conversionSHA256':sha(tools/'convert.py'),'validation':json.loads((cache/'validation.json').read_text()),
          'classes':['background','hair','bodySkin','faceSkin','clothes','accessories'],'files':files}
destination=generated/'PeopleParts.mlmodelc'
if destination.exists():
    backup=Path(tempfile.mkdtemp(prefix='people-model-prior-',dir=root/'.build'))
    shutil.move(str(destination),backup/destination.name)
shutil.move(str(compiled),destination)
temporary=generated/'PeopleParts.provenance.json.tmp';temporary.write_text(json.dumps(manifest,indent=2)+'\n')
os.replace(temporary,generated/'PeopleParts.provenance.json')
print('Verified native person feature model:',destination)
