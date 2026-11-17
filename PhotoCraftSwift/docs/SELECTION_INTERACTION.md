# Selection borders and canvas size

With New Selection active, drag inside a completed rectangular/elliptical, row/column, lasso/polygonal or magic-wand selection to move its border. Hold Shift during the drag to constrain movement to 45-degree increments. Arrow keys move the border by one pixel; Shift-arrow moves it by ten. Pending repeats are queued. The Move tool keeps its existing pixel-movement behavior.

The contour follows the pointer before release; mouse release commits one Undo transaction. Escape discards the draft. A new replacement selection hides the previous outline at pointer-down; Add/Subtract/Intersect retain it. Stale gestures, tool changes and view detach cannot commit a replacement accidentally. Integer translations retain the original grayscale coverage bytes and leave layer pixels untouched.

Canvas Size keeps magnification and pan. It resolves an initial Fit before changing dimensions and does not fit the previous dimensions while the resize is in flight. Undo/Redo retains this viewport policy.

The optional API uses existing selection.transform and document.canvasSize transactions. Direct pointer presentation adds capability metadata, with no streaming or new Adobe route. Desktop/API/Actions/archive checks use the same native Swift engine.

Build 526 adds Space repositioning during rectangular/elliptical creation: start dragging, keep the mouse pressed, hold Space to move the draft, then release Space to resize again. The cursor follows with closed Hand during repositioning. Combine mode, anti-alias and feather are captured at press; later Shift/Option changes affect shape geometry. Escape, focus, tool, source and busy changes discard the draft. Space before press retains the existing canvas Hand/pan behavior; single row/column are excluded.

An unfinished polygon takes priority over the old selection border, so a later vertex can be placed inside existing coverage. Final coverage still uses selection.shape, with the same native/API/Actions/history and archive behavior. Presentation metadata is discoverable under toolCursorFeedback.marqueeCreation and selectionTools.marqueeCreation.

Committed transforms still clip selections to the document. Temporary Command pixel movement, complete Photoshop cursor/default behavior and physical frame rate remain unqualified. All 86 selected tests, including 15 new contour/marquee methods, pass in Debug and both optimized architectures. Native launch/title is verified; live editing/save/reopen remains unqualified after chooser automation failed. This does not claim complete Photoshop parity.

References: [Adobe — Move a selection border](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/move-selection-or-selection-border.html), [Adobe — Marquee tools](https://helpx.adobe.com/photoshop/desktop/make-selections/get-started-selections/make-selections-with-marquee-tools.html).

[526 evidence](SELECTION_FEEDBACK_526.json) · [524 evidence](SELECTION_INTERACTION_524.json) · [526 diary](pending-updates/step526.md)
