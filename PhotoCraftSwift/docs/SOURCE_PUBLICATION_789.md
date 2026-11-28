# Source checkpoint 789

Camera Raw’s Done button now writes or updates the companion XMP for supported non-DNG originals. Photato keeps the camera file unchanged and retains unrelated XMP metadata. Nikon files with a verified sensor directory decode at full size from both Finder and retained bytes.

Adobe Camera Raw 18.1.1 created a sidecar for the CC0 Nikon D70s reference at Exposure +1.25. Photato read the Nikon at 3,008 × 2,000 pixels, created its own sibling and updated an existing Adobe-authored XMP. Adobe reopened the updated sidecar at Exposure +1.50. The original NEF’s SHA-256 stayed identical and all other top-level Adobe Camera Raw scalar settings stayed the same.

The authenticated `raw.saveSourceSettings` command now selects the XMP destination automatically for the original layer of a locally opened non-DNG RAW. It shares the native coordinated writer and requires local document saving and the current revision. The editor history and original source bytes remain intact.

Xcode built the app. Four focused imaging tests and one authenticated HTTP test passed. Both optimized architectures passed all 345 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Camera Raw database and storage preferences, camera-specific defaults, RAW variants unsupported by Apple’s decoder, physical Intel testing and byte-for-byte Adobe render equivalence remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,475,580 bytes with SHA-256 `5dfcc4db75dbf1f38d897aad988f8b49d4c5aca0831a8cc73ab51cf75c4cda81`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_789.json) · [Development record](DEVLOG.md#dev-step-789).
