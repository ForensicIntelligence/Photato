# Local Generative Fill

Select part of a still RGB image and choose **Edit > Generative Fill…**. Describe what to add or leave the prompt blank to fill from surrounding pixels. Photato places the result on a new layer above the visible stack, preserves feathering in an editable layer mask and gives the edit one Undo step.

Inference runs on Apple Silicon with macOS 26 or later. The models are optional downloads.

## Set up the prompt model

1. Review the model terms. Download the **ORIGINAL** Core ML conversion of Runway Stable Diffusion 1.5 Inpaint. The pinned ZIP is about 2 GB and is distributed separately under CreativeML OpenRAIL-M. [Model and terms](https://huggingface.co/Guernika/CoreMLStableDiffusion/tree/9252390067013229c60c491bae7b66a6249752b9) · [Pinned ZIP](https://huggingface.co/Guernika/CoreMLStableDiffusion/resolve/9252390067013229c60c491bae7b66a6249752b9/Models/ORIGINAL/Runway_SD1.5_Inpaint.zip)
2. Check the download with `shasum -a 256 Runway_SD1.5_Inpaint.zip`. The checksum should be `836af8415b0e92b7825532f61577cbddab106cb8950f0e8e47d2a5bf4d8fec00`.
3. Unzip it. Enter a nonempty prompt in Photato’s Generative Fill sheet, choose the extracted `Runway_SD1.5_Inpaint` folder, and select **Generate**.

## Set up the blank-prompt model

Run `python3 scripts/prepare-inpainting-model.py /path/to/new-model-folder` from the native project directory with Xcode installed. The script downloads the pinned model files and checks their hashes before compiling the Core ML package. Leave the prompt blank and choose the resulting `LaMa512.mlmodelc` package in the Generative Fill sheet. [Model and terms](https://huggingface.co/heypatkay/solume-big-lama-coreml/tree/c4358e4356b4c576a7fbfaabf27b5ffd5d9d7758)

## Automate a fill

Configure the model on the Mac first. Send `generativeFill.apply` to the document command route with the current document revision. Use empty parameters for a blank prompt. For a text prompt, use parameters such as `{"prompt":"a blue ceramic mug","seed":472122}`. An optional seed is an integer from 0 through 4,294,967,295. The API chooses a seed when omitted. Use `generativeFill.cancel` with the active operation ID to request cancellation. State fields report each model’s configuration and readiness. [API reference](AUTOMATION_API.md#local-generative-fill)

The selected area can be up to 4,194,304 pixels within a 4,096 px span on either axis. The model works on 512 × 512 sRGB context and a mask. Photato maps the generated patch back to document coordinates and colors, preserving the original selection coverage. Prompts are one line, up to 256 characters and within the tokenizer’s 77-token window, including boundary tokens.

Photato uses opaque pixels around the selection to reduce color seams. The correction tapers inward to preserve the generated colors farther inside the selection. The edit retains the original feathering and preserves pixels outside the mask.

Photoshop’s documented workflow includes a model picker and variation sets. Photato’s model generates one patch per operation. Editable variation sets, the Adobe Execute Actions form and output equivalence to Photoshop remain open. [Photoshop desktop workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/edit-images-with-generative-fill.html) · [Adobe Execute Actions model reference](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/guides-v2/execute-actions-models)
