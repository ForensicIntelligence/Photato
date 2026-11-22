# Review and remove general distractions

Choose **Remove** in the J tool group and open **Find distractions → General distractions**. Click **Find**. Photato shows the detected categories with colored overlays and counts. Use **Select All** or the individual checkboxes to change which areas are marked. The gear sets the overlay opacity. Add or subtract brush strokes to refine the marks before clicking **Apply**. Escape or **Cancel** discards the review. Apply creates one undoable edit and honors the current selection.

Photato can group identified objects, poles, spots and dust, unrecognized objects, vegetation, and visual clutter. Only groups with marks appear. **Sample All Layers** analyzes the visible composite. With it off, Photato analyzes the active raster. **Create New Layer** writes a transparent raster correction above the active layer. For the current-layer output, the usual image and transparency locks apply.

Detection runs on this Mac. Apple Vision and local spot analysis work without added models. The optional OWLv2 model proposes less prominent objects for Vision to segment. Photato includes a small, visible margin around the detected objects so the repair can cover their edges. Inspect the overlay before applying, especially when subjects or shadows touch a marked object.

**Auto** can use the separately configured LaMa512 Generative Fill model for a still RGB review on Apple Silicon with macOS 26 or later. The model uses the same reviewed mask and output controls. **Generative AI Off** always uses traditional Remove. Brush marks and the explicit **Generative AI on** mode can also use local fill. [Generative Remove](REMOVE_GENERATIVE.md) [Local Generative Fill setup](LOCAL_GENERATIVE_FILL.md)

Current limits are 16,777,216 canvas pixels for General distractions and 4,194,304 pixels for a traditional fill’s sampling window. The local path uses bounded overlapping regions for wide marks. Very small or hidden objects can be missed, fine texture can be mistaken for dust, and cast shadows can need manual marks. The six category labels and review sequence follow Adobe’s public workflow. Classifier results, fill appearance, and exact Photoshop 2026 output are still open for comparison. [Adobe desktop workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/review-and-refine-general-distractions.html) · [Adobe’s category reference](https://community.adobe.com/announcements-698/general-distractions-removal-in-photoshop-desktop-beta-1555409)

## Optional detection model

Use Google’s Apache-2.0 `owlv2-base-patch16-ensemble` at revision `cfd3195ba4ea9592eec887ded089f4c08eff231d`. Download `config.json`, `merges.txt`, `model.safetensors`, `preprocessor_config.json`, `special_tokens_map.json`, `tokenizer_config.json`, and `vocab.json` from that revision into one directory. The converter verifies each file against the pinned revision before processing. The converted model runs in Core ML on macOS 14 and later. [Model files and license](https://huggingface.co/google/owlv2-base-patch16-ensemble/tree/cfd3195ba4ea9592eec887ded089f4c08eff231d)

Use a Python environment with `torch==2.7.1`, `transformers==4.49.0`, `coremltools==9.0`, `numpy==1.26.4`, and `safetensors==0.8.0`, and install Apple’s Xcode command-line tools. From `PhotoCraftSwift`, run the converter with the publisher directory and an output directory.

```sh
python scripts/convert-distraction-detector.py /path/to/owlv2-files /path/to/output
```

Choose `DistractionDetectorV1.mlmodelc` in the review’s **Choose Detection Model…** control. **Use Built-in Vision** clears the added model. The app runs the compiled model locally, and Python is used only to prepare it. The app and repository omit the optional model weights.

## Photato API

Send `retouch.remove` to the shared document’s authenticated `/v1/documents/{id}/commands` endpoint with the current revision. These are the command parameters in order for a category-only review.

```json
{"operation":"findDistractions"}
```

```json
{"operation":"configureDistractionReview","enabledCategories":["poles","visualClutter"],"overlayOpacity":0.45}
```

```json
{"operation":"apply"}
```

`removeTool.generalDistractions.categories` lists available category keys, counts and enabled state. `enabledCategories` replaces the enabled set and accepts `[]` to clear it. `overlayOpacity` affects display only and leaves the marked pixels unchanged. `stroke` refines coverage and `preview` returns the shared pre-selection mask when the client has document transfer permission. `removeTool.resolvedProcessing` reports `localFillWhenEligible` when Auto can use the configured model. The existing `cancel` operation, busy, revision, sharing and source-change rules apply throughout the review.

The published Firefly Photoshop v2 schema omits a dedicated General distractions route. The Execute Actions descriptor and exact Adobe output remain unqualified. [Photato API](AUTOMATION_API.md) · [Adobe API reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/)
