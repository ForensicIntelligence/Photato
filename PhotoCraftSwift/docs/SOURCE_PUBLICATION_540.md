# Source checkpoint 540

Native Swift 0.3.0, build 540, 17 November 2026. Extended sRGB now evaluates the nonlinear power in Double and rounds to Float32 before continuing. The original Float32 operands, exponent, thresholds, final arithmetic and handling of negative values and signed zero are retained. The fix applies to desktop and API editing through the shared engine. [Extended sRGB transfer](https://www.w3.org/TR/css-color-4/#color-conversion-code).

The optimized production transfer matched across Apple Silicon and Intel under Rosetta on all 2,139,095,040 nonnegative finite Float32 bit patterns. The 2,040 block digests cover both encode and decode and match the standalone candidate. The signed probe covers another check of 1,061,749 finite inputs and found zero architecture differences in either production transfer. An independent 80-digit calculation agreed with the new power step on the 5,469 outputs that had differed on that probe. The exhaustive run covered nonnegative inputs. Signed behavior was tested separately.

All 244 focused methods and seven retained Photoshop compositing methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. The retained methods check 20 independent Photoshop exports. Both executables in the universal ZIP passed the offscreen workspace check. The 24 earlier small Brush alpha measurements are unchanged. Their existing differences from the measured Photoshop Brush outputs still apply.

## Stored Brush samples

All 32 test buffers agree across architectures in build 540. Six linear Float32 buffers differed between architectures in build 539. Each of the 24 RGB8, RGB16 and encoded Float32 buffers also matches build 539. Alpha is exact throughout the comparison. Changing the power step alters a small number of linear RGB words in new renders compared with build 539.

| Runtime | Revised buffers from 539 | Changed RGB words | Largest change in Float32 steps |
| --- | ---: | ---: | ---: |
| Apple Silicon | 6 | 832 | 7 |
| Intel under Rosetta | 0 | 0 | 0 |

Two owned regression references needed corrections. Two normalized input levels change 252 Auto-Blend RGB words by one representable Float32 step each. One Gradient Map vector changes a Green component by two steps. Independent 80-digit power calculations and the original arithmetic reproduce the corrections. The old input fixtures are retained, and both tests still require an exact output. Of 118 broader shared-color checks, 116 pass on Apple Silicon and 114 on Intel under Rosetta. Both corrected tests now pass on Intel. The remaining failures reproduce on build 539 and involve Gradient Fill PSD import, Pattern Patch API metadata and two Intel soft-proof comparisons.

## Render timing

The first build spent more time converting the same background sample for each pixel. An implicit Brush tile now converts its background once and reuses that value. The table shows the median of ten optimized runs in two trials with warmups, drawing a 990 px soft Brush on a 1024 × 1024 linear Float32 surface. The revised builds agree across architectures for each scenario. This measures isolated software rasterization. Physical editing cadence, stylus timing, macOS 14 and physical Intel remain open.

| Runtime | Surface | Build 539 | Build 540 |
| --- | --- | ---: | ---: |
| Apple Silicon | Implicit background | 63.2 ms | 59.6 ms |
| Apple Silicon | Dense pattern | 66.8 ms | 89.6 ms |
| Intel under Rosetta | Implicit background | 120.4 ms | 99.2 ms |
| Intel under Rosetta | Dense pattern | 116.8 ms | 154.9 ms |

## Hosted Brush input and drawing

AppKit ran the native workspace on Apple Silicon with a 24 MP fixture, two live adjustment layers and 12.5% zoom. The test delivered 240 points at a target 120 Hz with smoothing disabled. Each build and diameter ran once. All eight runs matched a complete native stroke, committed once and restored the source on Undo. This includes AppKit draw callbacks from the hosted workspace. Physical pointer, stylus and display measurements are still open.

| Diameter | First draw, build 538 | First draw, build 540 | Distinct draws during input, build 540 |
| --- | ---: | ---: | ---: |
| 64 px | 21 ms | 23 ms | 119 |
| 1,800 px | 848 ms | 741 ms | 1 |
| 2,500 px | 1580 ms | 1288 ms | 1 |
| 5,000 px | 4633 ms | 3700 ms | 0 |

At 5,000 px, the first worker used 3.67 s. Large-tip preparation remains the main measured cost in this fixture.

[Development record](DEVLOG.md#dev-step-540) · [Validation evidence](LINEAR_TRANSFER_540.json) · [Frozen source](SOURCE_SNAPSHOT_540.json)
