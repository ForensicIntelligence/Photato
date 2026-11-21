# Source checkpoint 704

Native Swift 0.3.0, build 704, 2026-11-21.

Generate Similar uses a chosen variation as the reference for another batch in the same local Generative Fill layer. Open Variation actions in Properties or pass the reference ID through the Photato API. The earlier results, mask and reference stay editable after reopening, and one Undo removes the new batch.

On one owned example, the mean RGB8 difference from the reference fell from 52.91 levels with full regeneration to 10.32 with conditioning at the same seed. Changing the reference changed the generated output by 46.57 levels on average. The sandboxed comparison preserved 49,283 pixels outside the original mask and the four earlier variation records. The generated result and reference ID survived reopening in Photato, PSD and PSB. The native editor and HTTP produced identical RGBA output when they used the same reference and seed on a reopened PSD. The reference sheet was captured offscreen. Variation actions were inspected in Light and Dark.

484 of 485 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The existing PhotoCraft layer-effect fixture repeated its 118 assertions from build 703 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug.

Generate Similar in this build supports Photato’s local prompted Generative Fill layers with saved context. Adobe also documents it for Expand, Background and Generate Image. Adobe Execute Actions compatibility and Firefly output equivalence remain open. The installed Photoshop session timed out on a read-only scripting query.

[Model setup](LOCAL_GENERATIVE_FILL.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_704.json)
