# Source checkpoint 703

Native Swift 0.3.0, build 703, 2026-11-21.

Generate More adds another batch to the selected Generative Fill layer. Edit the prompt in Properties or send the layer ID through the Photato API. New results use the original selection and image samples after reopening. Earlier results and the current layer mask stay editable. One Undo removes the batch.

The reopened-layer tests preserve the earlier result bytes, original inference inputs, current mask, placement and selection across Photato, PSD and PSB at RGB8, RGB16 and RGB32. The sandboxed Core ML probe generated four distinct results. Both original results matched the build 702 fixture at the same seeds. Each result preserved all 49,283 pixels outside the original selection and reopened byte for byte in all three formats in Photato. The editor and HTTP also produced identical RGBA output when adding to a reopened PSD at the tested seed. The Generate More sheet and expanded variation picker were captured offscreen. The picker was inspected in Light and Dark.

483 of 484 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 702 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug.

A layer holds up to 64 variations within the Smart Object storage limits. Layers saved by build 702 retain variation selection and lack the captured context needed for new batches. The installed Photoshop session timed out on a read-only query. Generate Similar, the Adobe Execute Actions descriptor, and Firefly output equivalence remain open.

[Model setup](LOCAL_GENERATIVE_FILL.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_703.json)
