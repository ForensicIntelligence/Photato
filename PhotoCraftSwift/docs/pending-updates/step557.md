<a id="dev-step-557"></a>

## 2026-11-18 — Add Brush and Pencil blend-mode shortcuts

Brush and Pencil now cycle their Mode picker with Shift-plus and Shift-minus. Shift-Option with a documented letter selects its blend mode directly. Q selects Behind and R selects Clear when Brush is active. Pencil can reach Clear through the picker or cycle. The Mac was locked during the Photoshop check, so the letter assignments use Adobe’s published macOS keyboard table and the exact live cycle remains open. [Adobe macOS shortcuts](https://helpx.adobe.com/content/dam/help/en/photoshop/using/default-keyboard-shortcuts/photoshop-keyboard-shortcuts.pdf).

BrushEditing.swift and PaintingTools.swift share the same ordered choices, with the existing destination checks on Behind and Clear. CanvasView.swift handles the keys only when the canvas owns focus and reserves the modified chord so it cannot change tools or swap swatches when a field has focus. The Mode picker uses its native label and help. The Clear cursor, brush revision, and captured-stroke behavior follow the existing paint settings. [Apple keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards/).

AutomationBrushes.swift reports the direct keys and cycle in the existing brushes capabilities. Mode and paintMode stay on the shared brush settings, and shortcuts create no document history. BrushWorkflowTests.swift covers all 25 mappings, the full picker cycle, locked targets, Pencil, a hosted text field, changes during a stroke, the cursor, Undo and HTTP pixel equality. Info.plist advances the build to 557.

A follow-up audit traced Paint Bucket and Magic Wand to the same dense color-region matcher. Its arrays could require about 503 GiB on a 300,000-pixel-square input. A separate probe matched all 120 dense reference masks across the three depths and produced full or empty coverage at 300,000 pixels per side with zero tiles and a 512-byte resident index. The probe covers uniform nearest-mapped sources. Production integration and general large color matching remain open.

All 454 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 146 established brush buffers and 24 Behind and Clear buffers matched build 556 on both architectures. Both slices of the universal archive passed the offscreen workspace check. The Actions workflow's rolling screenshots are stored with their test attempts. [Qualification](SOURCE_PUBLICATION_557.md).
