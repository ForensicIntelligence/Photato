# Source checkpoint 723

Select and Mask adds Refine Hair for a rough selection or an existing layer mask. Photato recovers soft strand coverage near the subject and keeps it editable. The native workspace previews the result before committing. The optional Photato API uses the same refinement.

The owned patterned-backdrop control recovered 85.0% of missing strand coverage, with 3.5% false coverage in nearby background. Partial-coverage alpha error fell from 0.335 to 0.104. Seven fixtures matched mask and PNG output bytes across Debug, optimized Apple Silicon and Intel under Rosetta. Masks stayed editable through native, PSD and PSB reopen. The independent reader matched stored coverage in both Photoshop file formats.

719 of 720 selected tests passed on each optimized architecture, with Intel tested under Rosetta. Debug passed 718 of 720. Both new regression methods passed on all three configurations. The optimized suites repeated the existing PSD layer-effect failure. Debug also reproduced the inherited Adobe-compatible Smart Filter stack overflow. Xcode built the checked-in project. The signed preview opened both macOS 14+ slices offscreen, and the Select and Mask control was inspected offscreen in Light and Dark.

The measured reference set includes wigs, toy hair, fibers and two controlled backdrops. Darkening the new background can reveal residual color on very fine strands. Complex backgrounds and strands far from the coarse mask still need manual refinement. Live Photoshop comparison and physical VoiceOver and keyboard checks remain open.

The installed Photoshop version is 27.2.0. Its last live inspection at build 722 exposed no accessible windows or menu bars.

Build inputs **9,423**. Source digest `34d01853ffe5bc0f3da16abd59f24d90d2ddfdc9dcc02314f921ebdf74e978c8`. Local universal preview SHA-256 `e4dca9a1d6c5627595a82c9b88a38f12a8bcf5f9e596f7ed7684abfa861d071a`.

[Refine Hair guide](REFINE_HAIR.md) · [Development record](DEVLOG.md#dev-step-723) · [Evidence hashes](SOURCE_PUBLICATION_723.json)
