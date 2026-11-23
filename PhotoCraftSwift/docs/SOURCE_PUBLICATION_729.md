# Source checkpoint 729

A narrow perspective stamp can partially cover a row of pixels even when the pixel centers lie outside it. Vanishing Point now renders that coverage for Clone Stamp and Brush, including pixels partly inside a clipped plane.

The default camera projected the failing 48-megapixel fixture to about 0.81 pixels of vertical brush thickness. The repaired fixture paints 20 pixels across two rows, with about 39% opacity near the center. Independent integration matched 36 native depth, hardness and pixel-offset cases within 0.003 normalized opacity. Rotated-plane and plane-clipping checks passed. The native preview and full render agree, and the selected crop matches the authenticated API. The source layer, local Undo, accepted edit, editable archive and document Undo also match. The tested thicker 24-megapixel and fixed-camera 48-megapixel crops retain their previous bytes.

The first edited 48-megapixel overview took 68 ms on optimized Apple Silicon and 109 ms under Rosetta once the source was ready. The overview retains 2,048 × 1,536 display pixels.

823 of 825 selected tests passed on each optimized architecture, with Intel tested under Rosetta. All three new regressions passed on both architectures. The existing layer-effect and color-profile fixtures repeated their earlier differences. The paired color-profile output matched build 728 byte for byte. Xcode built the project, all nine focused Debug core tests passed, and both signed macOS 14+ slices opened offscreen.

Photoshop 2026 opened Vanishing Point on the owned reference image. The UI exposed the dialog and its OK and Cancel controls. The process disappeared before a reference export, so Adobe pixel equivalence remains open. The default camera also reaches a separate save limit above 100,000 pixels on the longer canvas side. Healing modes and Photoshop plane interchange still need qualification. [Adobe Vanishing Point Stamp workflow](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/paint-in-vanishing-point.html)

Build inputs **9,423**. Source digest `95133c25b233fe665bca7ffd7abe37a47cc9bc8e3987bdc55bf8fb577d299cd2`. Local universal preview SHA-256 `d056dff31e2a0b93f30956f9505a033a7b1218417fafab400312b75f9077e871`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-729) · [Evidence hashes](SOURCE_PUBLICATION_729.json)
