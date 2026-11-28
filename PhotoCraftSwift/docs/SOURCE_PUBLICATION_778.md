# Source checkpoint 778

Photato opens supported BigTIFFs as editable documents. Its native reader uses 64-bit offsets to find strips, rectangular tiles, metadata and supported Photoshop layer records.

Photato and Photoshop 27.2 decoded all 23,091 grayscale samples from a test strip stored at byte 4,295,032,832, beyond the classic TIFF offset limit. The standalone native reader peaked at 19.7 MiB of memory on that sparse file. A separate big-endian BigTIFF matched 141,932 individually authored CMYK16 samples. The tests also compared indexed, bitmap and editable layer records with their classic TIFF references.

Native Open, authenticated Photato uploads and Adobe-compatible action inputs share the decoder. The smaller API fixture retained its 225 ppi resolution and its grayscale and opacity samples. The existing HTTP transfer limits apply.

Xcode built the native app. All 4 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 268 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

The >4 GiB test used a sparse file with a small image at a high offset. Dense multi-gigabyte pixel and Photoshop-layer payloads, BigTIFF output and broader format comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,202,010 bytes with SHA-256 `d56ecfb290a9f7fc9d1e25b55f71693235472c3b790e943e7eb0c7743998dc7e`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_778.json) · [Development record](DEVLOG.md#dev-step-778).
