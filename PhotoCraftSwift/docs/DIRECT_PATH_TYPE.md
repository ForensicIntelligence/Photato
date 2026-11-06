# Type directly on a path

Select a connected path in the Paths panel and choose the Horizontal Type tool. Near the path, the cursor changes to an insertion beam with a curve. Click where typing should start. The draft copies the path and its start fraction; editing the resulting type does not alter the saved path.

Type and select text on the curve. The native text view keeps rich text input, marked text, local typing Undo and existing commit/cancel controls. Carets, range selection and IME candidate placement use CoreText string positions on the same baseline as the renderer. Character/Paragraph controls retain the selected range. Commit adds one document Undo; Cancel leaves the source document unchanged.

Existing horizontal Path, Circle, Arch and Bow layers use the curve editor as well. The viewport and layer transform map carets into the native window, including affine placement. Preview work is detached and generation-guarded; cancelled or superseded work cannot commit a document. Detaching/reattaching the editor restarts an interrupted preview. The normal straight-text caret drawing is suppressed in this editor.

A press captures the path, document and tool. A changed document/tool or a drag beyond the click threshold cancels creation. All sixteen Control/Command/Option/Shift combinations currently dispatch the same path-entry operation and cursor. Space retains panning. Unsupported vertical path typing displays an unavailable cursor and does not create ordinary point text in its place. Exact Photoshop alternate-modifier behavior has not been observed for this increment.

## Optional API

Existing `text.create`, `text.set` and `text.layout` use the same engine. A native path draft corresponds to `text.create` with logical `x: 0`, `y: 0`, the entered text and its complete geometry: `mode: path`, copied `path`, and `start` fraction. Other x/y values retain their existing logical offset semantics. `text.layout` still accepts a saved `pathID` and copies it into existing type coordinates.

The root Photato state adds `pathTypeEditing`, with `supported`, `editing`, `rendering`, `mode`, `utf16Selection`, `caretCount`, `overset` and `error`. Its schema and capabilities describe supported native entry and remaining limits. It reports cached editor geometry rather than creating another layout for each state request. This increment adds no typed command, Adobe route or serialized format. There are 251 typed operations, native document 86, Actions 50, settings 4 and panel catalog 3.

Adobe's pinned API has no dedicated native curve-editor interface. Supported published text jobs continue to share the renderer; no new undocumented descriptor is advertised.

## Evidence and remaining work

Before changing shared path preparation, an unchanged-production run captured 36 owned render planes and metrics across Path/Circle/Arch/Bow, fitting, reverse direction, offsets and RGB8/16/32. The current Debug tests retain exact output words. These are prior-Photato regression fixtures, not Adobe output or an old Intel baseline. No font or Adobe artwork is redistributed.

The current affected Debug run passes 158 of 159 methods, including all ten new path methods and the original point/panel workflows. The remaining three assertions are the unchanged imported-source comparison failure. Native tests cover input and marked text, grapheme-safe caret/hit coordinates, selected-range formatting, local Undo, commit/Cancel/document Undo, affine existing layouts, all sixteen modifier contexts, stale/motion/tool-switch/busy/vertical guards, preview reattachment/cancellation and native/API equality at each depth. The same 485 optimized methods pass 484 on Apple Silicon and 482 under Rosetta. All six new native workflow methods pass both. Both retain the imported-source mismatch; Rosetta also retains the previous five 8-bit point-text assertions and three Float32 path-image assertions. In the latter, thirteen alpha words across three planes differ by one ULP; RGB words match. All 36 path planes match on Apple Silicon and 33 match under Rosetta. The exact assertions and fixtures remain unchanged. No cause or old Intel baseline is established. The universal macOS14 package, signature and extracted ZIP verify; the affected suites and cross-architecture byte identity remain unqualified.

The native canvas capture shows the curve, complete owned text, selection and underline. It is an offscreen automated native rendering, not a live interaction or Photoshop comparison. Physical Intel/macOS 14, sustained 60 fps, accessibility/IME/composer completeness and exact Adobe defaults/output remain unqualified.

Full T04 remains open. Vertical, inside-path and warped inline editing; live delimiters, start/end dragging and flip gestures; fully composited mask/opacity/effect appearance while typing; complete font/composer behavior, fitting, PSD and maximum capacity still need work. A full-circle start and end can occupy the same geometric point; full delimiter/affinity behavior remains open. Current path rendering retains its 16,384 UTF-16-unit, 2,000,000-outline-point and 16 MP bounds. This selected workflow does not close that scope or the overall Photoshop goal.

References: [Adobe: add text along paths or inside shapes](https://helpx.adobe.com/photoshop/desktop/text-typography/text-on-paths-shapes/add-text-along-paths-or-inside-shapes.html), updated 23 February 2026; [Dynamic Text overview](https://helpx.adobe.com/photoshop/desktop/text-typography/work-with-dynamic-text/dynamic-text-overview.html), updated 28 August 2026. Public CoreText/AppKit APIs supply the native implementation contracts. No Adobe implementation code was inspected. The Mac remained locked during this increment; the earlier human unlock request is still pending.
