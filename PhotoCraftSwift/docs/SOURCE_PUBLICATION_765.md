# Source checkpoint 765

PSD and PSB now compose the merged preview from native gray samples on aligned Normal layers at 8 and 16 bits per channel. The preview is white-matted when the composite has transparency. Opaque composites omit the merged opacity plane. Save retains the original editable layer samples and opacities.

Four Photoshop 27.2.0 PSD saves cover opaque and transparent stacks at both depths. An independent decoder matched every merged sample in the Photato PSD and PSB files with Raw and RLE encoding. The 16 comparison files match byte for byte across Debug, optimized Apple Silicon and translated Intel.

Desktop Save, authenticated Photato PSD and PSB downloads and the Adobe-compatible PSD output encoder share the writer. The hosted Photato and Adobe-compatible action routes matched the four Photoshop preview references.

The Xcode project built and all 37 focused imaging and 11 app and HTTP tests passed. Both optimized architectures passed all 226 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The Adobe comparisons cover the merged previews of the tested layer stacks. Whole-file equality, Adobe’s layer bounds and Gray16 rounding on re-save, and grayscale TIFF opacity remain open.

The signed Universal ZIP targets macOS 14 and later. It contains 77,982,405 bytes with SHA-256 `3b554c86932c54800a04102286ba31d6c4d1e7f9eec4af63861b7ed19695a4f0`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_765.json) · [Development record](DEVLOG.md#dev-step-765).
