# Source checkpoint 807

The Camera Raw filmstrip can rate, label, sort and filter its photos. Number keys assign stars and color labels. A rating or label can use the existing XMP sidecar or an embedded DNG packet. Rating-only saves preserve Camera Raw adjustments.

Adobe Camera Raw 18.1.1 stored four stars and Red on both selected DNGs. Photato’s native window displayed those marks and filtered out the unmarked photo. A separate embedded DNG round trip wrote the same XMP values and preserved the sensor payload and every developed Photato sample.

The tested XMP values agree with the live Adobe reference. [Adobe Camera Raw keyboard shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Authenticated `raw.markPhoto` edits a single-original shared document’s XMP rating or label through native Undo. `raw.inspect` reports it, and `raw.saveSourceSettings` accepts `photoMarkingOnly` for an authorized metadata-only write.

Xcode built the app. All sixteen focused application tests passed. The new cases cover filtering, Undo and Redo, clearing an inherited label, retaining unrelated metadata, and the authenticated source-settings save. Both optimized architectures passed all 393 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The native test checked reopening and filtering. The embedded save was verified separately through the native RAW engine. Grid, Stacks and the full Adobe renderer and export-byte comparison remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,484,079 bytes with SHA-256 `cce5a596a62d3bc3042d717d3d507dcc6fec32a6ae6fcb447941fb12ae61463d`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_807.json) · [Development record](DEVLOG.md#dev-step-807).
