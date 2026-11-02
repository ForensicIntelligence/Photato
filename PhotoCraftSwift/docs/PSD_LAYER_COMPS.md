# Layer Comps in Photoshop files

Photoshop2026 is the target. Adobe's public file specification defines resource1065 and the descriptor/metadata envelopes. Public ag-psd field definitions and one MIT-licensed saved file provide additional format evidence. A second fixture path has identical bytes and is not a second independent sample. A reported Photoshop2026 visibility-inheritance defect in the original project is supporting evidence, not an acceptance oracle. No Photoshop implementation or script code is copied.

PSD/PSB opening now imports supported saved comp catalogues into the native Layer Comps panel and API. Missing visibility values inherit the preceding value, defaulting to visible; integer position deltas resolve to independent saved states. Comps recording no properties are valid. Comments, original integer IDs, current comp and prior state are retained. Imported PS IDs map reversibly to namespaced UUIDs; newly created UUIDs receive stable file integer IDs. Native files retain UUIDs directly.

| Data | Current support |
| --- | --- |
| Catalogue, visibility and integer position | Editable PSD/PSB import/export; each saved variation applies independently |
| Appearance | Existing unchanged appearance can be retained; changing appearance records remain guarded |
| Embedded Smart Object comp choice | Source catalogues and independent selected instance choices survive PSD/PSB |
| Parent comp recording of child choices | Native81 support remains; PSD record mapping is still open |
| Effect reference metadata | Original reference and resolved per-comp reference values are transported; full anchored-style geometry remains unqualified |
| Other layer metadata | Retained byte-for-byte when cmls is rewritten or cleared |

Ordinary files and the Photato API use the same Swift serializers. The Adobe-compatible output encoder uses that serializer too; no new Adobe comp route or execute-actions descriptor is advertised. Unsupported appearance/parent-child/fractional/missing-layer records reject before file replacement or result publication. The existing linked-original permission policy is unchanged; cached-only linked comp selection needs further mapping.

Older native documents may contain an opaque Photoshop comp resource without a typed library. Saving them preserves the original resource, per-layer metadata and layer IDs. A nil typed library is not interpreted as deletion. Explicit Clear records native82 intent and removes comp resources/records from Photoshop outputs while retaining other metadata. Undo and recapture preserve or replace that intent. Opaque legacy records are not automatically promoted to fully editable native comps in this increment.

No-property comps and explicit source-comp clearing require native82 so older readers cannot silently lose those semantics. Per-instance choices alone remain80; parent child-choice records remain81; ordinary nonempty-property libraries remain79 where no newer semantics are present. Library/file/source/render budgets remain the existing implementation limits, not Photoshop maximum-capacity qualification.

## API

Existing `layerComps.edit`, imports, file downloads/copies and comp exports gain supported interchange. State/schema adds boolean `sourceCompsCleared`. Capture can record no properties; the old all-false rejection was an arbitrary restriction contradicted by the saved-file reference. Native downloads require `X-Photato-Archive-Version:82` for no-property/explicit-clear semantics. The catalogue remains213 commands and Actions30. Factory menus/shortcuts and tool/modifier cursors do not change.

## Validation

All 13 new cases pass. Source03 passes 408 of 409 affected optimized cases; one existing linked PSD/PSB cache case retains two strict failed assertions. Both diagnostic vectors match332. There are no unexpected errors or crashes. The separate reader verifies six output files across8/16/32-bit PSD/PSB metadata. These are native/independent-format checks, not Photoshop2026 execution or full-current-suite acceptance.

Tests cover the independent five-comp file, inherited visibility, offsets/prior state, all-depth round trips, untouched source/history, original IDs, effect-reference/other metadata, explicit clear and legacy opaque retention, malformed/unsupported records, atomic file preservation, embedded shared choices, real HTTP import/edit/download/native copy, archive negotiation and the Adobe output encoder. The independent Python reader inspects descriptors, not pixels. Its first draft misses alternative high-depth layer sections; that failed run and the repair are preserved. Source output sets overlap and are not counted as independent new fixtures.

The Mac remains locked. Full rich appearance, parent-child descriptors, fractional/group/reference geometry, legacy migration, linked cached sources, modes, Actions and owned Photoshop/UI/defaults/platform/capacity/performance/current-green acceptance remain open. No entire work package is closed.

[Evidence](PSD_LAYER_COMP_REFERENCES.json) · [Adobe file specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Adobe LayerComp reference](https://developer.adobe.com/photoshop/uxp/2022/ps-reference/classes/layercomp) · [Public fixture](https://github.com/Agamnentzar/ag-psd/tree/a74425db6584cc07b1cc135e370916cb4eccfb32/test/read-write/layer-comps) · [Reported visibility behavior](https://github.com/storytold/photocraft/issues/8093)
