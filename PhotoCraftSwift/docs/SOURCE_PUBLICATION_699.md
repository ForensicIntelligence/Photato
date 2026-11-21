# Source checkpoint 699

Native Swift 0.3.0, build 699, 2026-11-21.

Generative Fill now uses an optional Apple Silicon Core ML model to fill a selection from surrounding pixels. Photato places the result above the visible stack on a raster layer with an editable mask and one Undo step.

The pinned LaMa512 model ran in Debug and optimized Apple Silicon builds. The native transaction and authenticated loopback API returned identical composite samples on the same RGB8 fixture. Tests at RGB8, RGB16 and RGB32 matched protected pixels and every output-mask sample. The owned example retained the editable mask on native, PSD and PSB reopening in Photato.

476 of 477 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with identical assertions in build 698. Both signed preview slices opened offscreen.

The local provider fills from context. Text prompts, variant sets and Adobe Execute Actions support remain open. The installed Photoshop session timed out, so Adobe output and physical workflow comparison remain pending.

[Development record](GENERATIVE_FILL_699.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_699.json)
