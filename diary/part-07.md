[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-06.md)

## 2026-11-18 — Step 569 — Match HDR grayscale conversion and ICC gamma boundaries

32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves.

All 8,510,976 samples in 257 tested precision promotions and 194,560 samples in 38 RGB32-to-Gray32 cases match Photoshop on each architecture. All 661 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-569) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_569.md).

## 2026-11-18 — Step 568 — Match half-gamma promotion and Gray32 PSD layer stacks

RGB and grayscale gamma 0.5 profiles now promote to 32 Bits/Channel using the measured rounding on each architecture. PSD and PSB use native gray samples for supported 32-bit layer stacks.

All 2,142,336 stored samples from 59 tested conversion cases match the corresponding Photoshop files on each architecture. Five Gray32 layer stacks match all 960 merged words under each of four compression modes in PSD and PSB. All 657 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-568) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_568.md).

## 2026-11-18 — Step 567 — Use the source tone curves for 32-bit RGB and Gray

Promoting an 8-bit or 16-bit RGB or grayscale document to 32 bits now uses the supported tone curves from its current ICC profile.

All 1,976,832 samples from 54 supported cases match the files saved by Photoshop 2026 byte for byte on both tested architectures, using a separate Photoshop run on each architecture. Photoshop itself returned different values across architectures for 13,057 samples from the gamma and parametric cases. The Swift conversion matches the rounding observed on each architecture. All 651 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The desktop conversion and the authenticated Photato command produce the same stored samples and both Undo correctly. Both universal app slices passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-567) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_567.md).

## 2026-11-18 — Step 566 — Preserve opaque Gray32 merged samples in PSD and PSB

PSD and PSB exports now preserve all 32-bit grayscale samples when the document contains one visible, opaque Background. The writer uses the stored grayscale samples for the merged image and leaves out the redundant transparency plane. Saved auxiliary channels still follow the grayscale plane.

An independent reader checked every sample of the 16 × 12 test image against a raw PSD saved by Photoshop 2026 at checkpoint 511. All 192 merged samples match byte for byte in PSD and PSB in all four compression modes. The comparison covers the grayscale plane and the channel count. All 629 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The tests also cover a saved auxiliary channel, hidden Background, both API encoders, and authenticated Photato downloads. Both universal app slices passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-566) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_566.md).

## 2026-11-18 — Step 565 — Add Allow Tool Recording to Actions

The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures. Tool gestures still edit pixels and appear in Undo when the setting is off.

All 608 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. In 52 channel-stroke sequences, both recording settings produced the same raw samples as direct editing and the same per-architecture output as build 564. Forty older Brush step encodings also matched. Both universal slices passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-565) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_565.md).

## 2026-11-18 — Step 564 — Record Brush Actions for color channels

Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates. Playback resolves the recorded target against the current document, respects its selection, and takes one Undo to reverse.

All 583 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. On each architecture, 52 tested channel strokes replayed to the same samples as direct editing and matched build 563’s raw planes. Forty legacy Brush step encodings also matched. Both slices of the macOS 14+ validation archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-564) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_564.md).

## 2026-11-18 — Step 563 — Record and replay Quick Mask Actions

Enter Quick Mask, edit the selection with Brush or Pencil, and exit in one Action. Replay starts with the new document’s selection and can be undone in one step.

All 558 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. On both architectures, 24 Quick Mask sequences and 24 older Fill Action encodings matched build 562 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-563) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_563.md).

## 2026-11-18 — Step 562 — Record Brush Actions for masks and channels

Brush strokes on Smart Filter masks and saved channels now play back in Actions. A stroke above a shape can still create an ordinary pixel layer.

All 531 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 96 direct and prepared Brush output buffers and 12 older Action encodings matched build 561 byte for byte on each architecture. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-562) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_562.md).

## 2026-11-18 — Step 561 — Record Paint Bucket Actions

Paint Bucket clicks can now be saved in an Action. Playback uses the new document’s layer, mask, or visible composite. A recorded pattern stays with the Action.

All 527 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 240 color-region masks and 18 direct bucket buffers matched build 560 byte for byte on both architectures. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-561) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_561.md).

## 2026-11-18 — Step 560 — Add Clear to Edit Fill and Stroke

Choose Clear to erase pixels within a selection, along an outline, or across a whole pixel layer. Clear uses the existing Fill and Stroke API commands and can be recorded as a Photato Action.

All 522 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. On each architecture, 264 existing Fill, Stroke, and Path Clear pixel buffers and the legacy settings JSON matched build 559 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-560) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_560.md).

## 2026-11-18 — Step 559 — Paint Bucket Clear and automation

Clear removes alpha from the color region you click. The Photato API can configure the Paint Bucket or fill a region using the same options. Separated sparse fills and full solid fills also update much larger canvases without a whole-canvas write loop in the tested cases.

All 486 selected tests passed across three builds. The 624 actual dense and paged writeback comparisons matched on each optimized architecture. Live Photoshop output comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-559) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_559.md).

## 2026-11-18 — Step 558 — Large Paint Bucket and Magic Wand regions

Magic Wand and Paint Bucket now page large color selections. The tested sparse cases work on 300,000-pixel-square canvases, and a uniform opaque fill can update the whole canvas without allocating pixel tiles.

All 481 selected tests passed across three builds. Existing coverage and bucket buffers matched build 557 byte for byte. Dense maximum-size timing, other fill modes and exact Photoshop comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-558) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_558.md).

## 2026-11-18 — Step 557 — Brush and Pencil blend-mode shortcuts

On the canvas, Shift-plus and Shift-minus cycle paint modes. Shift-Option-Q selects Behind and Shift-Option-R selects Clear on Brush. The shortcut changes the next stroke, so you can switch modes without interrupting the stroke underway.

All 454 selected tests passed across three builds. They cover direct shortcuts, focus, the cursor, Undo and the Photato API. Live Photoshop keyboard comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-557) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_557.md).

## 2026-11-18 — Step 556 — Behind and Clear

The Brush Mode picker now has Behind and Clear. Behind puts paint underneath existing pixels. Clear removes their alpha and also works with Pencil. You can hold the grave-accent key to use Clear for a Brush stroke.

All 418 selected tests passed across three builds. They check pixel math, transparent and locked layers, Undo, replay and the Photato API. Exact Photoshop pixel comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-556) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_556.md).

## 2026-11-18 — Step 555 — Brush keyboard controls

Braces change brush hardness. The arrow keys rotate the tip, and holding Shift makes a larger turn. Option and number keys set smoothing. The test for an active stroke confirms that keyboard changes apply to the next stroke.

All 413 selected tests passed across three builds. The desktop and HTTP settings produced matching stroke pixels. Live Photoshop key behavior and exact stroke placement still need checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-555) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_555.md).

## 2026-11-18 — Step 554 — Round brush hardness

The four factory Round presets now change smoothly from soft feathering to an opaque core with a narrow edge. The aligned nonzero-hardness samples improved from a worst alpha difference of 161 to 12 of 255 levels. The two hard dabs from a separate document were within 2 levels. Older recorded settings still replay with their original profiles.

All 411 selected tests passed across three builds. The next measurements cover exact pointer placement, intermediate hardness settings and continuous strokes.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-554) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_554.md).

## 2026-11-18 — Step 553 — Wider Soft Round tip

Soft Round and Soft Round Pressure Opacity now paint with a wider falloff at zero hardness. Across six saved Photoshop dabs, the new renderer was within 3 alpha levels after lining up the centers. The three held-out sizes were within two levels. The previous renderer was off by up to 35. Older Actions still replay with their original brush settings.

The 409 selected tests passed in Debug and both optimized builds. The next brush checks cover exact pointer positions, harder tips and continuous strokes.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-553) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_553.md).

## 2026-11-18 — Step 552 — Brush opacity and flow number keys

With the canvas focused, number keys set opacity and Shift-number keys set flow. Airbrush swaps which modifier controls each value. Two digits set an exact percentage. This shares the existing settings used by the Options bar and the API.

The tests passed in Debug and both optimized builds. A closer look at 28 saved Photoshop dabs showed that every one extends beyond the current brush footprint. Exact brush pixels and a live shortcut check remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-552) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_552.md).

## 2026-11-18 — Step 551 — Faster paint output for wide brushes

Photato calculates independent brush output tiles in parallel and installs them in their original order. The 5,000 px brush on a 24 MP workspace reached its first offscreen AppKit draw in 181 ms, down from 315 ms. All 338 checked buffers match build 550 on each architecture.

All 401 selected tests passed in Debug and both optimized builds. Physical display cadence and exact Photoshop brush output remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-551) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_551.md).

## 2026-11-18 — Step 550 — Faster drawing on large canvases

Photato composes eligible tone stacks and packs the changed display rows in parallel. The 5,000 px brush on a 24 MP workspace reached its first offscreen AppKit draw in 304 ms, down from 460 ms. All 192 checked buffers match build 549 on each architecture.

All 400 selected tests passed in Debug and both optimized builds. Physical display cadence and exact Photoshop brush output remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-550) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_550.md).

## 2026-11-18 — Step 549 — Faster coverage for large brush strokes

The brush calculates wide-dab coverage in parallel. The 5,000 px example on the 24 MP workspace reached its first AppKit draw in 457 ms, compared with 502 ms in the paired build 548 trials. All 146 tested buffers matched build 548.

All 398 selected tests passed in each configuration. Wide brushes still need faster output and physical display testing. The 24 saved Photoshop brush cases still differ.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-549) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_549.md).

## 2026-11-18 — Step 548 — Faster first draw for wide Normal brushes

The brush prepares its Normal ink once per stroke. The 5,000 px example on the 24 MP workspace reached its first AppKit draw in 505 ms, compared with 679 ms in the paired build 547 trials. All 121 tested outputs matched.

All 397 selected tests passed in each configuration. Large-tip editing still needs faster coverage work and physical display testing.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-548) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_548.md).

## 2026-11-18 — Step 547 — Reuse work during a wide brush stroke

Wide raster brushes keep their coverage between pointer samples. On the 24 MP trial, nine prefixes of a 5,000 px stroke took 4,749 ms with the complete painter and 1,872 ms with retained coverage on Apple Silicon. All 60 saved painting outputs matched.

All 395 selected tests passed in each configuration. The cost of a new wide dab and physical editing cadence remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-547) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_547.md).

## 2026-11-17 — Step 546 — Faster canvas updates

Changed pixels now go directly into the display buffer. At 12.5% zoom, Apple Silicon display conversion for the 5,000 px brush fell from 357 to 103 ms on the 24 MP test image. All 80 saved outputs match build 545 on each architecture.

All 392 selected tests passed in the three configurations. Large brushes still need faster preparation to reach the display target.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-546) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_546.md).

## 2026-11-17 — Step 545 — Faster composition under tone layers

The renderer combines a raster and eligible tone layers in one pass through its tiles. On Apple Silicon, the 5,000 px first-dab software composition fell from 1,628 to 124 ms on the 24 MP test image. The hosted AppKit first draw took 896 ms in the paired runs.

All 64 output comparisons were exact and all 390 selected tests passed in each configuration. Large-tip display cadence remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-545) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_545.md).

## 2026-11-17 — Step 544 — Faster wide brushes

The renderer prepares the brush tip once per dab. Wide brushes now start their first canvas preview from the initial pointer sample. The 24 MP hosted test measured first draw at 2,343 ms for a 5,000 px soft brush, compared with 2,442 ms in build 543.

All 64 output comparisons were exact and 388 selected tests passed in each of the three configurations. Large-tip display cadence remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-544) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_544.md).

## 2026-11-17 — Step 543: reuse gradient samples

Large gradients reuse identical colour samples, and fill rendering writes a tile at a time. On Apple Silicon the 2,048 × 2,048 Perceptual raster fell from 351 to 49 ms. All 84 test images matched build 542 byte for byte.

All 372 selected tests passed in Debug and both optimized builds. The three saved Photoshop Gradient Map differences remain.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-543) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_543.md).

## 2026-11-17 — Step 542: get the same gradient pixels on Apple Silicon and Intel

Linear and Perceptual gradients now round the nonlinear part of sRGB the same way across the two builds. All 18 Gradient Map buffers that differed in build 541 now match, and the 32 tested Brush buffers are byte-identical to the prior build.

All 370 selected tests passed. The same three RGB8 Gradient Map fixtures still differ from Photoshop by at most one RGB8 level.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-542) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_542.md).

## 2026-11-17 — Step 541: faster feedback with large brushes

The brush preview and flat compositor now write changed pixels one tile at a time. In the 24 MP hosted workspace, the 1,800 px brush showed its first preview in 489 ms, down from 802 ms. The 5,000 px brush took 2.50 seconds, down from 3.61.

All 266 selected tests passed. The compiled builds reproduced all 32 brush outputs and 144 composite buffers from build 540 on each architecture. The larger brushes still need further responsiveness work.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-541) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_541.md).

## 2026-11-17 — Step 540: get the same linear Brush pixels on Apple Silicon and Intel

A single-precision power calculation in the sRGB transfer caused six Brush cases to disagree across the two builds. The transfer now calculates that step at higher precision and rounds to Float32. All 32 tested Brush outputs agree across architectures. The compiled transfer also agrees on every nonnegative finite Float32 input, and all 251 selected tests passed.

The 5,000 px Brush still takes 3.70 seconds to draw its first preview in the 24 MP hosted test. The smaller 64 px Brush drew 119 times during two seconds of input.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-540) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_540.md).

## 2026-11-17 — Step 539: render large brush dabs faster

The 5,000 px color-dynamics test took 0.52 seconds on Apple Silicon, down from 1.99. Brush rendering now updates one tile at a time.

All 205 selected tests passed. The optimized Apple Silicon and Intel builds reproduced the same bytes for both full-size brush tests. Live editing cadence still needs measurement.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-539) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_539.md).

## 2026-11-17 — Step 538: use a 5,000 px brush

Set a primary Brush diameter up to 5,000 pixels from the native controls or API. Large strokes process small regions before committing, with the same Undo and recorded Action behavior.

All 204 selected checks passed. The optimized Apple Silicon and Intel versions rendered the same bytes for a full-size dab and the 24 earlier Brush samples. Wide strokes still need performance work.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-538) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_538.md).

## 2026-11-17 — Step 537: record Pencil strokes in Actions

The Pencil now plays back in Actions. A recorded stroke keeps the points, brush settings and destination. Auto Erase checks the first pixel in the playback document, so the same step can switch between foreground and background on different images.

All 199 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. A new 24-dab Photoshop comparison measured the Brush's edge softness across six sizes. Exact brush pixels still differ.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-537) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_537.md).

## 2026-11-17 — Step 536: Shift-click with Brush and Pencil

Paint a point, then Shift-click to draw a straight connection. The pointer shows when there's a point to connect to. One Undo removes the connection.

All 178 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The desktop and API produced the same Photato document for both tools. A Brush Action also replayed the connection. Photoshop's brush left different alpha samples in the test sheet, so exact Brush output still needs work.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-536) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_536.md).

## 2026-11-17 — Step 535: set the ordinary Brush to 10% smoothing

The Brush opens at 10% smoothing. You can still set it to 0%, and your choice follows the workspace across document tabs. Saved Actions and presets use their recorded settings.

All 167 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. For the tested corner stroke, the new default produced the same native pixels from the desktop, HTTP and recorded replay. Exact Photoshop brush pixels and physical display timing still need verification.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-535) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_535.md).

## 2026-11-17 — Step 534: start the Brush worker during input

Photato now queues work for the first mark during input. The worker starts a median 0.23 ms after input. Across two rounds of the 24-megapixel test, the median time through the first AppKit draw was 27.52 ms to 20.77 ms.

All 114 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The preview and the committed stroke matched the complete native command. Undo restored the original. Physical editing cadence and Photoshop Brush pixel comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-534) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_534.md).

## 2026-11-17 — Step 533: start the first Brush frame sooner

On a ready canvas, Photato starts preparing the first Brush mark when the input arrives. The following frames still collect every sample. In the 24-megapixel AppKit test, median time from input to preparation fell from 18.12 ms to 0.20 ms. The median time through software drawing was 29.45 ms to 29.14 ms.

All 100 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. The measured stroke matches the full native command before and after commit, with one Undo. Physical display timing and Photoshop Brush pixel comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-533) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_533.md).

## 2026-11-17 — Step 532: reuse tiles after recompositing

A small edit used to write every pixel in the composited patch back into the canvas. Photato can now reuse complete tiles and copy just the affected rows at an edge. On the 24-megapixel Brush test, p95 for installing the patch fell from 0.96 ms to 0.16 ms. The composite and preview hashes matched build 531.

All 99 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The retained Photoshop 2026 files cover 20 owned RGB32 examples. Their represented merged pixels match. The first input driver showed a longer delay before preparation. The independently scheduled test recorded a lower end-to-end p95. Physical display timing and the broader Photoshop workflows still need verification.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-532) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_532.md).

## 2026-11-17 — Step 531: find the tiles a stroke changed

An edit to one part of a large canvas used to sort tile keys for the whole image. The damage check now skips tiles that share the same pixel storage as the previous frame. In the 24-megapixel test, p95 for a single-tile damage check fell from 1.58 ms to 0.33 ms. The complete preview, reduced preview and working sample hashes matched build 530.

All 90 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The hosted AppKit tests time the application through drawing. Physical 60 fps and Photoshop comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-531) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_531.md).

## 2026-11-17 — Step 530: send ready previews straight to AppKit

When a preview is ready, Photato now asks the attached AppKit canvas to draw. On the hosted Brush test, the median wait between the preview being ready and the draw beginning fell from 6.49 ms to 1.46 ms. In the same test, input-to-draw p95 fell from 14.36 ms to 9.86 ms.

All 59 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The original 1200 × 800 fixture provides the before-and-after comparison. A separate 24 MP layered test verifies the new AppKit path and exact brush pixels. Physical display timing still needs testing.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-530) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_530.md).

## 2026-11-17 — Step 529: test a different way to store canvas previews

I tried sharing unchanged memory between brush previews on large canvases. The previews matched the old bytes, but the 24-megapixel benchmark became slower. The separate memory test also rose from about 106 MB to 199 MB with two frames retained. I kept the results and restored build 528.

A follow-up using an AppKit test window found that the Brush preview often waited around 11 ms between being ready and the draw beginning. That delay is the next place to look. The test measures AppKit callbacks. Physical display timing still needs testing.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-529) · [Measurements](../PhotoCraftSwift/docs/CANVAS_PREVIEW_EXPERIMENT_529.json).

## 2026-11-17 — Step 528: open JPEG XL still images

Photato can open JPEG XL stills through File > Open and the optional API on systems with an ImageIO reader for the format. The two lossless fixtures, one RGB8 and one RGBA16, match all 280 authored sample values. The imported image remains separate from its original file and can be saved as a native document.

ImageIO presented a two-frame test file as one image. Photato now checks the codestream before it decodes the file and rejects animations with an explicit message. JPEG XL export and wider color and HDR checks remain open. The installed Photoshop Open dialog was reached, but it did not open the fixture folder through automation.

[Workflow](../PhotoCraftSwift/docs/JPEG_XL_IMPORT.md) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-528).

## 2026-11-17 — Step 527: avoid repeat save format scans

The Save As panel and API now reuse their writable-format decisions. JPEG and OpenEXR with transparency disabled use the existing exact opacity check. Once the raster is known to be opaque, another check can use that result until an alpha edit invalidates it.

All four new tests pass. Two broader runs hit an inherited channel-separation HTTP connection error, also reproduced on build 526. That test passed with the rest of its class in isolation on both builds. The timing evidence covers opacity checks on 24 and 36 megapixel images.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-527).

## Source update — 16 November 2026, builds 525–526

Selections now retain their exact contour during ordinary painting previews. Rectangular and elliptical marquees can be moved with Space while being drawn, then resized again after Space is released. Polygon vertices no longer start a drag of the old selection.

All 86 selected tests pass in Debug, optimized Apple Silicon and translated Intel, including 15 new tests. The universal package passes its checks. Native launch and window title are verified; live editing and save/reopen remain unqualified because the automation controls stalled in macOS's file chooser. Full functionality and physical 60 fps remain open.

[Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_526.md) · [525 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-525) · [526 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-526).

<a id="dev-step-526"></a>

## 2026-11-16 — Step 526: reposition a marquee while drawing

Hold the mouse button while drawing a rectangular or elliptical selection, press Space and move it, then release Space to resize again. The draft retains its combine mode, anti-alias and feather settings. Escape, tool/focus/source changes and busy-state changes discard it. An unfinished polygon also keeps ownership of its later clicks, including clicks inside the previous selection.

The new tests cover both marquee tools and all 16 modifier combinations, final mouse-release movement, cancellation, history, Actions, archive and the existing HTTP selection.shape command. The first polygon cursor assertion confused the toolbar icon with the existing lasso cursor; that test-only correction and the interrupted broad run are retained. No production binary or prior test assertion changed for the repair.

All 86 selected tests and all 15 new tests across builds 525–526 pass in each tested configuration. The universal app launches with Photato - Untitled-1. Native automation then stalls in the system file chooser, so live editing/save/reopen/normal Quit are not marked passed. Full Photoshop cursor/default behavior, temporary Command pixel movement and off-canvas committed selection coverage remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-526) · [Workflow](../PhotoCraftSwift/docs/SELECTION_INTERACTION.md) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_526.md).

<a id="dev-step-525"></a>

## 2026-11-16 — Step 525: retain selection contours during painting

Painting previews used to rebuild the selection outline by scanning the entire dense canvas, even when coverage had not changed. The contour now scans only the selection bounds and is retained for unchanged coverage/view settings. Ordinary pixel, mask and Adjustment Brush previews keep a matching outline on screen while their next image is prepared. Changed or cancelled requests cannot publish a stale or partial contour.

For a small selection on 24/36MP canvases, the optimized contour takes about 0.041ms on Apple Silicon and 0.061ms under Intel translation. The frozen native-524 traversal, recompiled in the same test binaries, takes 217/330ms and 372/563ms. Every contour segment matches. This measures contour preparation; it is not a Photoshop comparison, whole-stroke latency or physical display frame rate.

The initial 22 focused Debug tests pass. Final combined qualification is recorded under build 526. Earlier temporary checkouts had disappeared, so the exact public source and 13 unchanged local model/fixture inputs were restored into a persistent workspace. The older dirty checkout remains untouched. All original scopes and failures remain tracked.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-525) · [Contour preparation](../PhotoCraftSwift/docs/SELECTION_CONTOURS.md).

## Source update — 2026-11-09, build 524

Selection borders support dragging and arrow keys; replacement feedback starts on press. Canvas Size retains zoom/pan. Debug and normal optimized ARM/translated Intel each pass 65 selected methods, including all 13 new methods. Universal package checks pass; live UI inspection is unavailable this session.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-524) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_524.md).

## Source update — 2026-11-09 UTC, build 523

Layer-mask and Adjustment Brush previews now retain stroke coverage. The owned model workload processes about 60 accepted previews/s; physical display FPS remains unverified. Debug 52/52 and optimized ARM/translated Intel 69/69 selected methods pass. Native mask/adjustment history, Properties, save/reopen/Quit and universal package checks pass.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-523) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_523.md).

## Source update — 9 November2026 UTC, build 522

Masked adjustment previews improve about 23× in the controlled workload. All 30 selected tests pass on optimized ARM and translated Intel, including eight methods since public 520. Actual optimized universal paint/history/Properties/save/reopen/Quit and static package checks pass. Processing remains near 27/s for masks; physical 60 fps and live Sky scrolling remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-522) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_522.md).

## Source update — 9 November 2026 UTC, build 520

Color and vibrance now works with Adjustment Brush through native painting, editable Properties, masks, history, archive, Actions 61 and the optional API. Debug and each optimized architecture pass 46 selected methods/all 12 new. Actual native save/reopen/normal Quit and universal static checks pass. Independent Photoshop output still differs; full B08/A04 and all earlier failures remain open. Next: Q03, major stillneeded.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-520) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_520.md).

## Source update — 9 November 2026 UTC, build 519

Large Sky selection/replacement now retains working-resolution masks/output and visible full-detail previews. Scrolling/zooming imagery stays inside the viewport. Legacy previews, true 100% zoom, existing View shortcuts and read-only API viewport state are tested. Current Debug passes 15 focused checks/all 9 new viewport-display methods; optimized Apple Silicon and translated Intel each pass 63/all 34 new increment methods. Universal static checks pass; actual Sky sheet verification remains open after native inspection disconnected. Full AI09 and earlier failures remain open. Next: B08, major stillneeded.

[519 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-519) · [Workflow/API](../PhotoCraftSwift/docs/LARGE_SKY_WORKSPACE.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_519.md).

## Source update — 9 November 2026 UTC, build 518

Video keyframes now support multi-selection, an immutable clipboard and atomic paste, delete, move, duplicate and interpolation edits through native controls and the optional API. All 46 selected tests and 12 new tests pass in Debug, optimized Apple Silicon and translated Intel. Actual native group editing, save/reopen and universal static checks pass. Photoshop 2026 supplied the observed menu and single-layer timing/value reference; full SP01 and earlier failures remain open. Next: AI09, major stillneeded.

[518 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-518) · [Workflow/API](../PhotoCraftSwift/docs/KEYFRAME_GROUP_EDITING.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_518.md).

## Source update — 9 November 2026 UTC, build 517

Generated-image alternatives now remain in one native layer, with a Properties thumbnail chooser, deletion, Undo/Redo and offline save/reopen. All54 selected tests and9 new tests pass in Debug, optimized Apple Silicon and translated Intel. Actual native UI and universal static checks pass. Test images are owned synthetic fixtures; no actual provider generation or Photoshop-output equality is claimed. Full AI07 and prior failures remain open. Next: SP01 timeline/video, major stillneeded.

[517 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-517) · [Workflow/API](../PhotoCraftSwift/docs/GENERATED_VARIATIONS.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_517.md).

## Source update — 9 November 2026 UTC, build 516

Editable RGB PSD/PSB artboards now retain geometry, backgrounds, presets, children, origins and scoped guides. Debug and optimized Apple Silicon pass 74/74 selected tests; translated Intel passes 73/74, with the same older nine-assertion paging failure reproduced on retained public515. All 11 new methods and exact owned Photoshop merged references pass in every configuration. Native save/reopen, Photoshop reopen and universal static checks pass. Full I04/L07, prior failures and full parity remain open.

[516 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-516) · [Workflow/API](../PhotoCraftSwift/docs/PSD_ARTBOARDS.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_516.md).

## Source update — 9 November 2026 UTC, build 515

Original artboard projects now open with editable bounds, backgrounds, presets and children. Reframing/export preserves saved source appearances. All 46 selected tests and all 10 new methods pass in Debug, optimized Apple Silicon and translated Intel. Native Properties, Cancel, history, Save As/reopen and normal Quit pass, as do universal static checks. Full I03, editable PSD/PSB artboard interchange and earlier failures remain open.

[515 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-515) · [Workflow/API](../PhotoCraftSwift/docs/PCRAFT_ARTBOARDS.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_515.md).

## Source update — 9 November 2026 UTC, build 514

Auto-Blend now keeps visible editable source layers when seamless blending is enabled and transparent-area fill is off. Photomerge also retains the photograph names. Fill adds a merged layer; translucent sources still use the documented isolation fallback.

Debug and optimized ARM pass 37/37 focused tests, including all nine new methods. Intel passes 36/37 and eight of nine new methods; its exact linear-RGB comparison remains failed. Native commit, Undo/Redo and saved PSD reopening were checked. The Intel difference is isolated to the same color-transfer behavior in the retained build 513; the stored component comparison is unchanged. The original assertion remains required. Full blending fidelity, large-photo capacity, all prior failures and Photoshop parity remain open.

[514 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-514) · [Workflow/API](../PhotoCraftSwift/docs/EDITABLE_PHOTO_BLEND.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_514.md).

## Source update — 9 November 2026 UTC, build 513

Legacy Macintosh RGB proofing is now available in the native app and API. Shared Apple RGB profiles also work for document creation and output. Native controls, cancellation, Command-Y and saved/reopened PSD components were checked.

All seven new tests pass in Debug and both optimized architectures. Broader runs pass 54/55 on Apple Silicon and 52/55 on translated Intel. The remaining Gray-profile and frozen-proof failures reproduce on the actual retained build 512 binary; they remain open. The universal package passes static checks and is unlaunched. Full color-proofing and Photoshop parity are unfinished.

[513 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-513) · [Workflow/API](../PhotoCraftSwift/docs/APPLE_RGB_PROOF.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_513.md).

## Source update — 9 November 2026 UTC, build 512

Merge Channels now works through the native Channels panel and the optional API. Assign grayscale images to RGB, CMYK, Lab or Multichannel output. The result opens as a new document; only the chosen sources close.

All 15 new tests pass in Debug and both optimized architectures. The broader run passes 68/69, with the same legacy Multichannel failure reproduced on public build 511. Actual RGB16 and Multichannel16 saves reopen correctly and match all 960 Photoshop reference component values. Full parity and the recorded cleanup work remain open.

[512 — Merge Channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-512) · [Usage/API](../PhotoCraftSwift/docs/MERGE_CHANNELS.md) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_512.md).

## Source update — 8 November 2026, build 511

Photoshop rejected our Gray32 PSD exports even though Photato could reopen them. The writer omitted HDR toning metadata for grayscale. That is fixed in the shared native and API export path.

All 32 selected tests pass in Debug and both optimized architectures. Photoshop opens all eight tested PSD/PSB compression variants. A separate Float32 merged-preview difference remains. Merge Channels reference work is recorded, but that command is still in progress.

[511 — Gray32 Photoshop file export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-511) · [Validation and remaining work](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_511.md).

## Source update — 8 November 2026, build 510

The diary now includes reviewed adjustment values, language/plugin audits and editable gradient profile conversion. The current workflow passes all14new tests in Debug and both optimized architectures, plus a native save/reopen check. The broader run has a known Intel failure, independently reproduced on public506; it remains required.

- [507 — Reviewed adjustment values](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-507)
- [508 — AI, language and plugin acceptance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-508)
- [509 — Plugin host requirements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-509)
- [510 — Editable gradient profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-510)

[Validation and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_510.md).

## Source update — 8 November 2026, build 506

Photato now has a local learned upscaling workflow. Image > Generative Upscale creates a separate 2× or 4× document using an optional BSD-licensed Real-ESRGAN model. The original stays unchanged. Native progress, cancellation and API create/cancel share the same preparation.

All 46 selected methods pass in Debug, optimized Apple Silicon and translated Intel; 19 archive-tool checks pass. The diary includes the failed compiles, Intel half-precision repair and inherited archive path-guard correction. This remains an unfinished development alpha.

- [506 — Local learned upscaling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-506)
- [Workflow and API](../PhotoCraftSwift/docs/LOCAL_SUPER_RESOLUTION.md)
- [Validation and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_506.md)

## Source update — 8 November 2026, build 505

Generated backgrounds now prepare bounded references from larger masked subjects. The image workspace also offers an explicit request to edit a reference image on eligible Apple Silicon Macs running macOS 27 or later. Ordinary editing still targets macOS 14+.

All 81 focused methods pass in Debug, optimized Apple Silicon and translated Intel, including 20 new methods from 504–505. The records include failed attempts, the unresolved native AI-sheet connection failure and the limits of the model checks.

- [504 — Background generation on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-504)
- [505 — Edit a reference image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-505)

[Source delivery and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_505.md). Standalone website promotion remains pending.

## Source update — 8 November 2026, build 503

People selection now works beyond the former small-image admission limit. Apple text-service readiness explains missing device, system, model or signed-capability requirements. The Remove tool can mark background people for review before an explicit apply.

The current source passes 114 focused methods in Debug and each optimized architecture, including all 31 new 501–503 methods. The diary records the failed attempts and the portrait-classification correction. Full Photoshop functionality and output parity remain unfinished.

- [501 — Select People on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-501)
- [502 — Report Apple text-service availability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-502)
- [503 — Review people before removal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-503)

[Source delivery, validation and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_503.md). The standalone website and canonical historical-evidence pipeline remain separately pending.

## Source update — 8 November2026

Build500 passes its42 focused Debug tests and the same42 optimized tests on Apple Silicon and translated Intel. Actual sandboxed export, Cancel/history and normal Quit checks pass. This source snapshot includes the work through500; it does not establish full Photoshop parity or a full-suite pass.

- [487 — Share the person-selection model](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-487)
- [488 — Image styles and canvas size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-488)
- [489 — Native Remove tool](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-489)
- [490 — Generated backgrounds](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-490)
- [491 — Reference images for generation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-491)
- [492 — Reviewed edit plans](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-492)
- [493 — Profile changes on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-493)
- [494 — Directory durability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-494)
- [495 — Paged Warp](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-495)
- [496 — PSD vector path semantics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-496)
- [497 — Untagged files and sandboxed copies](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-497)
- [498 — Large colour-mode files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-498)
- [499 — Paths to Illustrator](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-499)
- [500 — Repair native asset export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-500)

The detailed private attempt records remain retained. The canonical history-index and website refresh are still pending; [delivery details](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_500.md).

# Photato development diary

<!-- process-note:start -->
## Source code and compatibility testing

Photato is a native Swift image editor targeting Photoshop 2026 functionality. The open-source PhotoCraft Rust project provides inspiration and licensed implementation material. Photoshop 2026 defines the behavior we need to reproduce. Ported code keeps its MIT/Apache licensing and credits. We record the source and license of dependencies and test fixtures.

For Photoshop compatibility, we use public Adobe documentation and Photoshop’s normal interface with our own test artwork. We record controls, defaults, shortcuts and results, and examine saved files. Some compatibility facts come from installed metadata and script definitions; Adobe’s script code is not incorporated into Photato.

We port licensed PhotoCraft code where suitable and write independent Swift code for the editor, macOS interface and APIs. We have not decompiled or disassembled Photoshop executables, extracted proprietary algorithm code, or copied Adobe’s proprietary implementation into Photato.

Tests compare results with the original Rust implementation, public file specifications and Photoshop-generated test files. They cover editing, previews, cancellation, undo/redo, saving and APIs. Byte-identical results are claimed only for tested cases. Mismatches and untested behavior remain in the record, along with source/build hashes, commands, failed attempts and repairs.

This is independent implementation with black-box compatibility research. Research and implementation happen within the same project, so this is not a claim of formal clean-room separation. Observing behavior and examining saved files are part of the process; the diary does not claim that no reverse engineering of any kind occurred. The restriction on decompiling, disassembling or copying Photoshop’s proprietary implementation remains explicit.

<!-- process-note:end -->

**Release policy — updated 6 November 2026:** Photato will be a free and open-source release under MIT OR Apache-2.0, without tips, donations, in-app purchases, subscriptions or paid feature unlocks. The repository is now public at the maintainer’s request; application releases remain manually approved. Earlier entries describe the former purchase experiment as history; step237 records its removal.

<!-- current-status:start -->
<!-- current-status-step:569 -->
## Current development status — 18 November 2026

32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves.

The grayscale comparison covers the default 32-bit gray destination with relative colorimetric intent, recognized standard RGB primaries, and custom linear RGB matrix profiles whose luminance weights sum to one. Other destination profiles, intents and custom white points still use ColorSync. Eight- and sixteen-bit grayscale conversion, transparent Multiply, and whole-file identity remain open.

[Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_569.md) · [Current work order](../PhotoCraftSwift/docs/CURRENT_WORK_ORDER.md)
<!-- current-status:end -->

## The brief and the decisions that shaped the project

The original brief was to inspect PhotoCraft, plan the port, implement it module by module, and test each module. The target became Photoshop 2026 functionality in a fully native Swift application for macOS 14 and later, with a universal application for Apple Silicon and Intel. Optional Apple AI belongs behind platform and availability checks. The maintainer clarified at step335 that Rust is a source of inspiration, not a required first parity milestone. Missing Photoshop workflows determine the work, regardless of whether Rust implements them.

The maintainer then made several decisions that continue to govern development:

- Use Photoshop's interface, menu structure and factory shortcuts by default. A visible menu item does not establish that its function is implemented.
- Allow Apple's Private Cloud Compute as well as eligible on-device features, and describe which service is actually used.
- Release the work as an open-source fork with clear PhotoCraft attribution. Name the application **Photato**, and use the supplied icon.
- The earlier optional App Store tip experiment was removed at step237. The current release is free and open source, with no purchases or paid feature unlocks.
- Include a native Xcode project alongside the package-based build and test workflow.
- Maintain both the Photato API and an interface compatible with the published Adobe Photoshop API wherever that contract defines the operation. Desktop and API operations share the native engine.
- Record every development change, including failures and removals, from the beginning.
- Follow the current seven-pass order: **major quick wins, major still needed, minor quick wins, minor still needed, major cleanup, minor cleanup, final settings/checks**. UI, menus, shortcuts, APIs and focused tests stay with each delivered function. Full original acceptance still governs package closure.

These decisions were made at different points. The dated account below preserves those changes instead of rewriting the past as though the final requirements existed from day one.

## 7 October 2026

### Establishing the native application

The first audit inventoried 24 Rust crates and 626 unique source menu identifiers. The Swift project separated the editing model, imaging and PSD support, optional AI, and native application. Early implementation covered sparse raster storage, blending, documents, commands and history, basic tools, native storage, and a deliberately limited PSD reader and writer. The initial milestone recorded 40 passing tests and a universal build targeting macOS 14. It also recorded repairs to canvas redraw, preview tone mapping, imported-file protection, gesture history, and signing affected by Desktop synchronization. The initial sequence was later expanded retrospectively; it is not a recovered edit-by-edit transcript. [Initial source audit and port](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-001)

A professional-workflow plan distinguished source parity from Photoshop parity. Inspection of the source corrected several earlier descriptions of supposedly missing Rust functionality, so those implementations remained part of the porting obligation. Inspection of the running Photoshop interface then guided a native workspace with grouped tools, document tabs, options, layers, adjustments, rulers and scrollers. Unsupported tools stayed visibly unavailable. [Workflow plan](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-002), [first workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-003)

### Correcting the AI policy

An early platform policy excluded Image Playground where it would use cloud computation. At the maintainer's request, that exclusion was removed and Private Cloud Compute was re-enabled subject to Apple's actual availability checks. The UI was changed so cloud-generated results would not be described as on-device. Local prompt refinement remained a separate capability. At that checkpoint the services were unavailable or still preparing on the test machine; live generation was not claimed. [Private Cloud Compute change](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-004)

### Geometry, selections, masks and editable documents

The port gained Free Transform, image and canvas sizing, resolution handling, resampling and undoable whole-canvas geometry. Selections expanded to coverage masks, ellipses, freehand and polygon tools, combinations, inversion and feathering. Direct pixel-mask editing, independent mask transforms, density, feather, enable/link state and PSD mask interchange followed. Independent Photoshop files exposed ordering and mask details that native round trips could not reveal. [Geometry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-005), [selection coverage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-006), [independent masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-007)

PSD support expanded to compressed channels and higher bit depths. Photoshop comparisons revealed that float PSD samples require linear-light handling, leading to corrections in storage and composition. Layer groups, clipping, editable paths and vector masks followed. Further work covered editable solid fills, edge feathering, mask commands, the clipboard and more compact native raster archives. The entries preserve measured residual errors rather than calling the whole format equivalent. [High-depth PSD](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-009), [groups](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-010), [paths and vectors](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-011), [solid fills](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-012), [mask and clipboard sequence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-015), [archive changes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-018)

### Attribution, support and the Photato name

Open-source attribution, bundled licenses and optional project/support links were introduced first. The App Store requirement then changed the support design: external donation destinations were replaced with StoreKit consumable tips, the external funding template was removed, and legacy donation metadata was ignored. Simulated StoreKit tests covered purchase and transaction recovery paths, while production registration, prices and release qualification remained open. The application was renamed Photato without removing upstream PhotoCraft credit or silently renaming every internal module. [Fork and attribution](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-008), [tips and removals](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-013), [Photato branding](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-014)

### Adjustments and independent references

The adjustment sequence added manual Levels, histograms and automatic correction, Curves, Hue/Saturation, Desaturate and Color Balance. The work included editable adjustment layers, destructive preview/apply paths, masks, history and PSD records. External Photoshop-produced fixtures exposed Hue/Saturation and Colorize differences that required corrections. The diary keeps source-algorithm agreement separate from Photoshop-output agreement. [Levels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-019), [histograms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-020), [Curves](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-021), [Hue/Saturation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-022), [Color Balance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-023), [reference-driven correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-024)

## 8 October 2026

### Retouching, painting and rendering

Work continued on Hue/Saturation behavior, Threshold and Posterize. Clone Stamp gained source slots, cross-document and mask sampling, alignment and transform controls. Regional rendering and immutable preview caching supported these interactions. Expanding cropped paint targets required careful preservation of existing pixels and mask coordinates. Healing Brush, Spot Healing, patch completion, Dodge, Burn, Sponge, Blur, Sharpen, Smudge, Magic Wand and Paint Bucket were then implemented or expanded through the shared native engine. These are recorded modules with their own limits, not a declaration that every Photoshop variant of those tools is complete. [Adjustment corrections](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-025), [Clone Stamp](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-027), [regional rendering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-028), [healing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-030), [toning and focus tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-032), [wand and bucket](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-034)

### Patterns and gradients

A persistent pattern library and PAT interchange led to editable Pattern Fill layers and embedded PSD patterns. Profiling then guided CPU rendering improvements. Gradient work introduced retained stops, multiple shapes and interpolation modes, editable Gradient Fill, live and Classic Gradient tools, preset libraries, Gradient Map, and Stripes. Storage, clipboard, previews, history and PSD interchange were extended alongside the features. [Patterns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-035), [Pattern Fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-036), [rendering optimization](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-037), [gradient foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-038), [Gradient Fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-039), [tools and presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-040), [Gradient Map](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-042), [Stripes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-043)

Several subsequent milestones were research and correction rather than new tools. Photoshop-saved references were used to investigate RGB16 transparency, Smooth interpolation, neighboring stops, color conversion, stop limits, tone coordinates and Classic arithmetic. Some candidates matched bounded reference sets; remaining mismatches and unsupported Smooth behavior stayed open. This sequence is particularly important to the record: a failed hypothesis or an unresolved numerical difference must remain visible. [RGB16 transparency correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-045), [Smooth investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-046), [stop preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-048), [tone coordinates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-050), [Classic candidate](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-052)

### Recording the work and matching menus

A dedicated documentation audit introduced stable milestone identifiers, the oldest-first index, explicit retrospective corrections, preservation rules and a hashed evidence inventory. It identified overwritten early logs and refused to manufacture missing timestamps or commits. [First development-history audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-044)

Layer alignment and distribution were investigated against Photoshop and then connected to native controls. Menu alignment and factory shortcut evidence were treated separately: the default bindings were corrected from the installed factory preset, including primary and alternate shortcuts. Layer via Copy/Cut and merging/flattening followed. The requested pause was taken at version 0.2.0, with the version change distinguished from fresh application test evidence. [Layer layout](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-053), [menu alignment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-055), [factory shortcuts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-056), [Copy/Cut](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-057), [merging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-058), [version and pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-059)

### Native workspace organization

After resumption under the then-current UI-first priorities, work addressed workspace visibility, native document windows, tab dragging, the shared application frame, floating canvases, zoom entry, compact layouts, saved workspaces and editable panel groups. These were prerequisites for a usable native editor rather than evidence of complete Photoshop tool coverage. [Resumed priorities](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-060), [document windows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-061), [shared frame](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-063), [saved workspaces](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-066), [dock groups](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-067)

## 9 October 2026

### Panels and layer interactions

Panel work continued with floating hosts, tear-off, stacks, columns, and retained History and Clone Source panels. Layer workflows gained New Layer, New Group and duplication dialogs, panel commands, inline naming, delete confirmation, color labels, visibility interactions, group disclosure and active-layer reveal. Thumbnail options, mask gestures, layout repairs, absolute positions and numeric-editing lifecycle followed. The detailed entries distinguish automated checks from live checks that could not run while the Mac was locked. [Floating panels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-068), [panel columns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-071), [layer dialogs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-073), [layer menu and naming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-076), [visibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-078), [thumbnail options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-082), [mask gestures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-084), [numeric editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-087)

### Xcode and the outstanding-work inventory

A native `Photato.xcodeproj` was added beside the Swift package, with application and module targets, shared schemes, universal Release configuration, resources and the macOS 14 deployment target. Channels and component previews were developed next. At the maintainer's request, implementation paused for a comprehensive parity inventory: 105 work packages, explicit gaps, dependencies and effort estimates. The estimates were engineering judgments, not promised completion dates, and some full-equivalence requirements had no defensible ETA. [Xcode project](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-088), [Channels panel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-089), [parity inventory and estimates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-090)

### Optional APIs and the product webpage

The optional native automation API and browser client were added as separately authorized work. Native transactions, permissions, document sharing and endpoint state were part of that increment. Subsequent decisions made API coverage mandatory for new features and established the published Adobe Photoshop v2 contract as a separate compatibility target. Both interfaces were retained over one Swift engine. Local server authentication and supported operations were not represented as Adobe's identity service or complete hosted-service compatibility. [Initial API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-091), [API completion rule](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-094), [Adobe contract requirement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-095), [both APIs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-096)

The Photato product webpage was created at `nusite/index.html`, following the existing forensicintelligence.ca style and showing provenance and development status. This was a separate presentation task during a pause in native feature development. [Webpage record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-097)

## 13 October 2026

### Accessibility, channels and recorded actions

Resumed work repaired native panel menu accessibility and qualified floating-panel input. Channel research distinguished visibility from the selected editing target, leading to independent RGB visibility and API state. Component-editing references and transaction design then supported recorded Photoshop actions and component integration. Failed attempts and subsequent qualification were preserved before another requested pause. [Accessibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-098), [floating-panel input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-099), [channel behavior](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-100), [RGB visibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-101), [component research](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-102), [recorded actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-103), [pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-104)

## 19 October 2026

### Component editing and a new implementation order

The component integration resumed with native controls and both public API paths. Independent Photoshop fixtures were exercised through the shared workflow. Testing caught stale catalogue expectations and UI/context problems; repairs and repeat qualification were recorded before the requested pause. The maintainer then changed the scheduling order to major functions, minor functions, and final details. The backlog was reorganized around that order without reducing the parity requirements. [Investigation and pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-105), [component/API integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-106), [verified pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-107), [priority change](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-108), [major-workflow backlog](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-109)

### Documents, color and file preservation

The major document workflow expanded through persistence, the `.photato` extension, source-format preservation and source-format Save. Work on exact RGB32 samples, linear HDR editing, retained working profiles, Normal composition and grouped/clipped documents used independent references to distinguish actual precision fixes from unqualified rendering behavior. PSB integration and bounded PSD/PSB row and file decoding followed, then streamed output and safe saving. [Persistence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-110), [file extension](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-111), [source formats](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-112), [float samples](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-114), [working profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-116), [Normal rendering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-117), [groups and clipping](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-118), [PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-119), [streamed saving](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-122)

### History, recovery and interruption handling

Scratch-backed undo, native archive streaming and shared tile storage addressed history and memory use. Cancellable asynchronous history navigation was followed by crash recovery, background backup writing, recovery preferences, atomic persistence and source-identity checks. The purpose was to make large documents and interrupted workflows safer without silently losing content, overwriting changed originals, or publishing stale background results. [Scratch history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-123), [archive streaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-124), [asynchronous history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-126), [recovery lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-127), [preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-129), [atomic persistence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-130), [source identity](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-131)

## 20 October 2026

### Opening, closing and recovery management

Recovery discovery became independent of the original document location. Coordinated closing, background opening, persistent recent files and queued opens were added or expanded. Recovery maintenance, explicit salvage, damaged-index reset, background discovery and memory admission followed. These workflows include native and API behavior, preservation of backups, cancellation and failure cases. Automatic memory admission remains an estimate, not a claim of a complete paging system. [Recovery discovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-132), [closing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-133), [opening](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-134), [recent files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-135), [backup maintenance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-136), [salvage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-137), [background discovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-138), [memory admission](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-139)

### Saving options and TIFF interoperability

Shared native/API encoding options started with PNG and TIFF settings, then PSD/PSB compression and file-compression preferences. TIFF work addressed float preservation, byte order, channel layout and prediction, layered import, editable layered output, numeric adjustments, vector masks and global mask-display metadata. An unreliable generic descriptor conversion draft was removed from production and preserved with the conflicting reference evidence. An independent parser's limitations were also documented and handled separately; they were not used to justify weakening the application checks. [Shared encoding options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-140), [PSD/PSB compression](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-141), [file preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-142), [float TIFF](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-143), [storage options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-144), [layer import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-145), [layer output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-146), [rich records and rejected draft](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-147)

At verified checkpoint 147, the record reports 1,390 passing Debug tests and 1,390 passing Release tests, independent output inspection, universal packaging and native Release save checks on Apple Silicon and Rosetta. This is a qualified checkpoint, not a completed Photoshop clone. All major workflow gates remain open. [Checkpoint 147](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_147.json)

### JPEG work in progress at reconstruction

Milestone 148 is developing JPEG quality, format, matte and color-profile controls with shared native/API output. The recorded investigation distinguishes Adobe's published quality choices from Photato-specific options and keeps Photoshop quantization and progressive scan-count equivalence open. At this diary snapshot, the observed focused attempts include a compiler failure followed by a run with 47 tests and six failures. The latter exposed restart-marker handling and an incorrect assumption that the platform always embeds sRGB ICC data. Those are findings under repair, not a successful release claim. Consult the running entry for subsequent results. [Current JPEG entry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-148)

## Changes of direction and removals

The diary records removal as deliberately as addition. Important examples include removing the earlier Private Cloud Compute exclusion; replacing external donation integration with StoreKit and deleting the funding template; correcting menu and shortcut defaults from factory evidence; removing stale format metadata where edits invalidate it; and withdrawing the unqualified TIFF descriptor-conversion draft from production. Rejected experiments remain evidence even when they do not become application code. [AI policy](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-004), [support replacement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-013), [shortcuts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-056), [metadata handling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-026), [withdrawn draft](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-147)

## How the diary stays current

Every meaningful addition, modification, deletion, rename, rollback or replacement must be recorded as work proceeds. Related edits may share an entry, but the entry must identify what changed, the affected paths or modules, why it changed, its user-visible or API effect, and how it was checked. A removal must name what was removed and whether anything replaces it. Investigation, failed tests, rejected approaches, repairs and remaining gaps belong in the same record; a final successful test count cannot replace them.

The detailed entry is written in [DEVLOG](../PhotoCraftSwift/docs/DEVLOG.md) under a stable milestone anchor. Unique run folders preserve before/after identities and test evidence. At a completed checkpoint, this readable diary receives the new chronology and any material change to the narrative. The [evidence inventory](../PhotoCraftSwift/docs/DEVELOPMENT_HISTORY.json) connects the records to surviving files. These obligations are part of [the repository instructions](../PhotoCraftSwift/AGENTS.md) and [the contribution requirements](../PhotoCraftSwift/CONTRIBUTING.md#development-record).

The original extracted Rust snapshot has no preserved upstream Git history, and some early logs were overwritten. The surviving record therefore cannot prove every historical keystroke or deleted intermediate file. Missing detail stays unknown. Neither this reconstruction nor the evidence audit creates an initial commit, recovers absent files, or certifies Photoshop parity.

### JPEG checkpoint verified after the reconstruction

**Update recorded 20 October 2026 after checkpoint148.** The failures above were retained and repaired: Swift matte conversion was disambiguated, nonzero JPEG restart intervals were supported, explicit ICC insertion/removal was added, and an invalid transparent ordinary-save test was corrected without relaxing the application guard. Native Save/Copy, Photato output and Adobe-defined JPEG job quality choices now share the encoder. All1,398 Debug and1,398 Release tests pass, with independent libjpeg-turbo coefficient/sample checks, universal packaging and public Release saves on Apple Silicon/Rosetta. Default JPEG outputs and161 retained prior exports remain byte-identical to147. Five live Photoshop references establish that quality8 quantization/chroma sampling and progressive schedules still differ. The original Photoshop Untitled-1 was restored. All major gates stay open. [Verified checkpoint148](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_148.json), [detailed repairs and live evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-148)

### Reading original PhotoCraft containers in Swift

Step149 adds the container groundwork for editable `.pcraft` migration: ZIP framing, Zstandard entropy decoding and BLAKE3 content verification. Procedural fixtures generated by the original Rust source cover 8-, 16- and 32-bit documents with layers and masks. The decoder verifies 42 tile addresses and 42 blob streams; an independent Zstandard encoder supplies 48 further cases, with official hash vectors and malformed-input tests. A repeat using the original dependency lock produces identical fixture bytes.

The first Swift compile failed on missing error propagation in ZIP checks. A later focused run exposed an invalid hand-built Huffman fixture; the external decoder rejected it too. Both failures remain recorded, and the repaired fixture retains its invalid predecessor as a rejection case. Final qualification passes 1,408 Debug and 1,408 Release tests, universal packaging and matching optimized decoder probes on Apple Silicon and Intel under Rosetta. Existing production modules were retained; seven internal decoder modules, one test module and attributed fixtures were added. Notices and the development records were updated.

This completes a tested dependency, not editable project import. Manifest mapping, directory bundles, desktop/API integration and full migration remain open under major item I03. No new user-facing command or API capability is advertised. The installed app and user documents/settings remain preserved. [Container foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-149), [checkpoint149](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_149.json)

### Preserving the complete source project graph before native mapping

Step150 found that direct import would lose source semantics: separate pixel/transparency/position locks, unbounded raster defaults, rich text, Smart Objects and other document features are not fully represented by the native model. The increment therefore adds an internal graph and payload reader, keeping original JSON and exact numeric tokens rather than prematurely converting those features. Known source surfaces retain signed tile positions, encoded defaults and sample bytes; known blob references are verified. Guarded directory reads complement ZIP input, and linked external Smart Object files are never opened.

Three rich fixtures use the original Rust test generator, extended with layer comps, video defaults and large IDs. The first caller asserted full equality and failed because the source loader intentionally remaps extreme IDs. A second caller and manifest comparison establish that only identities and comp links change. All48 source surfaces and222 stored payloads receive independent ZIP/JSON/zstd inventory checks. Intel qualification initially fails because SwiftPM discovers tests in an arm64 process; explicitly running the existing x86_64 bundle under Rosetta repairs the harness without source changes. Focused tests pass, then a source review adds the maximum-depth empty-group boundary regression before the final freeze. Final qualification passes1,422 Debug and1,422 Release tests,24 focused tests under Rosetta and universal package checks;692 prior output/reference files remain unchanged.

Three production modules, one test module and five attributed fixture files are added; prior application/Core/AI/API/menu sources are retained. No functionality is removed, no new public import capability is advertised, and all major gates remain open. Next is native partial-lock behavior and the editable adapter with matching UI/API/history/persistence tests. [Project reader record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-150), [checkpoint150](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_150.json)

### Separating Photoshop's protection settings

Step151 verified the lock behavior on a disposable procedural document in Photoshop2026.
Transparency, Image, Position, Prevent auto-nest and All produce distinct stored flags; All
uses a high bit that the old native writer omits. A fully locked layer can still be renamed.
Image forces Transparency checked, and the Command-/ shortcut differs from clearing All
inside the dialog. Independent Python PSD/PackBits decoding checks nine saved states,
including a black fill that preserves every alpha byte. The user's original document remains
untouched. An initial parser offset mistake and custom-dialog accessibility failures are
recorded alongside successful repairs. The first Intel build-tests attempt omitted
testable imports in Release; a retained retry adds the compiler flag without source changes.

The native changes add isolated value, PSD record and Adobe field parsers, three test modules
and eleven fixture/provenance files. The current official Adobe contract matches the pinned
version and confirms contextual omitted/null/empty protection semantics. These modules remain
inactive: changing import interpretation before all command guards migrate could expose
protected content to unintended editing. Model/archive migration, painting, groups/masks,
desktop controls and both APIs are still required together. No existing functionality is
removed or replaced, and no new executable API capability is claimed.

All10 focused,1,432 Debug,1,432 Release and10 Rosetta-focused tests pass, as do universal package
checks. All1,109 previous inputs and692 previous exported/reference files remain unchanged.
Seventeen files are added. Installed117 and user settings remain preserved. The checkpoint
records the six-part activation plan; all major gates remain open.
[Protection record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-151), [checkpoint151](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_151.json)

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-06.md)
