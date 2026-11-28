# Source checkpoint 769

Supported Grayscale, CMYK and Lab TIFF strips stream through local file Open and Save. Photato keeps the original numerical channels and uses bounded strips for the copy or composite.

A 16,384 × 17,408 Gray16 file opened, saved and reopened through the native file APIs. The source exceeded 512 MiB and libtiff compared all 285,212,672 samples against the rewritten output. The reopened copy retained its embedded color profile. The Xcode tests include a 36-megapixel Gray16 copy, editable CMYK layers and a separate sparse file above 512 MiB.

Authenticated TIFF downloads and Save As use the same strip serializer through their existing options. The selected HTTP save and download produced identical files, with exact gray and opacity samples after reopening. HTTP transfer and individual layer payload limits still apply.

The Xcode project built and all 47 selected imaging and 14 app and HTTP tests passed. Both optimized architectures passed all 237 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

Supported local classic TIFFs use 32-bit offsets. Larger RGB TIFF streams, tiled component TIFF, BigTIFF, some specialized layered blocks and more Photoshop sample comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,046,067 bytes with SHA-256 `2f8afb1e64338e79e46b68195913759a9cef3c8299b07a3a2f331fa8353d53cf`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_769.json) · [Development record](DEVLOG.md#dev-step-769).
