# Source checkpoint 720

Select and Mask can recover partial coverage from a rough selection. Estimate a smooth background or choose an aligned photo of an empty textured backdrop. Erase Refinement restores the input coverage where you brush. Decontaminate Colors removes the backing color and the result can keep an editable mask or export as transparent PNG. The Photato API uses the same workflow.

Four controlled glass and fabric cases compared the exported alpha and the recovered colors over light and dark backgrounds. Partial-alpha mean absolute error fell from 0.589–0.626 to 0.062–0.117. Both backgrounds improved on all four cases. The first aligned reference test showed a visible textured imprint. Using changes in the aligned backing estimated the local transmission and reduced the measurable checkerboard imprint by 88% in the sampled clear interior. Desktop and API exported identical PNGs. Native, PSD and PSB reopened with editable masks and retained the same PNG bytes. One Undo restored each input exactly. The exported PNGs also matched across Debug, optimized Apple Silicon and optimized Intel under Rosetta. The optimized Apple Silicon prepared edit ran in 0.15 seconds on the 1,536 × 1,152 aligned test image.

623 of 624 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The two new tests passed in all three configurations and cover RGB8, RGB16 and RGB32 smooth recovery and the desktop/API textured workflow. The PSD layer-effect test repeated the same 118 differences as build 719. Xcode built the checked-in project. Both slices target macOS 14.0 and opened the signed preview offscreen.

The four cases use independently generated scalar alpha masks. The recovered glass still has some edge tint and near-opaque coverage errors. The photographic GT03 case from the Rhemann et al. CVPR 2009 matting dataset exceeded the smooth-background limit. The tool asked for an aligned backing, which that photographic input archive lacks. Single-image recovery against complex backgrounds, physical refraction and exact Photoshop behavior remain open. [Matting benchmark](https://static.alphamatting.com/datasets.html)

The installed Photoshop 27.2.0 returned its version and exposed zero accessible windows and menu bars.

Build inputs **9,421**. Source digest `585fe480f083fbe4d633b2ef2cb6ee1cbb2cf58628100afc0ee872fbadab0e0f`. Local universal preview SHA-256 `4c8d260ea8ac6a90edd4ab60c75739e0b6037f2c20115c7cdc8e69920621058e`.

[Transparency guide](TRANSPARENCY_RECOVERY.md) · [Development log](DEVLOG.md#dev-step-720) · [Evidence hashes](SOURCE_PUBLICATION_720.json)
