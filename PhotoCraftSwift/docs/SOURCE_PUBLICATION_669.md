# Source checkpoint 669

Native Swift 0.3.0, build 669, 20 November 2026.

Embedded and linked PDF Smart Objects retain editable Warp in PSD and PSB. The renderer resamples the original PDF when the Warp magnifies the artwork. The page, crop and layer controls stay editable.

All 88 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

The owned Photoshop PDF fixture retained every composite byte when a neutral Warp mesh was added after 3× enlargement. Four new tests cover local PDF magnification, mask coordinates, rasterization, linked relink and native/HTTP interchange. 8 of 8 fixture outputs matched byte for byte across the three Photato configurations. Twenty-three supplemental Debug cases passed. Filtered PDF exports reopened with identical composites. All three prior raster Warp files and eight Intel RGB32 PSDs matched the preceding outputs byte for byte.

The running Photoshop scripting interface timed out. The independent Photoshop-authored PSD supplies the original PDF page and crop. A Photoshop-authored PDF with Warp, live Adobe rendering comparisons and full dense PDF capacity remain open.

[Development record](PDF_SMART_OBJECT_WARP_669.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_669.json)
