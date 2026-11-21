# Local Generative Fill

Select part of a still RGB image and choose **Edit > Generative Fill…**. Describe what to add or leave the prompt blank to fill from surrounding pixels. Photato places the result above the visible stack, preserves feathering in an editable layer mask and gives the generation one Undo step.

Inference runs on Apple Silicon with macOS 26 or later. The models are optional downloads.

## Set up the prompt model

1. Review the model terms. Download the **ORIGINAL** Core ML conversion of Runway Stable Diffusion 1.5 Inpaint. The pinned ZIP is about 2 GB and is distributed separately under CreativeML OpenRAIL-M. [Model and terms](https://huggingface.co/Guernika/CoreMLStableDiffusion/tree/9252390067013229c60c491bae7b66a6249752b9) · [Pinned ZIP](https://huggingface.co/Guernika/CoreMLStableDiffusion/resolve/9252390067013229c60c491bae7b66a6249752b9/Models/ORIGINAL/Runway_SD1.5_Inpaint.zip)
2. Check the download with `shasum -a 256 Runway_SD1.5_Inpaint.zip`. The checksum should be `836af8415b0e92b7825532f61577cbddab106cb8950f0e8e47d2a5bf4d8fec00`.
3. Unzip it. Enter a nonempty prompt in Photato’s Generative Fill sheet, choose the extracted `Runway_SD1.5_Inpaint` folder, and select **Generate**.

## Choose and save variations

The sheet generates three variations by default for a text prompt. Set **Variations** to one, two or three before generating. Select the generated layer and use **Properties > Variation** to switch between results. Photato stores each result as an editable layer comp inside an embedded Smart Object. Photato can reopen the alternatives, their shared mask, and their prompt, model and seed information from its native format, PSD and PSB.

Choose **Properties > Generate More…** to keep another batch in the same layer. The sheet starts with the selected variation’s prompt. Edit it to try another description. Photato uses the original image samples and selection captured when the layer was created, including after reopening. Existing results, the current layer mask and the layer’s placement are kept, and the first new result becomes active. Undo removes the batch and restores the earlier selection. A layer can hold up to 64 variations within the embedded PSD storage limit.

To keep more of an existing result’s composition, choose that variation in **Properties**, open **Variation actions**, and choose **Generate Similar…**. The sheet names the reference and starts with its prompt. Photato uses the chosen result inside the original selection as the starting image for partial denoising. The batch keeps the source variation and records its ID. You can reopen the results, reference and original mask in Photato, PSD and PSB.

New prompted fills save the prepared image area locally inside the layer. Save a flattened export when sharing artwork without its editable variation data. Build 702’s saved variations can still be selected. Generate More and Generate Similar require a fill that captured its original context.

Prompted inference uses a separate local Swift process. Cancel discards the pending edit and leaves the document unchanged. Blank-prompt fills use LaMa to produce a single result.

## Set up the blank-prompt model

Run `python3 scripts/prepare-inpainting-model.py /path/to/new-model-folder` from the native project directory with Xcode installed. The script downloads the pinned model files and checks their hashes before compiling the Core ML package. Leave the prompt blank and choose the resulting `LaMa512.mlmodelc` package in the Generative Fill sheet. [Model and terms](https://huggingface.co/heypatkay/solume-big-lama-coreml/tree/c4358e4356b4c576a7fbfaabf27b5ffd5d9d7758)

## Automate a fill

Configure the model on the Mac first. Send `generativeFill.apply` to the document command route with the current document revision. Use empty parameters for a blank prompt. For a text prompt, use parameters such as `{"prompt":"a blue ceramic mug","seed":472122,"variationCount":3}`. The API defaults to one result. A supplied seed must be an integer from 0 through 4,294,967,295. Photato advances the seed for each alternative and wraps at the upper limit. The API chooses a starting seed when omitted.

Use the returned `selectedVariations` state to find the layer comp IDs, then call `smartObject.layerComp` to choose one. To add a batch, set `targetLayerID` to the selected Generative Fill layer’s ID and send `generativeFill.apply` again. Omit `prompt` to reuse the selected result’s prompt. Omit `seed` to use the next unused seed range. Use `generativeFill.cancel` with the active operation ID to request cancellation. [API reference](AUTOMATION_API.md#local-generative-fill)

Add `referenceVariationID` to that request to use an existing variation from the target layer as the Generate Similar reference. An omitted prompt uses the reference variation’s prompt. The response reports `canGenerateSimilar` and the reference ID for each new result.

The selected area can be up to 4,194,304 pixels within a 4,096 px span on either axis. The model works on 512 × 512 sRGB context and a mask. Photato maps the generated patch back to document coordinates and colors, preserving the original selection coverage. Prompts are one line, up to 256 characters and within the tokenizer’s 77-token window, including boundary tokens.

Photato uses opaque pixels around the selection to reduce color seams. The correction tapers inward to preserve the generated colors farther inside the selection. The edit retains the original feathering and preserves pixels outside the mask.

Photato supports Generate Similar for its local prompted Generative Fill layers. Adobe also documents the operation for Generative Expand, Generate Background and Generate Image. Those workflows, Adobe Execute Actions request compatibility and Firefly output equivalence remain open. [Photoshop desktop workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/edit-images-with-generative-fill.html) · [Generate Similar](https://helpx.adobe.com/photoshop/desktop/generative-ai/get-new-variations-of-generated-content-with-generate-similar.html) · [Adobe Execute Actions model reference](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/guides-v2/execute-actions-models)
