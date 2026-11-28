# Source checkpoint 772

Photato can open classic TIFF files with editable Photoshop layer data above the previous 512 MiB limit. It reads the layer samples in bounded ranges and keeps the original layers editable.

Two independently built 12,000 × 12,000 TIFFs each contained 576 MB of editable layer data. Photato restored the authored RGB and opacity samples in both byte orders. On these sparse fixtures, the standalone native decoder peaked at 7.2 MiB for big endian and 7.6 MiB for little endian. Two further controls retained their 300 ppi setting, TIFF description and XMP title.

The authenticated Photato upload and Adobe-compatible action resource decoder use the same bounded layer and metadata paths. Both restored the editable layer and XMP from the same 17 MB TIFF. Existing HTTP input limits still apply.

Xcode built the native app. All 10 focused imaging and 7 app and HTTP tests passed. Both optimized architectures passed all 246 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

This checkpoint removes the input limit for the tested layer container. Larger layer payloads when saving, unsupported Photoshop descriptors, additional TIFF layouts and broader byte comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,101,379 bytes with SHA-256 `f7c4f7c5a4c31fcd0dd53b8c64e345654581f1db3560386de993236cbcd58c05`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_772.json) · [Development record](DEVLOG.md#dev-step-772).
