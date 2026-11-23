# Source checkpoint 724

Clone Stamp and Healing Brush can reuse the prepared canvas composite for Current & Below and All Layers. The renderer checks that the cached document matches the requested source and layer cutoff. Source selection, previews and authenticated Photato edits share this sampling path.

On the 2,096 × 2,592 portrait, the optimized Apple Silicon raw sampling step went from 190.2 ms to 0.17 ms with a ready exact composite. Under Rosetta it went from 352.4 ms to 0.22 ms. All source bytes matched. The six optimized portrait edits matched build 723 PNGs exactly. The editor preview, commit and authenticated API output matched. Each repair stayed on an editable correction layer after reopening and could be reversed with one Undo.

Healing Brush reduced mean RGB error in the three defect regions from 14.26, 12.62, 11.85 to 8.32, 4.98, 3.08 levels. Clone Stamp increased error for two of the three sampled source anchors. Every case left the pixels outside its brush envelope unchanged.

With the ordinary New Layer action, Apple Silicon rendered the first preview in 183–192 ms. Using a compact 2 × 2 raster that had to expand, the first preview took 641–682 ms. The normal sparse New Layer raster can update a small region. Depth conversion still took most of its first-frame time. Both layer geometries produced the same tested PNGs.

765 of 766 selected tests passed on each optimized architecture, with Intel tested under Rosetta. Debug passed 764 of 766. The new sampling regression passed on all three configurations. The existing PSD layer-effect test repeated its 118 assertions. Debug also reproduced the inherited Smart Filter PSD export stack overflow. Xcode built the checked-in project. The signed macOS 14+ preview opened offscreen on both architectures.

These tests compare Photato’s output across configurations and against a clean portrait reference. Live Photoshop comparison is still open. Raw sampling time measures a single preparation stage. Actual pointing-device feedback and physical frame cadence remain open. The Clone Stamp still requires the user to match both source texture and tone. Photoshop 27.2.0 exposed zero accessible windows and menu bars during the comparison attempt.

Build inputs **9,423**. Source digest `117c592a1498e5b1512fa69d945a73dc43dc48d5bd87a405d90e26d579be47f1`. Local universal preview SHA-256 `72ac2938a1ecb6f29a4412876988099a9842354ce4c0d80b1f15b59679515340`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-724) · [Evidence hashes](SOURCE_PUBLICATION_724.json) · [Portrait source credit](https://www.nasa.gov/image-article/spacex-crew-4-mission-specialist-jessica-watkins/)
