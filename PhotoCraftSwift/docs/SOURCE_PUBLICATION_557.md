# Source checkpoint 557

Native Swift 0.3.0, build 557, 18 November 2026. Shift-plus and Shift-minus cycle the Brush and Pencil Mode picker. Shift-Option letters select documented modes directly. Shift-Option-Q selects Behind and Shift-Option-R selects Clear on Brush. Clear is also available in the Pencil picker and cycle. Both tools use the same ordered choices for the keyboard and picker. The focused AppKit canvas handles the keys and skips unavailable modes. [Adobe macOS shortcuts](https://helpx.adobe.com/content/dam/help/en/photoshop/using/default-keyboard-shortcuts/photoshop-keyboard-shortcuts.pdf) · [Apple keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards/).

The selected mode updates the existing brush state and revision, with no document history entry. The active stroke retains the mode and cursor captured when it began. The next stroke uses the new mode. Tests check text-field focus, modifier conflicts, transparent and locked destinations, all 25 direct mappings, forward and reverse cycling, Undo, and exact native-to-HTTP Clear stroke output.

All 454 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 146 existing brush buffers and 24 retained and complete Behind and Clear comparisons match build 556 on both architectures. Both slices of the macOS 14+ universal archive passed offscreen checks. The Mac was locked during the live Photoshop check. Exact Photoshop cycle behavior, physical keyboard layouts and layer, gradient and other non-Brush tool shortcut routing remain open.

[Development record](DEVLOG.md#dev-step-557) · [Validation evidence](BRUSH_MODE_SHORTCUTS_557.json) · [Frozen source](SOURCE_SNAPSHOT_557.json)
