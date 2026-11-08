# Sky preset groups and batch import

Sky Replacement can organize imported skies into named groups. The Group picker shows all skies, Ungrouped, or one group. Manage Groups provides Create, Rename and Delete; Move Sky To changes the selected sky’s membership. Delete asks whether to keep the images in Ungrouped or remove them from the library. Existing document layers retain their embedded pixels.

Import accepts several image files. Every image must decode, and the complete library must fit its limits, before any are saved. Invalid images, capacity/storage errors, cancellation and stale context leave the existing library unchanged. Native group dialogs also reject changes to their captured library, filter or selection. Library management does not change document pixels, selection, dirty state or Undo history.

## API

The existing `sky.library` command supports these additional operations with the normal shared document and revision:

| Operation | Parameters |
|---|---|
| `group.create` | `name` |
| `group.rename` | `groupID`, `name` |
| `group.delete` | `groupID`, explicit `removeSkies` boolean |
| `move` | one to 64 unique `skyIDs`, explicit `groupID` UUID or null |
| `importBatch` | `images: [{name, data}]`, optional `groupID` |

`data` is base64 image content. Existing `import` accepts optional `groupID`; rename/delete/export/list remain supported. Responses include current `state` and `revision`, created `groupID` or imported `skyIDs`, plus the existing `skyID` for a single import. State includes groups, image memberships and native filter/dialog availability. Unknown/irrelevant/missing fields reject400; invalid context/image/capacity rejects422; stale/busy/cancelled/revoked preparation rejects409. Storage failure preserves the library. The native and API paths share preparation and persistence.

## Storage and limits

The internal plist is version 2, with strict version 1 migration on the next successful edit. Unknown or corrupt libraries are preserved and editing is disabled. This format is not Adobe `.sky` interchange.

The library supports64 images,64 flat groups,48 MiB aggregate image data and64 MiB on disk; each native image supports16 MiB. API requests retain their4 MiB transport limit and3,000,000base64 characters per image. Sky Replacement and sky images still support8,388,608pixels. These are separate budgets, not Photoshop capacity parity.

Native 90, Actions 58,266 typed commands and the observed factory menu/shortcut inventory are unchanged. There is no new pointer tool/modifier action. The pinned Adobe v2 contract has no dedicated sky-library route; this is a Photato API operation.

## Verification and remaining work

All 51 selected Debug checks and the same51 optimized checks on Apple Silicon and translated Intel pass, including 9 new methods. Tests cover legacy migration/retained bytes, group lifecycle and membership, corrupt preservation, capacity/storage rollback, native filter/Cancel/stale dialogs, atomic multi-image import, HTTP agreement/strictness and stale/busy/revoked work. Existing sky, factory-menu/cursor and independent RGB32 checks pass. An owned offscreen rendering verifies layout only; native live, exact Photoshop output/defaults and supported physical platforms remain unqualified.

Large sky canvases/masks, `.sky` import/export, recents/default skies, nested groups/reorder, wider multi-selection and full AI09 acceptance remain open. No package completion or overall percentage is inferred from these checks.

[Evidence](SKY_PRESET_GROUPS_477.json) · [Developer record](DEVLOG.md#dev-step-477)
