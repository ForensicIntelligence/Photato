# Background layers

**Checkpoint349:** Selected RGB Background pixels now use captured background-color holes, opaque canvas clipping, shared preview/commit/history and Actions33/API. The earlier Background transform gap described below is historical348/347 scope. Other transform targets and full acceptance remain open. [Current guide](BACKGROUND_PIXEL_TRANSFORM.md).

Photoshop Background is explicit layer identity. A layer named Background alone remains ordinary. New opaque RGB File/New documents create one opaque root at the canvas bottom, Normal at100% opacity. Transparent documents create a regular layer. Old native files retain their earlier semantics. The model protects Background position and transparency while allowing painting; unsupported changes require conversion.

Layer → New uses the factory Background/Layer conversion command. Layer from Background opens name/color label/mode/opacity options, with Cancel and one Undo on commit. Double-clicking the Background name opens that sheet; the lock command converts immediately to Layer0. Background from Layer fills transparency and canvas padding from the captured background swatch, moves the layer to the bottom, names it Background and restores Normal/100%. The first from-Layer implementation accepts one ordinary RGB raster root without masks/styles/Smart Objects/filters; other contexts need preparation and remain open.

Clear and Cut on Background replace selected coverage with the captured background color. Normal Eraser paints with that color and keeps opacity. Background/Magic Eraser converts to Layer0 before removing transparency. The retained brush-preview path and committed stroke share the same color treatment. Canvas extension/crop/image-size/canvas-turn operations reframe the Background to its new canvas while retaining one identity. Sparse/tiled storage and immutable opacity proofs avoid materializing a uniform300000-square plane or scanning all opaque samples on each validated paint edit. Practical maximum dense capacity and physical60fps still need measurement.

## Storage and automation

Native83 retains identity, while lower versions cannot admit these document semantics. Downloads containing Background require `X-Photato-Archive-Version: 83`. Old documents/operations keep their required versions. Semantic conversion and Background-clear Actions use version32; earlier Action versions remain readable. Duplicate layers become regular copies. PSD/PSB supported RGB Background records omit the layer transparency channel and carry protection and lyid0. Import uses structural channel/protection/canvas criteria, never the name alone. Full Photoshop interpretation and round-trip behavior still need live validation.

`layer.background` requires layerID/operation; toLayer accepts optional name, color label, mode and opacity. fromLayer accepts optional opaque backgroundColor RGBA, defaulting to the desktop background swatch. `pixels.clear` requires layerID and optionally that swatch. Both commands share native preparation, revision/busy/source guards and one Undo transaction. State/capabilities expose identity, active role, conversion availability and sheet ownership. The catalogue now contains227 commands.

```json
{"command":"layer.background","revision":"<current>","parameters":{"layerID":"<UUID>","operation":"toLayer","name":"Editable","opacity":1,"mode":"Normal"}}
```

Published `POST /v2/create-composite` accepts `type: background_layer` with add/edit/delete operations. Add requires image.source.url and supplies no placement; edit supports visibility/image replacement and explicit convertToLayer/convertedLayerName. Ordered subsequent ordinary-layer edits use the converted name. Move/placement and unsupported direct properties reject. Existing JSON output marks Background, its conversion availability and sole-background id0. Images pass through native profile/depth conversion; exact Adobe placement/fill/default/output behavior remains unqualified. Photato operations do not imply support for every Adobe endpoint or actionJSON descriptor.

## Qualification

All 20 new cases pass. Of 603 affected optimized cases, 602 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python parser verifies six owned8/16/32-bit PSD/PSB Background records. Sparse300,000 ×300,000 opaque planes are tested. These checks do not establish Photoshop output/UI/default equivalence, full-current-suite acceptance, supported-platform coverage, maximum dense capacity or physical60fps.

All104 workflow packages remain open. Background selected-pixel transforms and richer contexts remain major work. Native/API tests do not replace Photoshop comparisons. Last actual native app access is344's locked-Mac observation. Installed283/private source298/store archive332 are preserved; no new install/archive/push/upload/review/release.

[Evidence](BACKGROUND_LAYER_REFERENCES.json) · [Adobe desktop conversion](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/convert-background-and-regular-layers.html) · [Published background guide](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/layer-operations-background)
