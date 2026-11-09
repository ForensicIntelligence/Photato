# Selection borders and canvas size

With New Selection active, drag inside a completed rectangular/elliptical, row/column, lasso/polygonal or magic-wand selection to move its border. Hold Shift during the drag to constrain movement to 45-degree increments. Arrow keys move the border by one pixel; Shift-arrow moves it by ten. Pending repeats are queued. The Move tool keeps its existing pixel-movement behavior.

The contour follows the pointer before release; mouse release commits one Undo transaction. Escape discards the draft. A new replacement selection hides the previous outline at pointer-down; Add/Subtract/Intersect retain it. Stale gestures, tool changes and view detach cannot commit a replacement accidentally. Integer translations retain the original grayscale coverage bytes and leave layer pixels untouched.

Canvas Size keeps magnification and pan. It resolves an initial Fit before changing dimensions and does not fit the previous dimensions while the resize is in flight. Undo/Redo retains this viewport policy.

The optional API uses existing selection.transform and document.canvasSize transactions. Direct pointer presentation adds capability metadata, with no streaming or new Adobe route. Desktop/API/Actions/archive checks use the same native Swift engine.

Committed transforms still clip selections to the document. Space repositioning during marquee creation, temporary Command pixel movement and complete Photoshop cursor/default behavior remain unqualified. The current session tested native AppKit view events, not the user's running UI. This does not claim complete Photoshop parity.

References: [Adobe — Move a selection border](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/move-selection-or-selection-border.html), [Adobe — Marquee tools](https://helpx.adobe.com/photoshop/desktop/make-selections/get-started-selections/make-selections-with-marquee-tools.html).

[Evidence](SELECTION_INTERACTION_524.json) · [Diary](pending-updates/step524.md)
