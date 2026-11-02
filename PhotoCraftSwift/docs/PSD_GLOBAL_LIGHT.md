# Global Light in Photoshop files

Photoshop2026 defines the target. Adobe documents shared lighting for participating shadows and bevels. Its file specification defines resource1037 (four-byte angle) and1049 (four-byte altitude). The native editor already offers shared-light controls; supported PSD/PSB opening and saving now retain that shared state.

Both resources are read with defaults120°/30° when just one is present. Duplicate, truncated and invalid values reject. Export writes canonical angle0–359° and altitude0–90°. Existing resource order, names and padding survive unchanged or edited values. Native documents keep fractional precision; PSD/PSB outputs reject fractional shared-light fields before replacing a file. Inactive per-effect local angles and each shadow's Use Global Light flag survive saving.

Legacy styles without explicit document light export a single unambiguous shared fallback. Divergent fallbacks require an explicit choice. Older native files may hold the original resources: opening adopts them only if every participating style has matching fallback settings. It leaves conflicting or malformed opaque native metadata alone. Source files are never rewritten during adoption. Native75 negotiation is required where shared-light state is promoted; latest native format remains82.

Ordinary, Indexed/Bitmap and Multichannel PSD/PSB resource paths use the same mapping. The two native effect renderers canonicalize shared direction consistently; a local bevel's altitude now remains independent of the document light. This does not remove the existing rich-effect PSD save guards or qualify full bevel/style interchange.

## APIs and history

Existing `document.globalLight`, `layer.style`, imports, downloads/copies and the native dialog use the same model, history and serializers. Capabilities describe the actual interchange limits. Adobe-compatible output encoding uses that serializer; no invented Adobe lighting operation is added. The213-command catalogue and Actions30 remain unchanged. No new tool, modifier action, factory menu or shortcut is introduced.

## Evidence

All 11 new cases pass. Source02 passes 482 of 484 affected optimized cases, retaining two existing strict comparison failures (120 assertions): linked PSD/PSB cached pixels and source-effect words. Their diagnostic vectors match332. There are no unexpected errors or crashes. A separate reader verifies resources and style flags in six 8/16/32-bit PSD/PSB outputs. Native round trips and independent metadata checks do not establish Photoshop2026 pixel/UI equivalence or full-current-suite acceptance.

Tests cover native dialog Cancel/Commit, API equality/history/busy requests, legacy native file/API adoption, all-depth round trips, exact native composite words, resource corruption/stale replacement, named-resource preservation, local bevel independence, periodic directions, Indexed/Multichannel planes, atomic precision/conflict errors and Adobe output encoding. Older clients are explicitly rejected where native75 is necessary. These targeted native comparisons do not substitute for independent Photoshop rendering.

The existing public Layer Comp file supplies shared resource values but no modern styles; Source01's erroneous new style assumption fails and is preserved. A separate MIT public shadow payload records global participation with inactive local120° against document132°. Only that628-byte raw descriptor is added as a test fixture. The full original effect file is not qualified for native import. No Photoshop implementation is decompiled or copied. Actual Photoshop capture remains unavailable because the Mac is locked.

All104 package scopes remain open. Rich effects, Photoshop pixels/UI/defaults, full suite, supported platforms, maximum capacity and physical60fps are unqualified. Installed283/private full298/store332 are unchanged.

[Evidence](PSD_GLOBAL_LIGHT_REFERENCES.json) · [Adobe file specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Adobe Global Light guide](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/apply-layer-effects/set-a-global-lighting-angle-for-all-layers.html) · [MIT saved-file source](https://github.com/Agamnentzar/ag-psd/blob/a74425db6584cc07b1cc135e370916cb4eccfb32/test/read-write/effects/src.psd)
