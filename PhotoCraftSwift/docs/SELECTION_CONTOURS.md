# Selection contour preparation

Build 525 bounds the dense half-coverage contour scan to the selection's stored nonzero bounds. It retains the original horizontal/vertical run order, including holes, canvas-edge pixels and partial coverage at the 0.5 threshold. Sparse selections keep the existing view-bounded sampling policy.

Each editor store retains one contour in an off-main actor, keyed by immutable mask coverage, viewport region and sample step. Equal newly allocated masks can reuse the same contour. Main-thread admission uses coverage-storage identity rather than reading a large coverage plane. Cancelled or failed builds cannot publish a partial contour or replace a valid cache entry.

Ordinary pixel, layer-mask and Adjustment Brush previews keep an already displayed matching contour while the next image is prepared. A changed selection/view clears it immediately. Selection-altering brush commands are keyed from their final worker document, after their coverage command has been applied. Pixels, selection coverage, Undo, Actions and archive formats are unchanged.

The Photato API advertises this under selectionDisplay.contourPreparation. Existing commands and state schemas remain compatible. This adds no remote input or Adobe endpoint.

Eight new tests compare complete contour paths against the frozen native build-524 traversal recompiled in the same test binary, plus an independently specified rectangle, mixed threshold coverage, holes, maximum paged geometry, cache invalidation/cancellation, native painting/history and read-only API behavior. This reference does not replay the old application or compare Photoshop output.

In Debug, a 64×48 selection on owned 6000×4000/6000×6000 canvases takes about 1.1ms to prepare, versus 7.8/11.8s for that recompiled full-canvas traversal. The 120 unchanged requests use one retained contour. These are small-selection contour CPU costs, not whole-stroke latency or physical FPS. Large complex dense contours, physical display timing, remaining main-thread work, low-memory behavior and full Q03 qualification remain open.

[Marquee/border behavior](SELECTION_INTERACTION.md) · [525 diary](pending-updates/step525.md)

Combined build526 qualification passes all 86 selected and 15 new methods in Debug and both optimized architectures. The small-selection contour takes about 0.041ms ARM / 0.061ms translated Intel; unchanged requests reuse the same path. Native launch/title is checked, but editing/save/reopen is unqualified after file-chooser automation stalled. [Qualification](SOURCE_PUBLICATION_526.md).
