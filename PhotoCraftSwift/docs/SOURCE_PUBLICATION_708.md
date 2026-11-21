# Source checkpoint 708

Native Swift 0.3.0, build 708, 2026-11-21.

Generate More and Generate Similar now work on prompted Generative Expand layers that used overlapping model windows. The embedded PSB stores the original perimeter pixels, including when the edit starts with one result. Changing the underlying layers after saving leaves the model context intact. The edit keeps the earlier results and the current outer mask.

A 4,104-pixel-wide fixture matched every original Float32 model input after reopening in native, PSD and PSB, even after edits to the base pixels and mask. The real Runway model reproduced the first build 707 result byte for byte on a 4,104 × 120 image, then generated a new result from that saved reference. The proof kept both results, 393,984 original pixels, the edited mask and one-step Undo. The two results reopened byte for byte in PSB and Photato. The native Properties draft accepted the saved reference. The prepared edit and HTTP produced the same RGBA8 results and mask after reopening. A signed App Sandbox proof retained all 11 model inputs and 73,836 original pixels in PSB at each of RGB8, RGB16 and RGB32. The first result took 312.2 seconds and the similar variation took 164.8 seconds while build qualification ran.

498 of 499 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 707. Xcode built the app in arm64 Debug. Both signed preview slices opened offscreen.

Older tiled files still open and retain the saved results. They lack the captured source needed to regenerate. Large dense borders, long-range prompt continuity, rotation, blank-prompt alternatives and Adobe Firefly output equivalence remain open.

[Model setup](LOCAL_GENERATIVE_FILL.md#extend-the-canvas) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_708.json)
