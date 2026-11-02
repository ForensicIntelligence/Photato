# Layers to Files

File → Export → Layers to Files now opens a native destination, prefix, visibility, format, ICC and codec-options dialog with Run, progress and Cancel. Photoshop2026 is the target; Adobe's public guide supplies that workflow. Exact defaults, numbering and all contextual results remain subject to Photoshop comparison. No proprietary script is copied or inspected.

The batch visits individual layers from top to bottom through groups. Groups supply ancestor opacity/masks and remain editable containers where supported; they do not create duplicate output files. Visible Layers Only follows eye visibility through ancestors, including layers whose opacity is zero. With that option off, hidden target/ancestor eyes are enabled in the private copy. Clipping references to excluded peers are released; exact Photoshop clipping/adjustment/group semantics are not qualified. Optional trimming crops transparent canvas. Empty results retain a transparent1×1 canvas when trimmed.

| File type | Native behavior |
| --- | --- |
| PSD, PSB, Photato | Supported editable layers/ancestors and depth; existing streaming file writers |
| TIFF | Flattened current8/16/32-bit depth with None/LZW/ZIP choices |
| PNG-24, JPEG | RGB8 with transparency or white matte; PNG interlace and JPEG0–12 quality |
| PNG-8 | Existing native indexed palette/dither conversion and single transparent entry;8,388,608-pixel processing limit |
| BMP, Targa | Native ImageIO RGB8 output; no embedded ICC option |
| PDF | One rasterized page per layer, at physical document size; full PDF/profile/print parity remains open |

PSB and Photato are additional formats. Editable Photato always keeps its interpreting profile. Other supported formats offer ICC inclusion; custom HDR/ICC and encoder details retain existing limitations. Format availability observed on macOS27 does not prove behavior on every supported macOS14+/Intel host.

Names contain an optional prefix, a zero-based four-digit ordinal, a sanitized layer name and extension. Source names and original files remain unchanged. All files are prepared privately before publication. Existing destination names reject before linking outputs; interrupted publication rolls back only matching newly created files. A changed source rejects before publication. Native staging does not accumulate the batch's encoded payload in memory. It uses the existing streaming PSD/PSB/native writers and existing other-codec budgets, without applying the API ZIP aggregate cap to native file output.

## APIs

`layers.export` and `layers.export.cancel` bring the Photato catalogue to218 commands. Export requires enabled document transfers and returns ZIP plus `photato-layer-files.json`. Optional settings choose format, prefix, visible-only, trim, ICC, transparency, codec options or individual layer UUIDs. State exposes workspace, operation ID and completed/total/current-layer progress. Invalid, busy, stale, canceled and revoked operations preserve source/history and discard private staging. API clients receive files rather than arbitrary server filesystem access.

```json
{"command":"layers.export","revision":"<current revision>","parameters":{"settings":{"format":"png24","prefix":"assets","visibleOnly":true,"trim":false,"includeICC":true}}}
```

Adobe's existing published create-composite output layer selection shares ImageAssetSelection, including ancestor context and document/layer/trim bounds. Canvas fills use document bounds rather than alignment restrictions. The published format/crop/selection contract remains separate from this batch command, and no new Adobe route is invented. Native and Adobe source isolation use one implementation; exact service output remains unqualified.

## Validation

All 14 new and 331 affected optimized cases pass, with zero failures, unexpected errors or crashes. The independent reader verifies four PNGs and384 analytical RGBA channels. A260-file native batch totals137216120bytes and publishes successfully while the128MiB API ZIP correctly rejects it. These owned/native checks do not establish full Photoshop2026/default/UI/codec/platform/capacity or current-full-suite acceptance.

The tests cover all ten containers, high-depth/editable outputs, parent alpha and transparent trim, eye/zero-opacity handling, hidden layers, indexed transparency/profile flags, filenames/manifest, collisions, injected publication failure and rollback, native Run/API PNG-24 file byte equality, permissions/invalid/stale/busy conditions, deterministic cancellation/revocation/staging cleanup, external source changes and factory menu/Cancel behavior. The260-file test uses tiny synthetic PSDs with owned metadata, not a dense maximum-sized image. The PNG reader checks CRCs, dimensions, opacity/color and profile omission without the native decoder.

Full I05, Photoshop behavior/output/defaults, current suite, supported-platform, maximum dense capacity and physical60fps gates remain open. The latest actual native-access observation remains341's locked Mac; it is not re-polled here. The last complete inventory remains332, with11 strict comparisons still documented after a stale-test repair. Native82/Actions30 and all104 package scopes remain unchanged. Installed283/private full298/store332 are preserved.

[Evidence](LAYER_FILE_EXPORT_REFERENCES.json) · [Adobe Layers to Files guide](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/export-layers-as-files.html) · [Published layer-output contract](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/export-layers-migration)
