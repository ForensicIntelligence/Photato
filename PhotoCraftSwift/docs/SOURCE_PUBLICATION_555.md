# Source checkpoint 555

Native Swift 0.3.0, build 555, 18 November 2026. Braces adjust analytic-tip hardness in 25-point steps. Left rotates counterclockwise and Right clockwise. Shift-arrows rotate 15° per press. The AppKit handler preserves text editing, the standard modifier chords, and movement behavior in other tools. [Adobe macOS shortcuts](https://helpx.adobe.com/content/dam/help/en/photoshop/using/default-keyboard-shortcuts/photoshop-keyboard-shortcuts.pdf) · [Apple keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards/).

Option-digits set smoothing in Brush, Pencil, Mixer Brush and non-Block Eraser. The existing number-key logic uses 0.5 seconds for an exact two-digit entry. The Options bar and Brush Settings retain the values. Settings changed while painting affect the next stroke. [Adobe stroke smoothing guide](https://helpx.adobe.com/ph_fil/photoshop/desktop/repair-retouch/clean-restore-images/create-smoother-more-polished-brush-strokes-with-stroke-smoothing.html) · [Brush shortcut reference](https://jkost.com/blog/2017/05/brushes-and-painting-tool-shortcuts-in-photoshop-cc.html).

The same hardness, angle and smoothing fields are exposed through brush.configure, brush state and paint.stroke. The same timed stroke produced identical pixels after the keys and through the HTTP settings patch. The keyboard changes create no document history entry.

All 413 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 146 comparison buffers match build 554 byte for byte on each architecture. Both slices of the macOS 14+ universal archive passed the offscreen workspace check. Photoshop was inaccessible on the locked Mac. Live keyboard behavior across layouts, exact stroke placement and physical editing cadence remain open.

[Development record](DEVLOG.md#dev-step-555) · [Validation evidence](BRUSH_TIP_SHORTCUTS_555.json) · [Frozen source](SOURCE_SNAPSHOT_555.json)
