# Source checkpoint 768

Photato decodes supported classic TIFF strips into editable, file-backed color planes. Gray, CMYK and Lab data retain their original component values and supported precision as well as an RGB display preview.

Independent libtiff comparisons matched 258,014,000 native 16-bit channel words across ZIP, predicted LZW and raw TIFF inputs, including a 6,000 × 6,000 grayscale image and a planar CMYK control. The measured opacity plane was fully opaque in those four comparisons. A rotated Gray8 fixture separately verified associated alpha. An edited 36-megapixel grayscale copy reopened from a Photato archive with its complete edited component data intact.

Desktop Open, authenticated Photato document uploads and action-job TIFF resource decoding use the same file-backed component reader. The optional API advertises the expanded classic strip input. Its existing HTTP transfer limits still apply.

The Xcode project built and all 44 selected imaging and 13 app and HTTP tests passed. Both optimized architectures passed all 233 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

This checkpoint changes supported classic strip input. The 512 MiB encoded desktop limit, large TIFF output, tiled component TIFF, BigTIFF, layered capacity and independent Photoshop transparency comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,010,093 bytes with SHA-256 `0ab7ffb8664826c2da43d108e44f0c64aac18b110050f7cb44edc0ab9659df54`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_768.json) · [Development record](DEVLOG.md#dev-step-768).
