#!/usr/bin/env python3
"""Convert Google’s Apache-2.0 OWLv2 detector for Photato’s native Distractions review.

Use the publisher revision and verified local model files named in docs/REMOVE_GENERAL_DISTRACTIONS.md.
Python is only needed to prepare the optional model package.
"""

import argparse
from hashlib import file_digest, sha1
import json
from pathlib import Path
import subprocess

import coremltools as ct
import numpy as np
import torch
from transformers import Owlv2ForObjectDetection, Owlv2Processor


REVISION = 'cfd3195ba4ea9592eec887ded089f4c08eff231d'
WEIGHT_DIGEST = 'e1e130b9e404cf91a75ad45644c1da9d7fa5284085eecc864266a6923efb99e7'
PUBLISHER_BLOBS = {
    'config.json': 'dfc1049705d082052a81e7d18bde6d11fc137a0d',
    'merges.txt': '76e821f1b6f0a9709293c3b6b51ed90980b3166b',
    'preprocessor_config.json': 'b24bfd579e8682df31c7794a3e1c3ef6a9a22a7a',
    'special_tokens_map.json': '39808ac074d69141c0b2f065d16f56dfa5194cac',
    'tokenizer_config.json': '1c4c373d81adc0c63bb3368a89f4a92574395c2c',
    'vocab.json': '469be27c5c010538f845f518c4f5e8574c78f7c8',
}

QUERIES = (
    ('identifiedObjects', 'parked car'), ('identifiedObjects', 'bicycle'),
    ('identifiedObjects', 'truck'), ('identifiedObjects', 'motorcycle'),
    ('identifiedObjects', 'bench'), ('identifiedObjects', 'traffic sign'),
    ('identifiedObjects', 'street furniture'), ('identifiedObjects', 'backpack'),
    ('poles', 'street lamp post'), ('poles', 'utility pole'), ('poles', 'thin vertical metal bollard'),
    ('poles', 'sign pole'), ('vegetation', 'tree'), ('vegetation', 'bush'),
    ('vegetation', 'plant foliage'), ('visualClutter', 'trash bin'), ('visualClutter', 'rubbish'),
    ('visualClutter', 'plastic bottle'), ('visualClutter', 'traffic cone'),
    ('visualClutter', 'discarded bag'), ('visualClutter', 'cardboard box'),
    ('subject', 'person'), ('subject', 'dog'), ('subject', 'cat'),
)

class StaticVision(torch.nn.Module):
    def __init__(self, model, text):
        super().__init__()
        # Retain only the image transformer and detector heads in the traced graph.
        self.model = model
        self.register_buffer('text', text / (text.square().sum(dim=-1, keepdim=True).sqrt() + 1e-6))

    def forward(self, pixels):
        visual = self.model.owlv2.vision_model
        hidden = visual.post_layernorm(visual(pixel_values=pixels, return_dict=True).last_hidden_state)
        # The class token broadcasts across patch tokens through multiplication.
        # This equivalent expression avoids an explicit Torch broadcast_to op.
        flattened = self.model.layer_norm(hidden[:, 1:, :] * hidden[:, :1, :])
        class_head = self.model.class_head
        projected = class_head.dense0(flattened)
        normalized = projected / (projected.square().sum(dim=-1, keepdim=True).sqrt() + 1e-6)
        logits = torch.bmm(normalized, self.text.transpose(1, 2))
        logits = (logits + class_head.logit_shift(flattened)) * (class_head.elu(class_head.logit_scale(flattened)) + 1)
        boxes = (self.model.box_head(flattened) + self.model.box_bias).sigmoid()
        return boxes, logits, self.model.objectness_predictor(flattened)


def load(root):
    model = Owlv2ForObjectDetection.from_pretrained(root, local_files_only=True, attn_implementation='eager').eval()
    processor = Owlv2Processor.from_pretrained(root, local_files_only=True)
    return model, processor


@torch.inference_mode()
def query_embeddings(model, processor):
    inputs = processor.tokenizer([f'a photo of a {name}' for _, name in QUERIES],
                                 padding='max_length', truncation=True, return_tensors='pt')
    text = model.owlv2.get_text_features(**inputs)
    return torch.nn.functional.normalize(text, dim=-1).unsqueeze(0)



def verify(root):
    for name, expected in PUBLISHER_BLOBS.items():
        data = (root / name).read_bytes()
        observed = sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
        if observed != expected:
            raise ValueError(f'{name} differs from publisher revision {REVISION}')
    with (root / 'model.safetensors').open('rb') as stream:
        observed = file_digest(stream, 'sha256').hexdigest()
    if observed != WEIGHT_DIGEST:
        raise ValueError(f'model.safetensors differs from publisher revision {REVISION}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('publisher_directory', type=Path)
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    verify(args.publisher_directory)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    package = args.output_directory / 'DistractionDetectorV1.mlpackage'
    compiled = args.output_directory / 'DistractionDetectorV1.mlmodelc'
    if package.exists() or compiled.exists():
        raise FileExistsError('Use a directory without an existing DistractionDetectorV1 model.')
    torch.set_num_threads(6)
    model, processor = load(args.publisher_directory)
    example = torch.zeros(1, 3, 960, 960)
    with torch.no_grad():
        predictor = StaticVision(model, query_embeddings(model, processor)).eval()
        traced = torch.jit.trace(predictor, example, strict=False, check_trace=False)
    converted = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        inputs=[ct.TensorType(name='pixels', shape=(1, 3, 960, 960), dtype=np.float32)],
        outputs=[ct.TensorType(name=name, dtype=np.float32) for name in ('boxes', 'logits', 'objectness')],
        skip_model_load=True)
    converted.author = 'Google Research'
    converted.license = 'Apache-2.0'
    converted.short_description = 'Open-vocabulary object proposals for the Photato Distractions review.'
    converted.user_defined_metadata['source_revision'] = REVISION
    converted.user_defined_metadata['query_set'] = json.dumps(QUERIES, separators=(',', ':'))
    converted.save(str(package))
    subprocess.run(['/usr/bin/xcrun', 'coremlcompiler', 'compile', package, args.output_directory], check=True)
    print(compiled)


if __name__ == '__main__':
    main()
