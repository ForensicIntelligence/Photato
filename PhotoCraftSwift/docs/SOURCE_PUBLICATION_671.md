# Source checkpoint 671

Native Swift 0.3.0, build 671, 20 November 2026.

Perspective and Distort now move linked vector masks with the artwork and keep unlinked masks fixed. Masks remain editable after native, PSD and PSB saves.

All 131 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

All 12 owned PSD, PSB and composite outputs matched across the three configurations. An independent PSD/PSB path reader checked 2,064 samples of the saved curves. The largest measured deviation from the analytic projection was 0.00684 document pixel, including file quantization. Each of the eight Photoshop container round trips preserved all composite bytes.

The original PDF was placed by Photoshop. Photato applied the reference transforms. Exact Photoshop anchors and pixels, independent Free Transform on a selected path, and vector masks with non-neutral Warp remain open.

[Development record](PROJECTIVE_VECTOR_MASKS_671.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_671.json)
