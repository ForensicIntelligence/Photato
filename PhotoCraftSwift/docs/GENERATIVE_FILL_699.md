# Add local Generative Fill from surrounding pixels

Generative Fill now uses an optional Apple Silicon Core ML model to fill a selection from surrounding pixels. Photato places the result above the visible stack on a raster layer with an editable mask and one Undo step.

## Set up the model

On Apple Silicon with macOS 26 or later, run `python3 scripts/prepare-inpainting-model.py /path/to/new-model-folder` from the native project directory with Xcode installed. The script downloads the pinned Apache-licensed model files, checks their hashes and compiles the Core ML package. In Photato, select part of a still RGB image and choose **Edit > Generative Fill…**. Choose the `LaMa512.mlmodelc` package in the folder, then select **Generate**. [Pinned model and license](https://huggingface.co/heypatkay/solume-big-lama-coreml/tree/c4358e4356b4c576a7fbfaabf27b5ffd5d9d7758) · [Reference workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/edit-images-with-generative-fill.html)

## Editing and automation

Photato samples the visible document around the selection, converts the context to sRGB and scales it to the 512 × 512 model input. The model takes a binary edit mask. The raster result uses the original selection's 8-bit coverage as an editable layer mask, including feathered samples. The original layers remain editable. The affected selection can cover up to 4,194,304 pixels within a 4,096 px span on either axis.

The optional Photato API exposes `generativeFill.apply` with empty parameters and `generativeFill.cancel` with the running operation ID. The operation uses the model chosen on the Mac. Core ML inference runs locally. Adobe documents its cloud Generative Fill through Execute Actions. Photato's compatibility layer still needs the corresponding ActionJSON workflow. [Photato API](AUTOMATION_API.md#local-generative-fill) · [Adobe Execute Actions](https://developer.adobe.com/firefly-services/docs/photoshop/guides/execute-actions/) · [Adobe model reference](https://developer.adobe.com/firefly-services/docs/photoshop/guides/pegasus-worker-v2-models/)

## Verification

The pinned LaMa512 model ran in Debug and optimized Apple Silicon builds. The native transaction and authenticated loopback API returned identical composite samples on the same RGB8 fixture. Tests at RGB8, RGB16 and RGB32 matched protected pixels and every output-mask sample. The owned example retained the editable mask on native, PSD and PSB reopening in Photato. The owned 311 × 213 example checked 60,768 protected pixels and changed 5,457 selected pixels.

The regression fixtures now expect the factory Edit menu binding and both Photato commands. The first broad run still expected the disabled entry and the previous command count.

476 of 477 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with identical assertions in build 698. Both signed preview slices opened offscreen. The local provider fills from context. Text prompts, variant sets and Adobe Execute Actions support remain open. The installed Photoshop session timed out, so Adobe output and physical workflow comparison remain pending. [Qualification](SOURCE_PUBLICATION_699.md)
