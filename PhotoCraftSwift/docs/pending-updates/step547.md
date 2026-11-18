<a id="dev-step-547"></a>

## 2026-11-18 — Retain coverage for wide raster brushes

The 5,000 px first preview in build 546 took most of its time preparing the stroke. Wide strokes also ran the complete banded painter again for every input batch, even if the new samples generated no dab.

BrushPainter.swift retains coverage for eligible raster strokes up to 5,000 px and uses the same transformed selection bounds as complete painting. BrushDynamics.swift checks all first-dab input bits before promoting provisional coverage into the settled stroke. Empty batches keep the existing pixels. DocumentBrushStrokeSession.swift switches to the complete banded painter on the retained coverage budget and replays every original input sample. InteractiveBrushPreview.swift admits the same desktop route. AutomationBrushes.swift describes the behavior of native previews and complete paint.stroke requests.

RetainedBrushCommitTests.swift compares held prefixes, release, Actions, memory fallback and Undo with the complete painter. CanvasFrameDiagnosticsTests.swift exercises wide ordinary and wide dual-tip painting through their normal paths.

All 60 raw outputs agree with build 546's complete painter on both optimized architectures. All 395 selected methods passed in Debug and both optimized builds. Both packaged binaries passed the offscreen workspace check.

At 5,000 px on Apple Silicon, nine held prefixes took 4749 ms with complete preparation and 1872 ms with retained coverage. Paired AppKit first draw measured 621 ms in build 546 and 654 ms in build 547. The recorded changed-input draw counts exclude redraws of the same accepted raster. Physical display and tablet input remain open. [Qualification](SOURCE_PUBLICATION_547.md).
