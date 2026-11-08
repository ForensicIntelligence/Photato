# Color Lookup property responsiveness

Color Lookup layer Properties now prepares replacement content away from the main thread. This uses the existing prepared-edit worker, source-session checks and history publication. Numeric/name edits finish at the same boundary, and an unfinished Free Transform retains its previous error.

The Properties controls disable competing edits during preparation and show progress with Cancel. The existing canvas Escape handler can cancel geometry work. Cancellation before publication, closing the document or replacing its session discards the result. Publication and Undo history remain on the main actor; history spilling and rendering still need separate performance qualification.

A sampled optimized run also found repeated sorting of unchanged raster tile keys in document comparisons during publication and UI observation. Surface equality now accepts a positive shared-storage identity proof after checking dimensions, depth, encoding and default sample bits. Direct maps require matching keys, counts and tile-buffer identities; persistent maps require the same immutable base and root. Other representations still use the original logical pixel-bit comparison. This preserves signed zero, hidden colour and implicit/mapped/owned equivalence. The change also benefits other document comparisons; broader painting/display performance remains unqualified.

The LUT, interpolation, Dither, layer mask, mask properties, other layers and document pixels retain their existing representation and kernels. One changed property edit creates one Undo entry. An unchanged edit creates none. Recorded replacement actions retain their embedded table and existing version requirement. No new command, archive format, Actions version, menu item, shortcut or tool modifier was introduced.

## API

Existing `adjustment.set` and `adjustmentBrush.edit` replacement operations retain their request/response, revision, busy, source and history contracts. They already use prepared transactions. Discovery now describes the native property preparation under `colorLookup.propertyPreparation`; existing document busy/status/error state continues to apply. The Adobe interface keeps its existing Color Lookup action subset; no new endpoint or descriptor is claimed.

## Validation

The eight new transaction tests and four new storage-identity tests compare native edits with the previous synchronous expression and HTTP output at all supported pixel depths. They retain exact document, native archive and rendered results, masks, Undo/Redo, dirty notifications and action recording. Additional cases cover cancellation, stale sessions/lifecycle, busy/no-op edits, locks, invalid tables, wrong layers, modal/transform/component targets and strict HTTP errors. Two existing tests await the asynchronous setter before their original assertions; their numerical expectations are unchanged.

The opt-in benchmark measures 20 fresh-session edits per case on owned dense RGB8 gradients: 24 MP and 36 MP single-image-layer documents, plus 32 image layers at 1024 × 1024. The layers in the last case share an immutable pixel buffer; only the base layer is visible. Each geometry is measured with generated 33- and 129-edge lookup tables. Fixture construction is outside timing. Initial/final rendering is cancelled and excluded. Submission, completion and a 2 ms main-actor timer are reported separately.

The first two benchmark attempts exceeded the current 1 GiB counted raster budget in their multi-layer fixtures. Their failed sources, logs, raw reports and products remain preserved. Those rejection timings are not editing results. The corrected fixture validates before measurement. The first implementation shortened submission but left timer gaps unchanged, so its results were retained and rejected as sufficient responsiveness evidence. A sampled run then identified shared-tile equality as an additional bottleneck. This does not remove the document capacity limitation.

The benchmark is an in-process observation on a shared host, not physical input/display latency or proof of 60 fps. Exact Photoshop defaults/output, all-tool responsiveness, rendering, sustained painting, scratch/history behavior, physical Intel/macOS 14 and the full Q03 acceptance remain open. See [checkpoint evidence](LOOKUP_PROPERTY_RESPONSIVENESS_479.json) and [development record](DEVLOG.md#dev-step-479).

## Optimized observations

Twenty edits per row, p95 in milliseconds. Timer gaps include the 2 ms timer interval and scheduling overhead. These are observations on this host, not CI thresholds or display-rate measurements.

| Document / LUT edge | Submit before → after | Complete before → after | Main-actor timer before → after |
|---|---:|---:|---:|
| 6000 × 4000, 1 image layer(s), 33³ LUT | 7.00 → 0.08 | 7.00 → 1.93 | 6.96 → 3.09 |
| 6000 × 4000, 1 image layer(s), 129³ LUT | 9.28 → 0.03 | 9.28 → 4.08 | 9.23 → 4.05 |
| 6000 × 6000, 1 image layer(s), 33³ LUT | 9.69 → 0.03 | 9.69 → 2.49 | 9.67 → 3.07 |
| 6000 × 6000, 1 image layer(s), 129³ LUT | 11.72 → 0.03 | 11.72 → 4.78 | 11.72 → 4.71 |
| 1024 × 1024, 32 image layer(s), 33³ LUT | 5.54 → 0.04 | 5.54 → 1.47 | 5.51 → 3.09 |
| 1024 × 1024, 32 image layer(s), 129³ LUT | 7.74 → 0.04 | 7.74 → 3.80 | 7.76 → 3.67 |
