# Fill a selection from a reference image

With part of a still RGB document selected, open **Edit → Generative Fill…** or the canvas action. Choose a still PNG, JPEG, TIFF, or HEIC reference, up to 16 MiB and 64 megapixels.

- **Reference to** controls what the model sees. **Object** uses the existing alpha channel of transparent artwork or isolates the largest locally detected foreground subject. **Whole Image** fits the complete scene into the model’s input.
- **Intent** controls what the result changes. **Swap** replaces the selected area. **Place** extracts the generated foreground into each alternative’s transparency so the surrounding background shows through.
- **Variations** generates one to three alternatives. Photato places them in one editable Smart Object with the original selection as a separate mask. Generation takes one Undo step. **Generate More** reuses the embedded reference. **Generate Similar** uses the chosen result as a new exemplar.

The model takes a visual exemplar. Remove the reference to go back to prompted or context-only fill. The embedded result retains a normalized 224-pixel copy of the reference and the prepared selection context. Sharing an editable Photato, PSD, or PSB document also shares those embedded samples.

## Optional local model

Paint by Example runs in Swift and Core ML on Apple Silicon with macOS 26 or later. It produces 512-pixel inpainting samples. Placement quality depends on successful foreground extraction. If the model cannot find a distinct subject for Place, the edit leaves the document untouched.

This optional model is distributed separately. To prepare it, download these files from the [pinned publisher revision](https://huggingface.co/Fantasy-Studio/Paint-by-Example/tree/351e6427d8c28a3b24f7c751d43eb4b6735127f7), preserving their paths in a directory named `publisher`.

| Path | Use |
| --- | --- |
| `image_encoder/config.json`, `image_encoder/pytorch_model.bin` | Reference encoder |
| `unet/config.json`, `unet/diffusion_pytorch_model.bin` | Denoiser |
| `vae/config.json`, `vae/diffusion_pytorch_model.bin` | Source and latent conversion |

Use the conversion script from `PhotoCraftSwift` with Python 3.11, coremltools 9.0, Torch 2.7.1, Diffusers 0.35.1, Transformers 4.49.0, and NumPy 1.26.4 installed. Use Xcode’s Core ML compiler for the four generated packages. The script verifies the source configs and weights before reading them.

```sh
mkdir -p PaintByExampleCoreML
for component in reference denoiser posterior decoder; do
  python scripts/convert-paint-by-example.py publisher packages "$component"
done
for model in ImageEncoder Unet VAEEncoder VAEDecoder; do
  xcrun coremlcompiler compile "packages/$model.mlpackage" PaintByExampleCoreML
done
```

Choose the compiled **PaintByExampleCoreML** directory in Generative Fill. The model card describes the CreativeML Open RAIL-M license. [Publisher and model license](https://huggingface.co/Fantasy-Studio/Paint-by-Example) · [Research paper](https://arxiv.org/abs/2211.13227)

## Automation

Enable document transfers and send `generativeFill.apply` with the current document revision. Use `scope` of `object` or `wholeImage` and `intent` of `swap` or `place`. Include the reference bytes as Base64. Seed and variation count are optional.

```json
{
  "referenceImage": {
    "scope": "object",
    "intent": "place",
    "dataBase64": "<base64 of a supported source image>"
  },
  "variationCount": 2
}
```

For a later batch, supply the active result as `targetLayerID`. Its embedded reference is reused, or supply `referenceVariationID` to use that alternative. Discover the configured model under `generativeFill.referenceFill` and a result’s saved options under `generativeFill.selectedVariations.referenceFill`. [Automation API](AUTOMATION_API.md)

Photoshop supports additional models and reference combinations. Exact Firefly results and the Photoshop API v2 Execute Actions descriptor for reference-guided filling remain unqualified. [Adobe’s reference workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/use-reference-images-for-consistent-results.html)
