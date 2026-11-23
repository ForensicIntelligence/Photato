# Source checkpoint 726

Clone Stamp and Healing Brush now redraw the affected area when a plain, integer-aligned transparent layer grows. The renderer includes both the old and new tile bounds, including when expansion shifts the layer origin. The native editor and authenticated Photato API use the same compositor.

The independent Xcode Debug checks matched raw composites at RGB8, RGB16 and RGB32. The cropped portrait replays matched the saved PNG, editable archive, authenticated API and exact Undo. Each optimized architecture matched all 12 build 725 PNGs across ordinary and cropped correction layers.

The cropped correction layer's first preview took 115–124 ms on optimized Apple Silicon, compared with 498–554 ms in the adjacent build 725 run. A scripted 48-sample cropped-layer stroke published 42 Clone Stamp and 41 Healing Brush previews. The preceding build published three for each tool on the same fixture.

797 of 799 selected tests passed on each optimized architecture, with Intel tested under Rosetta. Both new cropped-layer tests passed in Xcode Debug and in both optimized suites. The existing PSD layer-effect fixture repeated 118 assertions. The retained build 725 bundles repeated the color-profile fixture results, including identical dense and paged output bytes on each architecture. The Xcode project built, all six focused Debug tests passed, and both signed macOS 14+ preview slices opened offscreen.

These measurements cover software rendering and publication of previews. Physical pointer-to-display cadence and direct comparison with Photoshop 2026 remain open. The running Photoshop 2026 process exposed no accessible editing windows or menu bars during this phase.

Build inputs **9,423**. Source digest `dfeb2eae34212b3c10caf58f5caed518a0a9111d6220676bcd0ff574266b6acd`. Local universal preview SHA-256 `ed81cc431d718946b0a308b645c5a19bdb91e45f5c59c1e130c1b9f3b3db3aaa`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-726) · [Evidence hashes](SOURCE_PUBLICATION_726.json)
