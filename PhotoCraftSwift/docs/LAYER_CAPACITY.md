# Layer capacity

The native document and optional Photato API accept up to 8,000 layers, including groups. This replaces the earlier 512-layer native and 64-layer shared-document limits. It is a tested development target. Current Adobe desktop documentation inspected for this change does not establish the exact Photoshop 2026 maximum; the Adobe Elements 8,000-layer statement is not proof of desktop Photoshop parity.

Native creation, duplication, grouping, Layer via Copy/Cut, clipboard insertion, generated layers, Layer Comps, layer export selections and supported movie placement use the common admission limit. Existing algorithm, object, source, frame, raster, temporary-storage and format budgets still apply. A layer count is not a guarantee that every dense stack fits memory or renders at 60fps.

Hierarchy validation, subtree discovery, selected group roots, bulk position locks, PSD serialization, native panel filtering and API protection state reuse immutable indexes within an operation. The indexes do not outlive the document snapshot. Layer order, parent relationships and inherited protection remain unchanged.

## Native files and Photoshop files

The native format remains version 84. No new fields or incompatible encoding were introduced. PSD/PSB import accepts up to 16,000 physical layer records because each group has a separate divider record; the resulting native graph still cannot exceed 8,000 layers. Source-format import uses the common layer limit while retaining separate manifest, node, surface and byte budgets.

## APIs

The Photato API advertises maxLayers=8000. General layer-ID schemas and parsers use the same bound, including protection, styles, Smart Object conversion, links, transforms and clipboard selections. API documents retain the 128MiB owned-heap budget. A new empty pixel layer is admitted using its prepared candidate and actual storage; logical canvas dimensions are not charged as a dense RGBA allocation. The transaction still checks revision, sharing, cancellation and current document state before committing one Undo entry.

Adobe resource jobs share the native document admission. Published create-composite output selection has its own maxItems=100 contract budget; it does not inherit Photato's 8,000 IDs. Existing unsupported empty-array/combined id-and-name/PSD multi-reference contexts remain documented compatibility gaps. No new Adobe route or unverified actionJSON descriptor is introduced. The movie-frames API keeps its explicit 64-frame import budget; other frame/key/source limits remain operation-specific.

235 typed Photato commands, native version 84 and Actions version 42 remain unchanged. Menus, shortcuts and tool cursor policies retain their current mappings. Full factory UI/default/output parity is still open.

## Verification

All 19 new capacity cases pass. Of 648 affected optimized cases, 640 pass; 8 retain 149 failed assertions. There are 1 unexpected errors and 0 crashes. Independent readers verify four owned PSD/PSB files: 32,000 layer names, 8,000 raster records or 16,000 group/divider records per file, and 128,000 raw channel bytes.

The exact Photoshop 2026 layer ceiling remains unverified. Dense stacks, sustained interaction speed, live UI, complete Photoshop output, supported Macs, the full current suite and physical 60fps are not qualified. All 104 complete package scopes remain open.

The tests cover creation/rejection and atomic history at 7,999/8,000/8,001, inherited locks and grouping, duplicate/paste/Move, native persistence at all pixel depths, native panel search/collapse, HTTP state/protection/native download, large UUID bodies, busy/stale/revoked requests, sparse 300,000×300,000 empty-layer creation, and the separate Adobe resource/output bounds. Tests use owned small artwork and offscreen native controls. They do not establish Photoshop-generated output equivalence or live screen performance.

[Reference evidence](LAYER_CAPACITY_REFERENCES.json) · [Development record](DEVLOG.md#dev-step-359)
