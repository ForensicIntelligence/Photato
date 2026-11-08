# Smart Object Convert to Layers

Use **Layer > Smart Objects > Convert to Layers**, or **Convert to Layers** in the Layers context menu. The command restores editable original content. Multiple layers become a group; it does not substitute Rasterize. The selected source Layer Comp is applied before restoration. The original outer Smart Object transform, warp, projection, Smart Filters and stack mode are discarded.

The current path supports static RGB originals with the same working profile, including retained originals from linked files. It never opens an archived link path. Missing/corrupt originals and unsupported mode/profile, PDF/RAW, artboard, variable and temporal transfers reject the whole operation. Those are functional gaps, not completed parity.

Patterns used by fills, shapes and styles travel with the layers. Conflicting IDs receive new identities without replacing destination artwork. Nested Smart Objects retain source data and sharing within their original class. Imported appearance caches are rebound from their captured reference; stale caches remain stale. Source text layout bounds are retained. Existing color management converts pixels between the three supported RGB depths; masks retain numerical coverage.

Wrapper IDs and parent selection, channels, paths, comps and metadata are preserved. A folder retains outer masks/styles/blending when a single source layer cannot absorb those attachments. These placement and attachment policies require installed Photoshop comparisons; source restoration tests do not establish their exact fidelity. Native/API conversion uses one detached prepared transaction for all selected instances, with source/session/revision/cancellation guards and one Undo/Redo.

## API

`smartObject.convertToLayers` takes `layerIDs`, an array of one to8,000 unique Smart Object UUIDs, and the normal shared-document revision. It returns the existing document state, including editable layers and hierarchy. Existing sharing/token/session/busy/revision policies apply. Invalid or unavailable sources fail atomically; no filesystem authorization is inferred from archived paths. Capability metadata documents supported context and remaining limits.

The pinned Firefly v2 contract has no dedicated endpoint for this desktop operation. No Adobe route, descriptor execution, UXP runtime or plugin compatibility is claimed. Portable Actions replay is not implemented for this operation; recording reports unsupported. Native format89 and Actions57 remain current; there are263 typed commands.

## Validation at checkpoint463

All15 new methods pass. Of55 selected methods,53 pass, one existing linked PSD/PSB test fails two exact-byte assertions, and one old archive/API test exits by signal10. Both older failures reproduce on retained462Source06. A separate continuation executes the methods blocked by that crash. Nothing is omitted from the aggregate record. The seven existing independent Photoshop RGB32 and nine cursor regressions pass.

New tests cover editable hierarchy/type/shapes/masks/resources, nested source/cache identities, all nine depth transfers, selected comps, retained links, multi-target clipping/parent/history, native/API equivalent content, cancellation, invalid/stale/busy/locked requests and guarded publication. Own composites and archives are exact for the tested cases; they are not a new independent Photoshop output oracle.

The isolated arm64 Debug package passes minimum macOS14, full production-entitlement, signature, resource and unsigned-payload checks. It is unlaunched and uninstalled. Normal463/universal/live acceptance is pending; latest optimized universal remains461. Exact defaults/output, unsupported workflows, full L05, platform/capacity/performance and all prior failures remain open. [Detailed evidence](SMART_OBJECT_CONVERT_TO_LAYERS_463.json).
