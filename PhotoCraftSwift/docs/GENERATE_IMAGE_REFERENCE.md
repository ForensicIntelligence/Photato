# Reference images in Generate Image

Open **Edit → Generate Image…** and enter the subject or scene. In **Reference image**, choose a still PNG, JPEG, TIFF, or HEIC up to 16 MiB and 64 megapixels. Choose **Style** for the reference’s colours and textures or **Composition** for its layout. Choose the corresponding model if this is your first use. Click **Generate** to put one to three editable alternatives on a new layer.

**Style** generates the described subject with Stable Diffusion, then applies arbitrary neural style transfer from the reference. The AesFA conversion works at 224 × 224 internally and Photato resamples its output to the model’s 512 × 512 image. Fine detail can soften and strong textures can dominate. **Composition** derives edges from the imported image and passes them to ControlNet during diffusion. It centres and crops the reference to fit the visible canvas. Edges guide the arrangement and scale of shapes, while the prompt supplies the subject and appearance. Complex or ambiguous references can introduce additional objects.

The generated Smart Object embeds the bounded, normalized reference pixels and how they were used. **Generate More** and **Generate Similar** reuse that reference after reopening a Photato, PSD, or PSB document. The original imported file stays where it was. Share the editable document only if you also intend to share the embedded reference.

## Model setup

The workflow runs locally on Apple Silicon with macOS 26 or later. It uses the [existing prompt model](LOCAL_GENERATIVE_FILL.md) plus the reference model for the selected mode. Photato does not bundle these optional downloads.

- **Composition.** Download and extract the [ORIGINAL Core ML ControlNet Canny archive](https://huggingface.co/Guernika/CoreMLStableDiffusion/resolve/9252390067013229c60c491bae7b66a6249752b9/ControlNet/ORIGINAL/ControlNet_Canny.zip). The ZIP is 666,468,874 bytes with SHA-256 `fa511fa9a75acb4fc98819d01fa798e39035761fa36168b3fee1b12400ce02aa`. Choose the extracted `ControlNet_Canny.mlmodelc` package. [Guernika catalogue](https://huggingface.co/Guernika/CoreMLStableDiffusion) · [Original Canny model](https://huggingface.co/lllyasviel/sd-controlnet-canny)
- **Style.** Copy the pinned [AesFA.mlpackage directory](https://github.com/g-nitin/ArtEdge/tree/d0b135e579c6475135b06b5ec937c74b716dae71/ArtEdge/models/AesFA.mlpackage) from ArtEdge. Preserve its directory layout and compile it once with `xcrun coremlcompiler compile "/path/to/AesFA.mlpackage" "/path/to/output-folder"`. Choose the resulting `AesFA.mlmodelc` package. The archived weights file has SHA-256 `9cf0164a8e426813db3bfd42438519a9512b7cb91ffce546255cd78490405bc5`. [ArtEdge license](https://github.com/g-nitin/ArtEdge/blob/d0b135e579c6475135b06b5ec937c74b716dae71/LICENSE) · [AesFA research](https://aesfa-nst.github.io/AesFA/)

## Automation

Use the existing authenticated `generativeImage.apply` command. Enable document transfers before sending a new reference. Add this parameter alongside the prompt and optional seed and variation count.

```json
{
  "referenceImage": {
    "use": "composition",
    "dataBase64": "<base64 of a supported source image>"
  }
}
```

Use `style` for the other mode. Configure each optional model in the desktop sheet. The document state lists configured models under `generativeFill.localImage.referenceModels` and the saved use under `generativeFill.selectedVariations.referenceUse`. When appending to a saved layer, supply its `targetLayerID` and omit `referenceImage` to reuse the embedded reference. [Automation API](AUTOMATION_API.md)

Photoshop documents the Style and Composition workflow. Adobe Firefly’s hosted Image API uses its own `style` and `structure` inputs. Exact Firefly output and the Photoshop API v2 GA Execute Actions descriptor for this workflow remain unqualified. [Adobe desktop workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/generate-images-using-reference-image.html) · [Firefly structure reference](https://developer.adobe.com/firefly-services/docs/firefly-api/guides/concepts/structure-image-reference/)
