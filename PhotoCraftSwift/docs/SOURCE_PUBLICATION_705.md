# Source checkpoint 705

Native Swift 0.3.0, build 705, 2026-11-21.

Generative Expand is available in Crop after dragging the handles outward. Use a blank prompt or describe the new area. Photato adds an editable masked layer and commits the canvas and generation in one Undo step. Prompted results can be switched in Properties. The Photato API uses the same editing path.

On the owned apple image, each local model preserved all 65,536 original pixels and added 25,632 opaque pixels. The largest mean RGB8 step immediately outside the old canvas dropped from 88.29 levels with LaMa512 and 54.54 with prompted generation to 0.00. Photato reopened the editable PSD and PSB results with identical RGBA bytes. The native editor and local HTTP route produced identical bytes at the same seed. Both models also passed the file and Undo checks in an ad hoc signed App Sandbox test harness.

494 of 495 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The existing PhotoCraft layer-effect test repeated its 118 assertions from build 704 in each configuration. The Xcode app built in arm64 Debug. Both slices of the signed preview opened offscreen.

This generation pass requires the new border’s bounding rectangle to fit within 4,194,304 pixels and 4,096 pixels per side. Local models can leave artifacts near the outer edge of the addition. Larger multi-edge generation, rotation, inward cropping during expansion, multiple blank-prompt results and Firefly equivalence remain open.

[Model setup](LOCAL_GENERATIVE_FILL.md#extend-the-canvas) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_705.json)
