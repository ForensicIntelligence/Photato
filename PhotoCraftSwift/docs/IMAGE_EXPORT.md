# Export As and Quick Export

**Checkpoint342 follow-up:** Selected Export As layers now share ancestor group context with Layers to Files and existing Adobe per-output selections. Canvas-fill assets use document bounds. See [layer-file export evidence](LAYER_FILE_EXPORT_REFERENCES.json) for the331 affected passes and remaining contextual/Photoshop gates.

Photoshop2026 defines the target. The former Export As command opened a basic flattened-image save panel. It now opens a native asset workspace with a preview and file settings. Document and Layer menus keep their factory shortcuts. Quick Export and Export Preferences use their existing menu positions.

Choose a document, selected layers/groups or artboards, then PNG, JPEG or GIF. Options include image dimensions, resampling, centered canvas clipping/padding, transparent trimming, transparency, multiple scales and suffixes. Width or height alone preserves aspect ratio; supplying both sets explicit dimensions. A zero dimension in the native controls means automatic. Selected hidden roots can be exported without changing visibility in the document; hidden descendants retain their own state. Names are sanitized and disambiguated, including case collisions.

Native previews coalesce changes for120ms, wait for a canceled encoder to finish, and display a bounded thumbnail. Reframing retains source raster/mask samples and affine geometry; it does not apply the transform a second time. File size/dimension listings use actual encoded outputs. Cancel discards the workspace. Export uses an immutable snapshot and refuses a changed/revoked source before handing out an API result. Native folder publication checks all pre-existing destinations; existing files are preserved. If a filesystem error interrupts a multi-file publication, already exported files remain. An explicit single-file save uses atomic replacement through the selected destination panel.

Quick Export preferences and last-used Export As settings are separate. Quick Export asks for a destination each time. Export Preferences retain format, quality, transparency, sRGB/profile and limited metadata choices. Export As remembers format/options/scales after a successful export, but resets source-specific dimensions/IDs for a new workspace. Neither adds document history. JPEG quality uses the existing native0–12 mapping; identical Photoshop quantization is unqualified. GIF uses a native palette and one-bit alpha, requires sRGB and cannot retain the optional ICC/descriptive metadata. PNG8 optimization is not implemented.

Exports can convert to sRGB or retain supported encoded RGB profiles. Custom RGB32 web output requires sRGB conversion. Profile embedding is independently selectable where supported. None removes original descriptive metadata. The limited metadata option retains author, copyright status/text and rights URL, with no original title, keywords, EXIF packet or GPS data. It does not yet implement the complete Photoshop contact-information set.

## APIs

The Photato API adds `image.export`, `image.export.cancel` and `export.preferences`, bringing216 commands. `image.export` accepts the documented settings object and returns a ZIP of assets plus `photato-export-manifest.json`; transfers must be enabled. Persistent preference writes additionally require the existing native preference-change opt-in. State exposes workspace, operation ID and preferences. Invalid, busy, stale, canceled and revoked requests do not change source/history. No arbitrary server filesystem destination is introduced.

```json
{"command":"image.export","revision":"<current revision>","parameters":{"settings":{"format":"png","target":"document","scales":[{"factor":1,"suffix":""},{"factor":2,"suffix":"@2x"}],"convertToSRGB":true,"embedProfile":false,"metadata":"none"}}}
```

Adobe's published `POST /v2/create-composite` uses `outputs[].layers`, with exactly one id or name per reference. The local manifest supplies IDs; ambiguous names reject. Shared native isolation supports single-layer/group/artboard bounds, document bounds and transparent trimming. Single-layer output defaults to layer bounds; document/multiple-layer output defaults to document bounds. PNG/JPEG/TIFF support multiple layers composited into one output; editable PSD is single-layer/group/artboard only. Each selection enters the encoding-cache key, and existing ICC/options/job lifecycle continue independently per output. Execute-actions retains its separately qualified document-bounds contract. No new Adobe export endpoint is invented.

## Validation and limits

All 19 new cases and 317 affected optimized cases pass, with no failed assertions, unexpected errors or crashes. A separate reader verifies five owned PNG outputs and 412 analytical RGBA channels. This is native/format evidence; full-current-suite and Photoshop2026 output/UI/platform acceptance remain open.

Coverage includes analytic resampling/canvas pixels, off-canvas/hidden/group isolation, artboards, format/transparency/profile/metadata choices, high-depth conversion, budgets/naming/cancellation, native preview/Cancel, real HTTP byte equality and manifest, source/history preservation, permission/invalid/busy/stale/revocation errors, deterministic cancellation, preference persistence, file collision protection and menu/shortcut bindings. Adobe tests cover mixed output-cache independence, ID/name/crop validation, editable group PSD and hosted asynchronous output.

Per-asset independent options, complete contact metadata, PNG8 optimization, Save for Web, Layers to Files, slices/asset generation, selected temporal layers, full rich/group/clipping/effect bounds, all resamplers/defaults and encoder byte equality remain open. The existing Data encoder/resource budgets do not prove maximum dense capacity or physical60fps. The Mac is locked, so no new live Photoshop/native UI acceptance is claimed. The last complete inventory remains332;11 strict comparison cases remain documented outside this selection. Native82 and Actions30 are unchanged, and all104 package scopes stay open.

[Evidence](IMAGE_EXPORT_REFERENCES.json) · [Adobe Export As options](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/export-settings-and-export-location-preferences.html) · [Published layer output contract](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/export-layers-migration)
