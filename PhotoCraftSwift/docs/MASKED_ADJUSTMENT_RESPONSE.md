# Masked adjustment preview performance

Build522 avoids evaluating hidden pointwise pixels and bounds the damage from a newly painted plain top adjustment. It retains the current complete-render math, validation and transaction/history behavior. Nonlocal effects and unproven structures keep full rendering.

In the owned3072-square paced model workload, new adjustment previews improve from 1.185 to 27.646 accepted previews/s (26.622 in the repeat). This is about 23× the baseline processing rate. Median input-to-ready improves477.1→35.7ms; maximum1802.5→97.6ms in that run. These are CPU processing measurements, not physical displayFPS. Raster is about 60/s; masks/existing adjustments remain near 27/s. The60fps goal stays open.

All 30 selected methods pass on optimized Apple Silicon and translated Intel. Five are new in522; three unpublished521 methods are also included. Seventeen Adjustment Brush types, three component depths and four blend modes match complete-render Float32 words. Tests cover masks, groups/clipping, invalid input, signed zeros, locality fallbacks and the existing Sky/API/menu/modifier paths. Original test failures and the corrected obsolete public-compositor rejection assertion remain documented.

The signed optimized universal app completes native paint, Undo/Redo, editable adjustment, continued paint, separate save/reopen and normal Quit. The original PNG remains unchanged. Static minimum14/signing/payload/model/license/archive checks pass. Physical supported-platform qualification and full regression remain open.

API impact: existing desktop and API calls share Renderer. Their commands, schemas, parameters, availability, revision, history and persistence semantics are unchanged. The Sky containment candidate changes presentation only; its read-only viewport state retains the existing schema. No Adobe endpoint is invented. Exact Photoshop output/default/shortcut equivalence and full Q03 are not implied.

Sky scrolling still needs live verification: hosted pixel/geometry tests pass but native inspection disconnects on the sheet. The screenshot was not reproduced by the isolated hosted baseline. Earlier viewport claims must be read at their recorded automated scope.

[Evidence](MASKED_ADJUSTMENT_RESPONSE_522.json) · [Qualification](SOURCE_PUBLICATION_522.md)
