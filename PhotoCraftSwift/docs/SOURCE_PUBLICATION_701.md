# Source checkpoint 701

Native Swift 0.3.0, build 701, 2026-11-21.

Generative Fill now uses opaque pixels around the selection to reduce color seams. The correction tapers into the selected area. The editor and Photato API preserve the editable mask and one-step Undo.

Mean RGB8 drift across 505 boundary samples fell from 4.39 to 0.31 levels on the apple and from 3.95 to 0.24 on the mug. Each result preserved all 49,283 protected samples and all 9,898 tested interior samples. Both fills retained exact pixels and editable masks when reopened in Photato as native, PSD and PSB files. A synthetic fill exercised a 4,194,304-pixel selection on a 300,000 × 300,000 sparse canvas.

480 of 481 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 700’s assertions. Both signed preview slices opened offscreen, and the checked-in Xcode project built in arm64 Debug.

A separate trial generated three alternatives for the same prompt and selection using distinct seeds, then used a PSD-backed Smart Object with Layer Comps. All three reopened and switched in Photato with exact RGB8 composites and the original mask in native, PSD and PSB files.

Application-managed variation sets and the Adobe Execute Actions descriptor remain open. A separate seed probe hit a Core ML GPU exception once and succeeded on retry. The installed Photoshop session timed out on a read-only scripting query, so Photoshop output equivalence has yet to be verified.

[Model setup](LOCAL_GENERATIVE_FILL.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_701.json)
