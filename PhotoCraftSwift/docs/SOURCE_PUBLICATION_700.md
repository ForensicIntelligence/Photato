# Source checkpoint 700

Native Swift 0.3.0, build 700, 2026-11-21.

Generative Fill accepts a text prompt and selection mask in Photato’s native editing sheet and HTTP API. An optional Core ML model generates the content locally. The existing blank-prompt mode uses LaMa512.

Using the same source, selection and seed, a red-apple prompt and a blue-mug prompt produced distinct subjects. The native and authenticated HTTP paths matched RGB8 output bytes for the same prompt and seed. Both prompts preserved all 49,283 protected pixels. The editable mask retained feathering and a protected hole, and one Undo restored the original document. Both edits reopened in Photato with exact RGB8 composites and mask coverage in native, PSD and PSB files.

477 of 478 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 699’s assertions. Both signed preview slices opened offscreen. The checked-in Xcode project built in arm64 Debug, and the sheet was inspected offscreen in Light and Dark.

Hard selection edges can show a tonal seam. Editable variation sets, Adobe Execute Actions descriptor compatibility and Firefly output equivalence remain open. The installed Photoshop session timed out on both scripting queries.

[Model setup](LOCAL_GENERATIVE_FILL.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_700.json)
