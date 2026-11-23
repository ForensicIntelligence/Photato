#!/usr/bin/env python3
"""Convert the pinned CIDAS CLIPSeg model to Photato’s optional native model."""

import argparse
from hashlib import file_digest, sha1
import json
from pathlib import Path
import subprocess

import coremltools as ct
import numpy as np
import torch
from transformers import CLIPSegForImageSegmentation, CLIPSegProcessor

SIDE = 352
REVISION = '999e0328d9e10b484360c477313983f9afdd7050'
QUERIES = ('shadow on the ground', 'cast shadow', 'a reflection in water', 'a reflected object', 'reversed mirror image')
WEIGHT_DIGEST = 'd00ca85d6b859f9d07b7cfb8ef26fe9771cb275b34c9368f2ecf603139307f55'
PUBLISHER_FILES = (
    ('config.json', '9c1a3a8693f29070857102aea691cadcb7e8a806'),
    ('merges.txt', '76e821f1b6f0a9709293c3b6b51ed90980b3166b'),
    ('preprocessor_config.json', '30fe86be4cc83725316cbc68ed8c78f9d1483642'),
    ('special_tokens_map.json', '2c2130b544c0c5a72d5d00da071ba130a9800fb2'),
    ('tokenizer_config.json', '446c39016ef7112b9ace812c98641502da0193d1'),
    ('vocab.json', '469be27c5c010538f845f518c4f5e8574c78f7c8'),
)

class StaticMask(torch.nn.Module):
    def __init__(self, model, text):
        super().__init__()
        self.vision=model.clip.vision_model
        self.decoder=model.decoder
        self.layers=model.extract_layers
        self.register_buffer('text',text)

    def forward(self,x):
        hidden=self.vision(pixel_values=x,output_hidden_states=True,interpolate_pos_encoding=False,return_dict=True).hidden_states
        acts=tuple(torch.cat([hidden[i+1]]*len(QUERIES),dim=0) for i in self.layers)
        return self.decoder(acts,self.text,output_hidden_states=False,output_attentions=False,return_dict=False)[0]



def verify(root):
    for name, digest in PUBLISHER_FILES:
        content = (root / name).read_bytes()
        observed = sha1(f'blob {len(content)}\0'.encode() + content).hexdigest()
        if observed != digest:
            raise ValueError(f'{name} differs from publisher revision {REVISION}.')
    with (root / 'model.safetensors').open('rb') as stream:
        if file_digest(stream, 'sha256').hexdigest() != WEIGHT_DIGEST:
            raise ValueError(f'The weights differ from publisher revision {REVISION}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('publisher_directory', type=Path)
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    verify(args.publisher_directory)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    package = args.output_directory / 'RelatedElementsV1.mlpackage'
    compiled = args.output_directory / 'RelatedElementsV1.mlmodelc'
    if package.exists() or compiled.exists():
        raise FileExistsError('Use an output directory without an existing RelatedElementsV1 model.')
    torch.set_num_threads(6)
    model = CLIPSegForImageSegmentation.from_pretrained(args.publisher_directory,
        local_files_only=True, attn_implementation='eager').eval()
    processor = CLIPSegProcessor.from_pretrained(args.publisher_directory, local_files_only=True)
    with torch.no_grad():
        tokens = processor(text=list(QUERIES), return_tensors='pt', padding=True)
        text = model.get_conditional_embeddings(batch_size=len(QUERIES), **tokens)
        wrapper = StaticMask(model, text).eval()
        # Evaluate the publisher’s positional interpolation once for the fixed input size.
        embedding = wrapper.vision.embeddings
        tokens_per_image = (SIDE // embedding.patch_size) ** 2 + 1
        positions = embedding.interpolate_pos_encoding(torch.zeros(1, tokens_per_image, embedding.embed_dim), SIDE, SIDE)[0]
        embedding.position_embedding = torch.nn.Embedding.from_pretrained(positions)
        embedding.position_ids = torch.arange(tokens_per_image).reshape(1, -1)
        embedding.image_size = SIDE
        traced = torch.jit.trace(wrapper, torch.zeros(1, 3, SIDE, SIDE), strict=False, check_trace=False)
    program = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        inputs=[ct.TensorType(name='pixels', shape=(1, 3, SIDE, SIDE), dtype=np.float32)],
        outputs=[ct.TensorType(name='logits', dtype=np.float32)], skip_model_load=True)
    program.author = 'CIDAS'
    program.license = 'Apache-2.0 (publisher model card)'
    program.short_description = 'Fixed text prompts for Photato’s Related Elements review.'
    program.user_defined_metadata['revision'] = REVISION
    program.user_defined_metadata['queries'] = json.dumps(QUERIES, separators=(',', ':'))
    program.save(str(package))
    subprocess.run(['/usr/bin/xcrun', 'coremlcompiler', 'compile', package, args.output_directory], check=True)
    print(compiled)


if __name__ == '__main__':
    main()
