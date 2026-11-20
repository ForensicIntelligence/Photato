# Keep type and shapes as vector outlines in print

19 November 2026 · Development preview 639

**File > Print > Output > Include Vector Data** keeps eligible solid shapes and horizontal type as vector outlines. It starts enabled and can be turned off for a fully rasterized rendition. The print preview, macOS print job and authenticated PDF use the same prepared page. The checkbox is unavailable for Hard Proofing, Separations, Photato-managed color and incompatible image modes. [Adobe printing and vector data reference](https://helpx.adobe.com/photoshop/desktop/print/print-images-from-photoshop.html)

The renderer considers an uninterrupted set of Normal, opaque, unmasked layers above the image. Supported shapes share the same stroke geometry as the canvas, including eligible solid strokes. Supported type uses native glyph outlines. A layer needing masks, a dependent blend, fallback glyphs, multiple colors or preserved source pixels stays in the raster stack, with its backdrop. The outlines use the working RGB profile and the same document-to-page transform as the raster. Print Selected Area, paper clipping, scale and print marks still apply.

The print option is retained in native print settings and in the supported Adobe Print Style field when explicitly configured. Earlier native files without this field use the enabled default. `print.configure` accepts `settings.vectorData`, and `printing.vectorData` describes the available output. [Photato API](AUTOMATION_API.md#vector-print-output-preview-639)

The owned 160 × 120 pt test page used a bounded selection, a filled and stroked ellipse and three outlined letters. An independent parser found nine path starts and 44 curve operators in vector output, with a single 64 × 44 white raster backdrop. The raster setting produced no contour operators. Poppler rendered both outputs at 72 and 720 dpi and placed the colored shape and lettering as expected.

Adobe describes vector output for supported PostScript workflows. These tests verified Photato's macOS PDF drawing path. Physical driver qualification, exact comparison with live Photoshop and vector output through more complex color and layer workflows remain open.

The wider run surfaced two editable shape interchange failures. A rectangle with Photoshop's `vscg` record failed to import, and a native rectangle failed to export as an editable PSD or PSB shape. Both failures reproduce in build 638. The full first test run (local evidence) and the prior-build reproduction (local evidence) are retained alongside the print results.

The first compiler run flagged the Core Graphics path's missing Swift concurrency annotation. Vector marks now own an immutable path copy before crossing from background preparation to the native preview. The second run passed all 76 print, save and live-shape checks in 59.90 seconds. The signed Apple Silicon macOS 14-targeted ZIP verified after extraction and produced a 1,000 × 650 workspace snapshot. The cumulative 1,197-case run is in progress on Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta.

The source patch (local evidence), focused test log (local evidence) and independent PDF verification (local evidence) accompany the build.
