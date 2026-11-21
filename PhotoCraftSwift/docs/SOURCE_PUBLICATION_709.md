# Source checkpoint 709

Native Swift 0.3.0, build 709, 2026-11-21.

Generate Background now offers a local model after Remove Background. Photato places the result on an editable Smart Object below the masked subject. The document retains the original subject context for Generate More and Generate Similar after reopening. The Image Playground workflow is available through its Apple Intelligence action.

The Vision and Runway test on project artwork preserved 422,792 fully opaque subject pixels and filled 578,461 transparent pixels. Both results retained their stacks and rendered samples after a Photato and PSB reopen. A signed App Sandbox harness passed the same owned-artwork checks. The native action and Photato HTTP API matched byte for byte in a separate same-seed test. A 6,200-pixel-wide test preserved editable placement and opacity at the far corner. A 300,000 × 8 PSB retained the same outer-edge pixels and editable source when reopened. At actual size, the RGB8, RGB16 and linear RGB32 fixtures preserved their rendered bytes through native, PSD and PSB reopening.

503 of 504 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 708. All 19 existing Apple Intelligence background tests passed. Xcode built the app and both signed preview slices opened offscreen. The native setup sheet was checked in light and dark appearances.

The local model samples the document within a 512-pixel frame and scales the result to the canvas. Dense maximum-area export, lighting and texture quality, dedicated background colour and import choices, and Firefly output equivalence remain open.

[Model setup](LOCAL_GENERATIVE_FILL.md#generate-a-background) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_709.json)
