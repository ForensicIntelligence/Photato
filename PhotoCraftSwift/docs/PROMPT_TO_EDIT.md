# Prompt to Edit

Select a visible pixel layer and choose **Edit → Prompt to Edit…** or the matching canvas action. Describe the change, pick one to three variations and click **Generate**. You can leave the selection empty or use **Select All**. For a previously generated layer, use **Select All**. Use **Generative Fill** for a partial selection.

The generated result goes on an editable Smart Object directly above the source. Photato hides the original layer and keeps its pixels and mask available. Undo restores the original visibility, layer selection and image. The model receives the selected layer’s visual content within the canvas and the instruction. Photato retains the source alpha in the result.

## Local model

Prompt to Edit uses InstructPix2Pix on Apple Silicon with macOS 26 or later. It runs locally and accepts a 512 × 512 reference. Photato fits the image to that input and places the result back in document coordinates. The reference remains in the editable document for future variations. The existing Apple Intelligence editor remains available from the Edit menu. [Model and terms](https://huggingface.co/Guernika/CoreMLStableDiffusion/tree/9252390067013229c60c491bae7b66a6249752b9) · [InstructPix2Pix research](https://openaccess.thecvf.com/content/CVPR2023/papers/Brooks_InstructPix2Pix_Learning_To_Follow_Image_Editing_Instructions_CVPR_2023_paper.pdf)

1. Review the model terms and download the optional **ORIGINAL** Core ML ZIP, about 2 GB. [Pinned model archive](https://huggingface.co/Guernika/CoreMLStableDiffusion/resolve/9252390067013229c60c491bae7b66a6249752b9/Models/ORIGINAL/TimBrooks_InstructPix2Pix.zip)
2. Run `shasum -a 256 TimBrooks_InstructPix2Pix.zip`. The checksum should be `381f4deb21c72aad46076c4cfa76eb8866ab0458156b40b690f211fa325f33ce`.
3. Extract the archive, then choose the `TimBrooks_InstructPix2Pix` folder in Prompt to Edit.

## Review and continue editing

Use **Properties → Variation** to switch between results. **Generate More** applies the new instruction to the saved original. **Edit This Variation** makes the selected result the reference for another edit. Earlier choices stay available when you add a result or reopen the editable Photato, PSD or PSB file.

This local workflow supports still RGB documents and visible root pixel layers outside clipping stacks. Groups, layer styles, non-generative Smart Objects, Firefly model selection, and output equivalence with Adobe’s models remain open. [Adobe’s desktop workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/edit-images-with-prompt-to-edit.html)

## Automation

Send `promptEdit.apply` to the Photato document commands route with the current revision and a `prompt`. The active layer is used by default. Supply `sourceLayerID` to verify that it matches the intended layer. `seed` and `variationCount` are optional. To add results to a saved edit, send `targetLayerID` instead. With `referenceVariationID` the operation starts from that alternative. Use the state at `generativeFill.promptEdit` to check availability and `generativeFill.selectedVariations` to find the editable choices. Cancel through `generativeFill.cancel`. [Photato Automation API](AUTOMATION_API.md)

Adobe separately documents image-to-image instruction editing in its Firefly Generate Image contract. [Firefly Image5 API](https://developer.adobe.com/firefly-services/docs/firefly-api/guides/how-tos/cm-generate-image/feature-guide)
