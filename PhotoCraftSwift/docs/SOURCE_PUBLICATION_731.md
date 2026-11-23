# Source checkpoint 731

Vanishing Point adds Heal Off, Luminance and On for the Brush, Stamp and pasted patches. Luminance matches the surrounding light while keeping the source color differences. On blends both light and color. The native workspace and authenticated Photato API share the renderer.

On the 1,600 × 1,200 owned texture, Luminance lowered the mean lighting error on 901 defect pixels from 0.06803 to 0.00137. On lowered the mean RGB error from 0.15817 to 0.00000. The tested crop hashes agree in Xcode Debug and both optimized slices. The native and authenticated HTTP paths agree on each mode’s preview, editable archive, source and Undo. The core checks cover RGB8, RGB16, RGB32, a translucent pasted patch and an active selection.

830 of 832 selected tests passed on each optimized architecture, with Intel tested under Rosetta. All four new cases passed on both. The existing layer-effect and color-profile fixtures repeated their earlier differences, and the paired color-profile outputs matched build 730 byte for byte. Xcode built the project, all 14 focused core tests passed, and both signed macOS 14+ slices opened offscreen.

The solver bounds each local repair region, including its one-pixel boundary, to 4,194,304 pixels. Applying into an imported 1 × 1 transparent repair layer leaves an out-of-bounds defect unchanged. The New Layer option handled the same repair. Photoshop 2026 pixel comparison and full product retouch acceptance remain open. [Adobe’s painting controls](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/paint-in-vanishing-point.html) · [Adobe’s floating selections](https://helpx.adobe.com/ph_fil/photoshop/using/vanishing-point.html)

Build inputs **9,423**. Source digest `663b6a6b1ae0003fd72f355285484db86414d88e00105ce1306d0965a22a2aff`. Local universal preview SHA-256 `a71242537796236c69cac82058e5e62a4a32f8c887520c99056524ce3d16f9df`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-731) · [Evidence hashes](SOURCE_PUBLICATION_731.json)
