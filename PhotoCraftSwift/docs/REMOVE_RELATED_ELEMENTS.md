# Remove related shadows and reflections

Choose **Remove** in the J tool group. In the processing menu beside **Mode**, choose **Remove Related Elements…**. Set up the local LaMa512 fill model and the Related Elements detection model. Both models run on this Mac. The workflow requires Apple Silicon with macOS 26 or later. [Generative Remove setup](REMOVE_GENERATIVE.md)

Choose **Mark Object**, then brush or loop around one object. Press Return or choose **Find Related Elements** to preview its effects. Shadows and reflections have separate checkboxes. The canvas shows the marked object in pink and tints each enabled effect separately. The review includes a small margin to cover uncertain edges. Use Add or Subtract to refine the coverage. **Apply** puts the repair on a new raster correction layer in one undoable edit. Escape or **Cancel** clears the review.

**Sample All Layers** controls the image used for detection and fill. The active selection limits which pixels can change. The analysis reads a bounded crop around the mark and uses that shape to associate the detected shadow or reflection. One crop can contain up to 16 megapixels. Other nearby effects can still be mistaken for part of the marked object, so check the overlay before applying.

Footprints, smoke, steam, water wakes, Adobe’s separate Enhance action and matching cloud output remain open. [Adobe’s desktop workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/remove-related-elements.html)

## Detection model setup

The converter accepts the publisher’s CLIPSeg files at revision `999e0328d9e10b484360c477313983f9afdd7050`. The Hub model card labels the revision Apache-2.0. Place `config.json`, `merges.txt`, `model.safetensors`, `preprocessor_config.json`, `special_tokens_map.json`, `tokenizer_config.json`, and `vocab.json` from that revision in one directory. The converter checks the files against the pinned contents. The optional model weights are supplied separately. [CIDAS publisher files](https://huggingface.co/CIDAS/clipseg-rd64-refined/tree/999e0328d9e10b484360c477313983f9afdd7050) · [Upstream project](https://github.com/timojl/clipseg)

Use Xcode’s command-line tools and a Python environment with `torch==2.7.1`, `transformers==4.49.0`, `coremltools==9.0`, `numpy==1.26.4` and `safetensors==0.8.0`. Run the converter from `PhotoCraftSwift`.

```sh
python scripts/convert-related-elements.py /path/to/clipseg-files /path/to/output
```

Choose the resulting `RelatedElementsV1.mlmodelc` in **Choose Detection Model…**. Photoshop documents a cloud provider for this workflow. Photato’s models are local.

## Photato API

Use the authenticated shared-document `retouch.remove` command with the current revision. Send `beginRelatedElements` to start the review, `stroke` to mark the object, and `findRelatedElements` to generate suggestions. This converts the initial strokes into the reviewed object mask. `configureRelatedElements` accepts `enabledElements`, with `shadow` and `reflection` as available keys. An empty list clears the effects and retains the object mask. Subsequent `stroke` commands refine the visible coverage. `apply` creates the correction layer. The existing `preview` and `cancel` operations apply to this review. The full mask preview requires document-transfer permission and remains capped at 16 megapixels.

The response’s `removeTool.relatedElements` state reports starting availability, pending analysis, and the suggested effects and their enabled state. Models are selected in the editor. The pinned Firefly Photoshop v2 contract has no dedicated route for this operation. [Automation API](AUTOMATION_API.md) · [Adobe v2 reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/)
