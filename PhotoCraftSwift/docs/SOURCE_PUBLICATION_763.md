# Source checkpoint 763

Open now creates an editable RGB8 layer from a PNG palette with partial opacity or multiple transparent entries. The decoder retains straight RGB and all per-pixel opacity. A palette with one or zero fully transparent entries and no partial opacity stays editable as Indexed Color.

Desktop Open, authenticated Photato import and the existing Adobe-compatible PNG action-resource reader share the native decoder. The regression also compares the authenticated PNG download with a desktop save. The public schemas stay the same.

All 35 focused imaging tests and ten app and HTTP tests passed in Xcode Debug. Both optimized architectures passed all 223 selected tests. Intel ran under Rosetta.

Photoshop 27.2.0 opened all five owned controls in the same modes as Photato. Independent decoding matched 748 straight RGBA imports and 187 retained indices. The graded-palette Photoshop PNG copy matched all 187 source RGBA samples, including hidden RGB.

The second Photoshop PNG copy verified all 187 rendered samples for the unused-opacity control, including the fully transparent pixels outside the visible bounds.

The comparisons cover the tested palette tables and exact decoded samples. Complete PNG container equality and animated indexed PNG import remain open. Photoshop also opened an owned 8,389,632-pixel palette PNG beyond the current Photato restricted PNG limit.

The signed Universal ZIP targets macOS 14 and later. Both extracted architectures rendered offscreen. The 77,953,079-byte ZIP has SHA-256 `290fd76bf39efd5c6ac86ed9e4efa404f7636f341ab3a0545457a44686de5403`.

[PNG palette transparency specification](https://www.w3.org/TR/png-3/#11tRNS).

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_763.json) · [Development record](DEVLOG.md#dev-step-763).
