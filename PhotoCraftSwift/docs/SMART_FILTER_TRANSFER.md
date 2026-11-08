# Smart Filter stack and mask transfer

Drag **Smart Filters** to another Smart Object to move its complete stack. Hold Option at drop to copy. Drag the filter-mask thumbnail to transfer only the shared mask. One Undo restores both layers. Existing individual-filter copy and within-stack reorder remain available.

The complete program appends in bottom-to-top application order. Existing destination enable state and shared mask are retained. A new destination stack inherits source enable state, mask and document-space mask properties. Copies receive fresh filter IDs; moved collisions are remapped. Moving a stack clears it from the source. Moving a mask removes only the source mask, retaining its filter program. Original source bytes, pixels, transforms, layer masks/styles and unrelated document state are preserved.

The path uses the existing filter renderer and primitive applicability checks on a private candidate. Source, target, limits and render validation complete before one prepared publication. Cancellation, stale state, revoked API sharing/token, invalid private drag payloads and unsupported targets cannot publish half a move. A copied selected filter mask stays selected; a moved-away one is reconciled through the same native/API target handling, including layers that also have ordinary masks.

## API and Actions

`smartFilter.transfer` takes UUID `sourceLayerID`, UUID `targetLayerID`, `part` (`stack` or `mask`) and a required boolean `copy`, with the normal shared-document revision. The result uses the existing document/layer/Smart Filter state schemas. Transfers are within one shared RGB document. Move requires unlocked source and target; copy can read a locked source. Mask transfer requires an existing destination filter stack. Existing source, program, renderer and 32-filter limits apply. Cross-document, unsupported contexts and complete Photoshop parity remain open.

Native/API use the same Core operation, prepared history and auxiliary-target safeguards. Semantic Actions version 58 replays source/destination by portable layer names/occurrences. Older feature minima and native format 89 remain unchanged. There are 264 typed commands. No dedicated transfer endpoint exists in the pinned Firefly v2 contract; no Adobe descriptor runtime or plugin host is claimed.

## Qualification

All 15 new transfer methods pass. The Debug aggregate accounts for 56 methods: 55 pass and one older published API method exits by signal 10, reproduced on retained 463. The same old method's normal outcome is recorded independently; no Debug repair cause is claimed.

The optimized batch passes all 87 enumerated methods on ARM and translated Intel, including 49 new methods from checkpoints 462–464. Release01's earlier 85-method run failed two saved-style API methods on each architecture; its sources, products and diagnostics remain retained. The final source/result binding is in the detailed evidence. Own transfer output captures compare 1,152 bytes / 288 Float32 words across three fixture depths, and match exactly. This is an own-engine comparison, not a new Photoshop output oracle. The seven old independent RGB32 methods and nine cursor methods protect their own qualified cases.

The isolated universal package passes minimum macOS 14, full production entitlements, signature and extracted-ZIP checks. It is unlaunched/uninstalled. Exact Photoshop merge/mask/placement/default behavior, physical gestures/platforms, unsupported workflows, full L06, capacity/performance and all earlier failures remain open. [Detailed evidence](SMART_FILTER_TRANSFER_464.json).

## Installed Photoshop observations

An owned synthetic 64 × 48 RGB8 document was opened in Photoshop 2026, converted to a Smart Object, duplicated and given a Gaussian Blur Smart Filter at the displayed radius of 1.0. The screenshot shows the upper filtered Smart Object, its white filter mask and the lower unfiltered object. The fixture was saved and closed. Coordinate dragging failed with Computer Use error `-10005: noWindowsAvailable`, so transfer ordering, mask inheritance, copy modifiers and output equivalence remain unqualified. See the [probe record](../artifacts/runs/20261107T052411Z-464-smart-filter-transfer/native-probe01.json).

Signing changes only the verified `LC_SEGMENT_64.__LINKEDIT.vmsize` allocation field in each packaged slice. All other unsigned bytes match the corresponding tested binary. This exception is recorded separately from the exact raw image-buffer comparisons.
