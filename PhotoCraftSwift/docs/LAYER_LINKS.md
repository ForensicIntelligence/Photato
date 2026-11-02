# Layer links and whole-layer Move

Photoshop 2026 is the reference. This increment implements a functional subset of persistent layer links and whole-layer movement. It does not close the Photoshop layer or transform workflow.

Select at least two regular layers or groups and choose Layer > Link Layers, the panel context command, or the chain button at the bottom of Layers. Linking combines the selected layers' existing relationships. A chain appears beside each linked row. Click its chain to unlink that member; Shift-click to temporarily disable or restore its participation. Select Linked Layers includes temporarily disabled partners and changes only the view selection. A remaining singleton relationship is removed after an edit. Background must be converted before linking.

Move/V, arrow nudges, whole-layer Free Transform and explicit Move automation resolve enabled partners and group descendants transitively, moving each layer once. A position lock on any effective target rejects the whole operation. Disabled members do not join a move begun on their partners. A selected disabled member still moves itself and its own descendants. The exact interaction between links, groups and every Photoshop context remains unqualified.

Without a pixel selection, native Move shows a bounded, coalesced preview and commits one undoable transaction on pointer release. Option at pointer-down copies the effective targets; subsequent Option changes do not change that captured action. Shift changes the angle constraint during dragging, Command suppresses guide snapping, and the effective cursor follows those settings. Arrows nudge one pixel; Shift-arrows nudge ten. Pixel selections, masks and channels use their separate existing workflows. Translation preserves raster sample storage and retained Smart Object data. Unlinked pixel masks remain fixed in document space. Copies retain hierarchy and editable data and receive independent link groups only among copied peers; originals do not join the copied relationship.

The previous no-selection canvas path could mistake the default full selection coverage for a real pixel selection and reject a Move. The path now requires an actual selection before entering selected-pixel Move.

## Native automation

The optional Photato API adds `layer.links` and `layers.move`, using the same engine and history transactions. The catalogue contains 233 commands. State and capabilities include `layerLinks`, graph membership, disabled members, raw view selection, effective Move targets, availability, and parameter/result schemas.

`layer.links` accepts `layerIDs` and `operation`: `link`, `unlink`, `enable`, `disable`, or `select`. `select` is a view operation and does not create document history. `layers.move` accepts `layerIDs`, integer `dx`/`dy`, and optional `copy`. Each request uses 1–64 unique existing layer UUIDs, normal shared-document revision/authentication, and existing resource budgets. Move results include `createdLayerIDs`, `movedLayerIDs`, the current revision and document state. Invalid, busy, stale, revoked and cancelled edits publish no partial document.

The pinned Adobe v2 contract supplies no independently qualified persistent-link route/descriptor. None is invented. Existing resource jobs carry supported PSD/PSB metadata through the common serializer; their full contract and per-layer positioning semantics remain separately tracked.

## Files and portable Actions

Native linked fields require version84, including links in retained Timeline sources. Older unlinked documents keep their prior feature minimum, and older readers remain supported. Portable Actions require39 for link edits or40 for whole-layer Move/copy; advertised read support is1–40. Earlier affine37/projective38 operations retain their minima.

PSD and PSB use Adobe image resources1026 (two-byte group IDs) and1072 (one-byte enabled flags), indexed by physical layer records including group markers. Matching existing IDs, resource names, padding and record order are preserved. Edited arrays are regenerated. Nonzero divider link IDs are explicitly unsupported pending qualification. Flat serializers omit stale layer-index resources. Data and atomic file exports share one serializer. These owned-file checks do not prove complete Photoshop interchange.

## Verification and remaining work

All 22 new cases pass: 9 model, 5 imaging and 8 application cases. Of 1128 affected optimized cases, 1125 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. Independent readers verify 10240 RGBA channels across eight owned Move/copy outputs and link records in six PSD/PSB files. Sparse 300,000 × 300,000 Move/copy storage is tested. Exact Photoshop behavior/output, live UI, the full current suite, supported platforms, dense maximum capacity and physical 60fps remain unqualified.

Native tests use offscreen AppKit input and previews, not a physical Photoshop session. The last actual Photoshop access at349 encountered the locked Mac; no new live access is claimed. Installed preview283, private source backup298 and store archive332 remain unchanged. No installation, push, archive, upload, review or release is performed in355.

Still open: Transform Again and repeated-copy transforms; exact Photoshop link/group/copy semantics, pivots/defaults/menu validation/layout/artwork; temporal link editing and whole-layer Move in unsupported target/mode contexts; all selection/component/fill/artboard/link/merge/reorder combinations; nonzero PSD divider classes and full format coverage; linked animation state editing; all current-suite failures and supported-platform runs; dense maximum capacity and physical60fps. Sparse300000×300000 translation/copy is a functional storage check, not dense-memory acceptance. No full package or parity percentage is inferred from this increment.

Source-inspection follow-up: a retained singleton link label combined with another unlinked view-selection seed can leave Select Linked Layers enabled because the availability check counts raw seed IDs. No peer or pixel data is added by that no-op view action. Explicit regression and availability refinement remain deferred with the other incomplete link contexts; full L01 is open.
