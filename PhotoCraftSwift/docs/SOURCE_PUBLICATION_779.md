# Source checkpoint 779

Use BigTIFF format is available in the TIFF save dialog. Photato writes 64-bit offsets for image strips and pyramid previews while keeping supported TIFF compression, profiles, layers and saved selections.

Photoshop 27.2 opened the layered BigTIFF with the Masked coating layer selected and re-saved the Gray8 BigTIFF losslessly. All 23,091 samples matched. A separate sparse test wrote and reopened a first image directory and image strip beyond 4 GiB. File and Data output matched on the tested layered images.

Native Save, Save a Copy and the authenticated Photato save and download paths use the same encoder. Set tiffBigTIFF=true to choose BigTIFF. Omission or false selects classic TIFF. Existing transfer limits apply.

Xcode built the native app. All 3 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 272 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

The high-offset test used a sparse file. Dense multi-gigabyte composite and editable-layer output and broader Photoshop container comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,217,907 bytes with SHA-256 `9520f10b4b45eefda17ae747d470e14328e21bb52586b17a10b7f743e9189227`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_779.json) · [Development record](DEVLOG.md#dev-step-779).
