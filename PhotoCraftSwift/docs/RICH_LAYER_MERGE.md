# Rich layer merging

Layer > Merge Down (Command-E), Merge Layers (Command-E) and Merge Visible (Shift-Command-E) now prepare supported static RGB artwork through the shared native compositor. The Layers context menu and optional APIs use the same engine, one Undo, cancellation and source/revision/revocation guards. No new tool or modifier action is introduced; the factory menu/cursor policy remains in place.

The merged content can contain type, shapes, fill/adjustment layers, pixel/vector masks, affine geometry, layer effects, resolved Smart artwork, groups and complete clipping bases. The result is a pixel layer; merged editable sources are recoverable with Undo. Untouched layers and document-owned selections/channels/guides/paths/profiles/comps remain in the document. A selected group's descendants are consumed once. Same-parent child selections retain their parent; selected groups rasterize as a whole. Merge Down requires an adjacent visible pixel layer below the source. Unavailable contexts fail before commit.

Merge Visible renders the selected visible root subtrees within the canvas and preserves hidden root layers. Hidden descendants inside a visible merged group currently reject, avoiding unqualified data-loss/retention behavior. A merged Background remains an opaque, canvas-aligned Background. Other output keeps transparency, including a valid empty result. Selected/down can retain off-canvas geometry using a translated temporary viewport. Effects use conservative padding; exact Photoshop effect extents and external-backdrop interactions remain unqualified. Existing renderer feature/memory/disk limits still apply.

The previously measured plain pixel arithmetic remains the fast path. Larger supported RGB output uses sparse/paged preparation rather than imposing a 4 MP API limit. The maximum logical sparse case is tested; this is not dense maximum-size or responsiveness qualification. Non-RGB numerical planes are never silently converted through display RGB.

## Automation

Photato `layer.merge` retains its command identity. Parameters: `operation` is `down`, `selected` or `visible`; `layerIDs` is a unique UUID array, one for down, at least two (or one group) for selected, empty for visible. The response uses the shared document state, now including `layerMerge` availability and selected IDs. Root state/capability/schema metadata describes supported contexts and open gaps. Invalid values/missing IDs, busy/stale/cancelled/revoked requests use the existing API error policy and never partially replace the source.

Semantic Actions retains the existing portable merge operation and its original format minimum; playback re-renders against the destination document.The API retains 239 typed commands, with native file format 84 and Actions format 44. Existing Adobe `mergeLayersNew`/`Mrg2` and `mergeVisible`/`MrgV` actionJSON events on `/v1/action-jobs` and published `/v2/execute-actions` use the same prepared renderer on isolated documents. No endpoint was invented and complete Firefly service/format/schema/proprietary equivalence is not claimed.

## Qualification

All 18 new cases pass. Of 298 affected optimized cases, 297 pass and 1 fail; 2 failed assertions, 0 unexpected errors and 0 crashes. Independent readers verify 288 RGBA bytes and 672 raw merged PSD/PSB component bytes across three PNGs and six Photoshop files.

Complete L02 merge/rasterization, numerical/palette/ink/temporal composition, cross-parent selections, clipped artwork without its selected base, hidden descendants inside visible merged groups, stamp/merge-clipping variants and exact Photoshop backdrop/effects/geometry/defaults/live UI remain open. Supported-platform, full-current-suite, dense maximum capacity and physical60fps qualification remain open. All 104 work packages remain open against their full acceptance criteria.

A single selected group uses Merge Group from the default menu/context action and the Adobe default merge event, preserving its lower sibling. Explicit Photato operation=down continues to mean Merge Down. Inactive-window pointer observations now clear stale hover modifiers; existing captured gestures and remote editing parameters are unchanged. The regression explicitly seeds Option before inactivating its test window.

Native round trips, analytical expected pixels and independent exported-image decoding provide separate evidence. Existing Photoshop-saved plain merge references remain in the affected test selection. No new live Photoshop output was captured: its AX tree is readable, while prior input attempts timed out. No installed app, source backup, App Store archive, binary upload or software release is changed by this increment. Private backup 363, installed preview 283 and store archive 332 remain as recorded.

[Adobe desktop layers help](https://helpx.adobe.com/my_ms/photoshop/using/layers.html) · [Adobe UXP Layer](https://developer.adobe.com/photoshop/uxp/ps_reference/classes/layer/) · [Evidence](RICH_LAYER_MERGE_REFERENCES.json)
