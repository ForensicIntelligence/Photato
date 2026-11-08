# Magic Wand sampling

Choose Magic Wand (W; Shift-W cycles the selection group). Sample Size offers Point Sample and 3 by 3, 5 by 5, 11 by 11, 31 by 31, 51 by 51 and 101 by 101 Average. The sampling square is centered on the clicked pixel and clipped to the document. Tolerance, Anti-alias, Contiguous, Sample All Layers and selection modifiers retain their existing roles.

Options are captured at the click. A change to the tool's next sample does not change an operation already preparing. Sampling reads the current layer, visible composite or selected ordinary layer mask, including transformed sources and locked layers. Source pixels stay intact. The resulting selection has one Undo/Redo operation and saves with the document.

## Optional API

`selection.wand` requires `operation`. Use `configure` with a nonempty patch of `sampleSize`, `tolerance`, `contiguous`, `antiAlias`, `sampleAllLayers` and `mode`. These are window-local settings; configure does not edit document history. Use `select` with document `x` and `y`, optional setting overrides, optional `layerID` and `target` (`content` or `layerMask`). Omitted settings use the captured window values; overrides do not change them. The result supplies `revision` and `magicWand` state; fetch the shared document state for selection geometry/coverage and preview.

Sizes are 1, 3, 5, 11, 31, 51 and 101. Tolerance is an integer from 0 to 255. Selection modes are `replace`, `add`, `subtract` and `intersect`. Invalid settings, stale/busy requests, cancellation or revoked sharing cannot publish a partial selection. Capability discovery supplies parameter, result, settings and state schemas. There is no dedicated route in the pinned Adobe v2 contract, and no semantic actionJSON compatibility is claimed.

## Qualification and remaining work

The installed Photoshop 2026 popup confirms all seven choices; a change to 3 by 3 and restoration of Point Sample were observed. No canvas or numerical equivalence is inferred from that menu test. Photato averages the existing quantized RGBA8 matching samples, including hidden RGB/alpha, with checked integer sums and nearest rounding. A contiguous seed that fails the average-color tolerance yields an empty region. These details need independent Photoshop comparisons.

All 11 new tests and all 57 selected Debug methods pass, including native/API equivalence across seven sizes, three depths and ordinary masks, captured settings, history/archive, request guards and all 16 modifier combinations. A separate literal arithmetic reference agrees with every one of 74,263 captured mask bytes. The old 240-case point-sample regression still matches all 66,096 bytes; that licensed Rust regression is not a Photoshop oracle. Seven older independent Photoshop RGB32 cases and nine cursor methods pass within their existing scope.

Normal optimized qualification is deferred to the next stable batch; latest selected optimized universal is 464. Full S02, the full native gesture matrix and physical-platform checks, exact Photoshop defaults/output, dense/maximum capacity, restart settings persistence, semantic Actions and unsupported target contexts remain open. [Detailed evidence](MAGIC_WAND_SAMPLING_465.json).
