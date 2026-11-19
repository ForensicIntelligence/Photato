# Source checkpoint 571

Native Swift 0.3.0, build 571, 18 November 2026. A ZIP request for 32-bit PSD and PSB layer channels now writes ZIP with prediction. ZIP requests for the merged preview write raw samples so Photoshop can open the file. RLE still writes an RLE merged preview. Photato continues to decode legacy files made with unpredicted ZIP.

Photoshop 2026 27.2.0 opened all eight corrected and raw-control Display P3 HDR files on each installed architecture. The saved grayscale outputs match word for word across both formats and save encodings for each of the two documents. Separate RGB8 and RGB16 controls, with the same embedded profile and samples, opened with raw and RLE merged previews. Photoshop rejected plain and predicted ZIP previews at Open in each tested format and architecture. Independently authored HDR controls reproduced those results.

All 694 selected tests passed in Debug, optimized Apple Silicon and optimized Intel under Rosetta. An independent decoder compared 24 PSD and PSB files from 12 owned inputs per configuration. All 774,416 layer and merged sample words matched the raw controls in each configuration. Each plain ZIP request produced the same bytes as the explicit predicted-layer and raw-preview request.

The new Swift tests exercise on-disk and in-memory export, legacy decoding, and explicit ZIP requests over the authenticated Photato API. The native commands and Adobe-compatible output use the shared PSD and PSB writer.

The local signed universal archive passed extraction, signature and offscreen workspace checks on both architecture slices, with macOS 14 minimum-version metadata. The package contains both optional model resources and their verified provenance.

The readable references also allow a direct comparison with build 570’s mode conversion. The two Apple Silicon cases and the Intel opaque case match all 5,120 words each. The Intel masked case still differs at 291 of 5,120 words. Broader merge behavior, byte-identical whole-file output, physical Intel hardware and macOS 14 runtime remain open.

[Development record](DEVLOG.md#dev-step-571) · [Validation data and source fingerprints](PSD_FLOAT_COMPRESSION_REFERENCES_571.json)
