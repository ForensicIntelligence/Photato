# Generate Image

Choose **Edit → Generate Image…** or **Generate Image…** in the canvas controls. Enter a description, choose one to three variations, and click **Generate**. You can switch between results in Properties. All variations live in one editable embedded Smart Object above the original layers. The generated image fills the canvas using a centered crop. The original layers and any selection remain intact.

Local generation requires Apple Silicon, macOS 26 or later, and the same optional Stable Diffusion Core ML model used by prompted Generative Fill. If you have already configured the prompt model, Generate Image uses it. Otherwise choose the extracted model folder when prompted. The model generates 512 × 512 images. Photato scales their placement separately so the original generated pixels stay available for editing. [Model setup](LOCAL_GENERATIVE_FILL.md)

**Generate More** creates another batch from the selected variation’s prompt. You can change the prompt before starting. **Generate Similar** also uses the selected variation’s own pixels as a reference. You can switch variations and append batches after reopening Photato, PSD and PSB files in Photato. Each committed generation and each variation choice has its own Undo step.

The existing **Edit → Create with Apple Intelligence…** workflow opens Apple’s Image Playground, including Private Cloud Compute on eligible systems. Apple’s system sheet manages that provider’s availability and consent. Local generation uses the separately configured model and the prompt alone for new images.

## Automation

Send `generativeImage.apply` to the Photato document commands route with the current revision. New images require a `prompt`. `seed` and `variationCount` are optional. Add `targetLayerID` to append to the selected Generate Image layer and `referenceVariationID` to use an existing variation as a reference. Discover the result and choices under `generativeFill.selectedVariations`. Use `smartObject.layerComp` to switch the selected result. Use `generativeFill.cancel` with the operation ID to cancel active local generation. [Automation API](AUTOMATION_API.md)

Adobe documents a different hosted model for its desktop workflow and lists it in the Photoshop API v2 Execute Actions model inventory. The public Firefly Generate Image API uses its own contract. Photato’s model selection, resolution, generation fidelity and Adobe-compatible action coverage are still open. [Photoshop desktop workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/generate-image-with-descriptive-text-prompts.html) · [Photoshop API v2 model inventory](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/guides-v2/execute-actions-models) · [Firefly Image5 contract](https://developer.adobe.com/firefly-services/docs/firefly-api/guides/how-tos/cm-generate-image/feature-guide)
