# Point-text alignment

Centred and right-aligned point text now use a shared insertion coordinate for each hard line. TextKit lays out glyphs in positive coordinates; the renderer allocates only their resulting bounds. Changing paragraph alignment no longer turns a short line into a 32,770-pixel raster and rejects it at the existing dimension check.

Rendering, outlines, native caret and hit testing, and the editor's layer placement use the same crop and model origin. Rich justified paragraphs with a centred or right-aligned last line also update TextKit's line bounds, keeping native insertion points with the displayed glyphs. Selected text remains selected after formatting. Committing uses the existing document transaction and Undo; Cancel retains the original document.

Ordinary left-aligned point text and paragraph frames retain their previous rendering path. Fifteen owned regression planes, captured from unchanged checkpoint 437 production code before the repair, pin Apple Silicon all-depth RGBA words and metrics for left point, paragraph and vertical cases. These are regression references, not Photoshop output comparisons.

## Optional API

Existing `text.create`, `text.set`, portable Actions and supported Adobe text jobs share the repaired native engine. There is no new command or Adobe route. The Photato state response adds `textGeometry` for the active or currently edited type layer:

- `layerID`, `draft`, `available` and `error` describe the target and layout availability.
- `metrics.width` and `metrics.height` are raster dimensions.
- `metrics.localRasterOrigin` is the model-local raster offset; document placement still uses layer transforms and source-frame metadata.
- `metrics.textKitCropOrigin` is an internal drawing/caret offset, distinct from document placement.
- `metrics.pointAnchored` identifies the repaired point-layout path. A retained pristine imported appearance can supply its cached metrics instead.

The state schema and capabilities describe these fields and the remaining limits. Existing request schemas and document/native/Actions versions are unchanged. There are 251 typed commands, native document version 86, Actions 50, settings 4 and panel catalog 3.

## Qualification and remaining work

The current affected Debug run passes 132 of 133 methods, including all ten new point-layout methods and all eleven new panel methods. The remaining imported-text source-reference method has the same three exact mismatches as the unchanged pre-repair baseline. It remains in the test selection. The same 468 ordered optimized methods pass 467 on Apple Silicon and 466 under Rosetta. The unchanged imported-source mismatch remains on both. The original frozen-output method also fails five 8-bit cases under Rosetta: all ten 16/32-bit planes match, but 8-bit RGBA words and quantized bytes differ. The exact assertions and fixtures remain unchanged. No cause or old Intel baseline rerun is claimed. These are incomplete affected suites, although all selected native caret/typing/formatting/API/history workflows pass both architectures. The universal macOS 14 package, signature and extracted ZIP verify. Physical Intel/macOS 14 and cross-architecture byte identity remain open.

Tests cover native horizontal/vertical caret and hit testing, empty typing at the chosen insertion coordinate, repeated rich last-line layout, selected-range formatting, native/API output and archive equality, mask placement, Actions, Cancel/Undo and small text on a sparse 300,000 × 300,000 document. Offscreen native tests are not physical interaction or Photoshop qualification.

Type raster limits remain 32,768 pixels per side and 16 MP, with the existing 100,000 UTF-16-unit input limit. The virtual layout width is not an allocated image. Large type, point wrapping, whitespace/composer semantics, arbitrary affine native editing, full typography/PSD fidelity and Photoshop defaults/output remain open. Older centred-point documents without logical source metadata may have ambiguous placement from the former layout bug; the frozen ordinary-output cases do not qualify that migration.

The next major package is T04, path/warped/Dynamic Text. A source audit identifies direct Type-tool creation on a path as a candidate: current canvas creation handles ordinary point/box text, while existing shaped layout is entered through controls for an existing type layer. Native hover/click/cursor and draft/history/API behavior need implementation and tests. No implementation or live Photoshop pass is claimed by that audit.

References: [Adobe paragraph formatting](https://helpx.adobe.com/photoshop/desktop/text-typography/characters-glyphs/format-paragraphs.html), [text along paths or inside shapes](https://helpx.adobe.com/photoshop/desktop/text-typography/text-on-paths-shapes/add-text-along-paths-or-inside-shapes.html), [Dynamic Text](https://helpx.adobe.com/photoshop/desktop/text-typography/work-with-dynamic-text/dynamic-text-overview.html). The public Apple TextKit APIs and local SDK headers supply the native layout contracts. No Adobe implementation code was inspected.
