# Source checkpoint 553

Native Swift 0.3.0, build 553, 18 November 2026. Soft Round and Soft Round Pressure Opacity now use a wider alpha falloff at zero hardness. The brush diameter setting still represents the nominal size. The texture and dual-tip controls and the current pen pressure behavior remain available.

The Swift renderer's alpha differed by at most 3 of 255 levels on the six saved zero-hardness dabs from 3 to 41 px after aligning their centers. The original Photato renderer differed by up to 35 levels on the same samples. Two separate 13 px dabs differed by at most 2 levels. The recorded-click comparison without center alignment still differs by up to 118 levels. Verified sample bytes match between the optimized architectures. Higher-hardness outputs matched build 552 in all 18 saved cases.

The comparison used existing RGB8 exports from two documents created in Photoshop for this test. The new profile derives from the 7, 12 and 21 px samples. The 3, 13 and 41 px main-sheet samples and the separate 13 px examples were held out. Physical pointer placement, tablet timing, continuous Photoshop strokes and nonzero-hardness falloffs remain open. Moving above zero hardness presently switches back to the earlier falloff.

All 409 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The new tests cover 5,000 px raster bounds, all three pixel depths, equal complete and retained output, preset migration and format handling, and matching desktop and API stroke pixels through Undo and Action replay. All 146 legacy raster buffers match build 552 on each architecture. A separate 5,000 px two-point probe checks that the native raster session can switch to the complete painter under its coverage budget. Both slices of the universal validation package passed the offscreen workspace check.

The existing Photato commands expose the optional profile. Native preset files version 2 and Action libraries version 63 preserve it. Older files preserve their previous rendering. ABR continues to exchange standard round-tip metadata.

[Development record](DEVLOG.md#dev-step-553) · [Validation evidence](WIDE_SOFT_ROUND_553.json) · [Frozen source](SOURCE_SNAPSHOT_553.json)
