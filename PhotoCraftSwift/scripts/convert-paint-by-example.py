"""Convert checksum-verified Paint by Example components to Photato's Core ML input contract."""
import argparse
from hashlib import file_digest
from pathlib import Path

import coremltools as ct
from diffusers import AutoencoderKL, UNet2DConditionModel
from diffusers.pipelines.paint_by_example.image_encoder import PaintByExampleImageEncoder
import numpy as np
import torch

IDENTIFIER = "Fantasy-Studio/Paint-by-Example"
REVISION = "351e6427d8c28a3b24f7c751d43eb4b6735127f7"
WEIGHTS = {
    "image_encoder/pytorch_model.bin": "296d26d0c844328727c58870e169183c0d23a6d82ecd3467a8484610f3be6146",
    "unet/diffusion_pytorch_model.bin": "2020aa8102bd6ea977738454f87d8e08483271469bfa1ebd1b62534f0cf7d371",
    "vae/diffusion_pytorch_model.bin": "1b134cded8eb78b184aefb8805b6b572f36fa77b255c483665dda931fa0130c5",
}

CONFIGS = {
    "vae/config.json": "00a83c5fd47f4a99d6228314f36dd07ff4b6f1122a2d8cc9428297731d3f840a",
    "image_encoder/config.json": "bfe476ec35a718c7c9081ac3e17dda62ef7630d618ab7b5bfbc836ea0d71806d",
    "unet/config.json": "54296409313f49c3dd010b1f646f4e060ac546945529e2b9eaec5c5a6b2eb223",
}


def verify(source, name):
    for path, expected in {**WEIGHTS, **CONFIGS}.items():
        if path.startswith(name + "/"):
            with (source / path).open("rb") as raw:
                if file_digest(raw, "sha256").hexdigest() != expected:
                    raise ValueError(f"Publisher checksum mismatch: {path}")


class ReferenceEncoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, pixels):
        features, unconditional = self.model(pixels, return_uncond_vector=True)
        return torch.cat((unconditional, features), dim=0).transpose(1, 2).unsqueeze(2)


class Denoiser(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, sample, timestep, encoder_hidden_states):
        states = encoder_hidden_states.squeeze(2).transpose(1, 2)
        return self.model(sample, timestep, states, return_dict=False)[0]


class Posterior(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.quant_conv = model.quant_conv

    def forward(self, pixels):
        return self.quant_conv(self.encoder(pixels))


class LatentDecoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.decoder = model.decoder
        self.post_quant_conv = model.post_quant_conv

    def forward(self, latents):
        return self.decoder(self.post_quant_conv(latents))


def export(model, name, features, output, shape, destination):
    target = destination / (name + ".mlpackage")
    if target.exists():
        raise FileExistsError(target)
    model.eval()
    with torch.no_grad():
        example = tuple(torch.zeros(dimensions) for _, dimensions in features)
        traced = torch.jit.trace(model, example, check_trace=False, strict=True)
    converted = ct.convert(
        traced, convert_to="mlprogram", minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16, skip_model_load=True,
        inputs=[ct.TensorType(name=name, shape=dimensions, dtype=np.float32) for name, dimensions in features],
        outputs=[ct.TensorType(name=output, dtype=np.float32)],
    )
    converted.author = IDENTIFIER
    converted.version = REVISION
    converted.license = "CreativeML Open RAIL-M"
    converted.user_defined_metadata["reference_contract"] = "photato-paint-by-example-1"
    converted.user_defined_metadata["attention_implementation"] = "ORIGINAL"
    described = converted.get_spec().description.output[0].type.multiArrayType.shape
    if list(described) != list(shape):
        raise ValueError(f"{name} output shape {list(described)} != {shape}")
    converted.save(str(target))
    print(target, flush=True)


def convert(source, destination, name):
    if name in ("posterior", "decoder"):
        verify(source, "vae")
        vae = AutoencoderKL.from_pretrained(source / "vae", local_files_only=True, use_safetensors=False)
        if name == "posterior":
            export(Posterior(vae), "VAEEncoder", [("z", (1, 3, 512, 512))], "moments", (1, 8, 64, 64), destination)
        else:
            export(LatentDecoder(vae), "VAEDecoder", [("z", (1, 4, 64, 64))], "image", (1, 3, 512, 512), destination)
    elif name == "reference":
        verify(source, "image_encoder")
        from transformers import CLIPVisionConfig
        config = CLIPVisionConfig.from_pretrained(source / "image_encoder", local_files_only=True)
        model = PaintByExampleImageEncoder(config)
        weights = torch.load(source / "image_encoder/pytorch_model.bin", map_location="cpu", weights_only=True, mmap=True)
        # Transformers now creates these deterministic IDs as a non-persistent buffer.
        ids = weights.pop("model.vision_model.embeddings.position_ids")
        expected = torch.arange((config.image_size // config.patch_size) ** 2 + 1).unsqueeze(0)
        if not torch.equal(ids, expected):
            raise ValueError("Unexpected CLIP position IDs.")
        model.load_state_dict(weights, strict=True, assign=True)
        export(ReferenceEncoder(model), "ImageEncoder", [("reference", (1, 3, 224, 224))],
               "embeddings", (2, 768, 1, 1), destination)
    else:
        verify(source, "unet")
        model = UNet2DConditionModel.from_pretrained(source / "unet", local_files_only=True, use_safetensors=False)
        export(Denoiser(model), "Unet", [("sample", (2, 9, 64, 64)), ("timestep", (2,)),
                                       ("encoder_hidden_states", (2, 768, 1, 1))],
               "noise_pred", (2, 4, 64, 64), destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("component", choices=["posterior", "decoder", "reference", "denoiser"])
    args = parser.parse_args()
    torch.set_num_threads(4)
    args.destination.mkdir(parents=True, exist_ok=True)
    convert(args.source, args.destination, args.component)
