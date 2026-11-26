[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-08.md) · [Next page](part-06.md)

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
<!-- current-status-step:745 -->
## Current development status — 25 November 2026

Vanishing Point Brush and Stamp can follow linked faces, respect a perspective Marquee and draw straight strokes with Shift. The desktop and Photato API share rendering and Undo. Native tests verify cursor feedback and the straight-stroke path. Exact Photoshop stroke pixels remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-745) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_745.md).

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

## 2026-10-20 — Step152: protection reaches editing and both APIs

The previous isolated protection model now governs actual native edits and file persistence. Painting preserves the existing alpha stencil; Photoshop’s explicit selected Clear removes pixels. Image and position locks block their respective operations, while full-lock Rename and grouping follow the observed reference. The native dialog, layer buttons, shortcut and both API paths share those transactions. Version12 prevents older readers from silently losing partial protection; compatible existing files retain their prior version.

The first two compilations exposed test inference and initialization errors. Full01 later found94 failed assertions, mostly90 repetitions of the old TIFF partial-to-full collapse. An independent byte inventory proved all30 TIFF fixtures contain transparency-only protection. Focused06 also exposed a known unsupported little-endian opaque metadata block; the test now distinguishes that limitation from protection-only output. Later review also corrected API-only flag transitions and a reproduced protected-Fill integer quantization defect; both interrupted validations and the failing regression are preserved. Live testing then exposed initial checkbox enablement overridden during SwiftUI installation; a hosted-control regression reproduced five failures before the environment-state fix. Final59 focused,1,442 Debug,1,442 Release and20 Rosetta tests pass, with universal packaging and an owned native UI probe. This is bounded integration, not complete Photoshop parity; all major gates remain open.

[Runtime development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-152), [checkpoint152](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_152.json)

Step153 completes the first editable original-project migration subset. Source-generated RGB 8/16/32 fixtures retain raster/group/mask/path/selection/protection data through native Open, API editing and Photato persistence. Empty-selection and file-registration regressions were reproduced and repaired; all 1,455 Debug/Release tests,13 Rosetta cases,universal packaging and an owned live workflow pass. Rich source features and all major gates remain open. See [the detailed step153 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-153).

Step154 adds independent source/Photoshop rendering comparisons and repairs off-canvas raster-mask edge handling. The first broad cropped-mask hypothesis was disproved by controls; the final change follows the measured layer-boundary distinction. All 1,460 Debug/Release tests, 14 Rosetta cases and native/UI/API/package checks pass. Gaussian/vector/full byte parity remains open. See [step154](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-154).

## 26 October 2026

Step155 resumes the feather experiment begun on20October. Controlled identical-byte tests identify a filesystem visibility defect behind misleading Photoshop import errors. The first core repair passes while end-to-end tests expose AppKit staging as a second boundary; the final change carries destination visibility through both. All1,471 Debug/Release,33 focused and22 Rosetta tests pass, and direct Photoshop Open accepts native UI and generated outputs without byte changes. The atlas independently records16 radii, with exploratory exact fits at4/5/10; general feather parity remains unfinished. Historical pauses, failed tests/harnesses and both current-source builds are preserved. See [step155](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-155).

### 26 October: major features before numerical refinement

Step156 captures 48 independent transparent feather controls, but fractional radii invalidate the first simple kernel hypothesis. The maintainer asks to prioritize missing major functionality. Research and reference files are preserved; no feather algorithm is changed. [Deferred research](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-156)

Step157 adds a shared Swift raster-filter workflow: Gaussian/Box/Motion Blur, Unsharp Mask, High Pass, Add Noise, Mosaic and Average. Native preview sheets, Cancel/OK, selection and locks, one undoable edit, existing file persistence, the Photato command and both resource-job interfaces are integrated together. All59 focused Debug and1,483 full Release tests pass, along with24 functional cases on arm64 and x86_64 under Rosetta. The universal macOS 14+ candidate and live UI checks verify; installed117 remains unchanged. Failed fixture/old synchronous-test assumptions and outdated API-count assertions are retained with their repairs. Exact Photoshop filter pixels and Smart Filters remain open. [Filter workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-157)

## Complete chronological index

Every numbered milestone in the source diary at this reconstruction appears below. The link opens the full account of its changes, failures, tests and remaining work. An index entry is a record of activity; research and pause entries are not completed features.

| Date | Milestone | Recorded development |
|---|---:|---|
| 2026-10-07 | 001 | [native Swift migration milestone 1](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-001) |
| 2026-10-07 | 002 | [ordered parity and professional workflow gates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-002) |
| 2026-10-07 | 003 | [Photoshop 2026 workspace replication](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-003) |
| 2026-10-07 | 004 | [Private Cloud Compute re-enabled](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-004) |
| 2026-10-07 | 005 | [native geometry module](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-005) |
| 2026-10-07 | 006 | [coverage selections and direct mask editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-006) |
| 2026-10-07 | 007 | [independent layer masks and PSD interoperability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-007) |
| 2026-10-07 | 008 | [open-source fork and optional support](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-008) |
| 2026-10-07 | 009 | [compressed and high-depth PSD interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-009) |
| 2026-10-07 | 010 | [native layer groups and clipping masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-010) |
| 2026-10-07 | 011 | [native paths and vector masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-011) |
| 2026-10-07 | 012 | [editable PSD solid fills and exactness measurements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-012) |
| 2026-10-07 | 013 | [native App Store tips](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-013) |
| 2026-10-07 | 014 | [Photato branding](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-014) |
| 2026-10-07 | 015 | [feathered pixel masks at canvas boundaries](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-015) |
| 2026-10-07 | 016 | [native mask commands and isolated vector-alpha diagnostics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-016) |
| 2026-10-07 | 017 | [native image and layer clipboard](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-017) |
| 2026-10-07 | 018 | [compact raster archives and faster pixel packing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-018) |
| 2026-10-07 | 019 | [manual RGB Levels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-019) |
| 2026-10-07 | 020 | [Levels histograms, presets and automatic correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-020) |
| 2026-10-07 | 021 | [RGB Curves editing and interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-021) |
| 2026-10-07 | 022 | [Hue/Saturation, color ranges and Desaturate](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-022) |
| 2026-10-07 | 023 | [Color Balance workflow and PSD storage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-023) |
| 2026-10-07 | 024 | [real Hue/Saturation PSD references and Colorize correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-024) |
| 2026-10-08 | 025 | [Hue/Saturation range transfer correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-025) |
| 2026-10-08 | 026 | [Threshold and Posterize](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-026) |
| 2026-10-08 | 027 | [native Clone Stamp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-027) |
| 2026-10-08 | 028 | [regional composition and immutable preview cache](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-028) |
| 2026-10-08 | 029 | [expandable Clone Stamp targets and mask sources](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-029) |
| 2026-10-08 | 030 | [sampled Healing Brush in native Swift](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-030) |
| 2026-10-08 | 031 | [automatic Spot Healing and native patch completion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-031) |
| 2026-10-08 | 032 | [Dodge, Burn and Sponge](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-032) |
| 2026-10-08 | 033 | [Blur, Sharpen and Smudge](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-033) |
| 2026-10-08 | 034 | [Magic Wand and foreground Paint Bucket](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-034) |
| 2026-10-08 | 035 | [native patterns and PAT interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-035) |
| 2026-10-08 | 036 | [editable Pattern Fill layers and embedded PSD patterns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-036) |
| 2026-10-08 | 037 | [exact CPU rendering and Pattern Fill picking optimizations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-037) |
| 2026-10-08 | 038 | [Gradient engine and preset foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-038) |
| 2026-10-08 | 039 | [Editable Gradient Fill and PSD merged transparency](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-039) |
| 2026-10-08 | 040 | [native live and Classic Gradient tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-040) |
| 2026-10-08 | 041 | [persistent native gradient preset library](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-041) |
| 2026-10-08 | 042 | [native Gradient Map and Photoshop 2026 reference acquisition](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-042) |
| 2026-10-08 | 043 | [Stripes gradients and Photoshop depth/import compatibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-043) |
| 2026-10-08 | 044 | [development record audit and documentation discipline](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-044) |
| 2026-10-08 | 045 | [RGB16 merged transparency correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-045) |
| 2026-10-08 | 046 | [Smooth gradient reference acquisition and analysis](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-046) |
| 2026-10-08 | 047 | [Smooth neighboring-stop investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-047) |
| 2026-10-08 | 048 | [Gradient Map stop preservation and Smooth color probes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-048) |
| 2026-10-08 | 049 | [Bounded Smooth color-conversion references](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-049) |
| 2026-10-08 | 050 | [Native RGB16 Gradient Map tone coordinates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-050) |
| 2026-10-08 | 051 | [Classic gradient lookup investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-051) |
| 2026-10-08 | 052 | [Classic native arithmetic candidate](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-052) |
| 2026-10-08 | 053 | [Layer alignment and distribution reference qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-053) |
| 2026-10-08 | 054 | [Native layer layout commands and controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-054) |
| 2026-10-08 | 055 | [Photoshop 2026 menu structure alignment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-055) |
| 2026-10-08 | 056 | [Photoshop factory menu and shortcut defaults](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-056) |
| 2026-10-08 | 057 | [Layer via Copy and Cut](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-057) |
| 2026-10-08 | 058 | [Layer merging and flattening](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-058) |
| 2026-10-08 | 059 | [Minor version 0.2.0 and requested pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-059) |
| 2026-10-08 | 060 | [Workspace visibility and resumed UI priority](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-060) |
| 2026-10-08 | 061 | [Native document windows and Window menu](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-061) |
| 2026-10-08 | 062 | [Native tab drag and drop](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-062) |
| 2026-10-08 | 063 | [Shared application frame and floating canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-063) |
| 2026-10-08 | 064 | [Native viewport zoom and percentage entry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-064) |
| 2026-10-08 | 065 | [Compact workspace layout](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-065) |
| 2026-10-08 | 066 | [Shared saved workspaces](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-066) |
| 2026-10-08 | 067 | [Editable panel dock groups](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-067) |
| 2026-10-09 | 068 | [Native floating panel hosts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-068) |
| 2026-10-09 | 069 | [Native panel tear-off](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-069) |
| 2026-10-09 | 070 | [Native floating panel stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-070) |
| 2026-10-09 | 071 | [Native dock columns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-071) |
| 2026-10-09 | 072 | [Retained History and Clone Source panels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-072) |
| 2026-10-09 | 073 | [Native New Layer dialog](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-073) |
| 2026-10-09 | 074 | [Native New Group workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-074) |
| 2026-10-09 | 075 | [Native Duplicate Layer and Group workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-075) |
| 2026-10-09 | 076 | [Layers panel commands and inline renaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-076) |
| 2026-10-09 | 077 | [Layer text editing and delete confirmation UX](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-077) |
| 2026-10-09 | 078 | [Layer color labels and visibility workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-078) |
| 2026-10-09 | 079 | [Native Layers eye-column dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-079) |
| 2026-10-09 | 080 | [Group disclosure and collapse-all view state](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-080) |
| 2026-10-09 | 081 | [Active-layer reveal and minimal scrolling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-081) |
| 2026-10-09 | 082 | [Native Layers Panel Options and thumbnails](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-082) |
| 2026-10-09 | 083 | [Thumbnail coverage and mask preview geometry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-083) |
| 2026-10-09 | 084 | [Mask-thumbnail gestures and mask canvas views](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-084) |
| 2026-10-09 | 085 | [Workspace layout lifecycle investigation and reveal repair](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-085) |
| 2026-10-09 | 086 | [Compact field layout and absolute position editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-086) |
| 2026-10-09 | 087 | [Native numeric editing lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-087) |
| 2026-10-09 | 088 | [Native Xcode application project](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-088) |
| 2026-10-09 | 089 | [Channels panel and component previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-089) |
| 2026-10-09 | 090 | [User-requested pause, comprehensive parity inventory and estimates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-090) |
| 2026-10-09 | 091 | [Optional native automation API and browser client](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-091) |
| 2026-10-09 | 092 | [Sheet lifecycle and panel organization validation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-092) |
| 2026-10-09 | 093 | [User-requested pause after verified current increment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-093) |
| 2026-10-09 | 094 | [Require API coverage with every new capability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-094) |
| 2026-10-09 | 095 | [Published Adobe Photoshop API v2 compatibility requirement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-095) |
| 2026-10-09 | 096 | [Maintain Photato and Adobe-compatible APIs together](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-096) |
| 2026-10-09 | 097 | [Photato product webpage and public provenance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-097) |
| 2026-10-13 | 098 | [Resumed native panel menu accessibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-098) |
| 2026-10-13 | 099 | [Floating panel input qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-099) |
| 2026-10-13 | 100 | [Channel interaction reference qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-100) |
| 2026-10-13 | 101 | [RGB channel visibility and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-101) |
| 2026-10-13 | 102 | [Component editing reference and transaction design](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-102) |
| 2026-10-13 | 103 | [Recorded Photoshop actions and component integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-103) |
| 2026-10-13 | 104 | [Verified pause after latest debugging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-104) |
| 2026-10-19 | 105 | [Component integration investigation and verified pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-105) |
| 2026-10-19 | 106 | [Native component editing and public API integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-106) |
| 2026-10-19 | 107 | [Verified pause after component and API debugging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-107) |
| 2026-10-19 | 108 | [Major-function-first completion order](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-108) |
| 2026-10-19 | 109 | [Major-function backlog and native document workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-109) |
| 2026-10-19 | 110 | [Document persistence workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-110) |
| 2026-10-19 | 111 | [Native .photato file extension](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-111) |
| 2026-10-19 | 112 | [Source-format preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-112) |
| 2026-10-19 | 113 | [Source-format Save workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-113) |
| 2026-10-19 | 114 | [Exact RGB32 sample preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-114) |
| 2026-10-19 | 115 | [Direct linear HDR editing and composite qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-115) |
| 2026-10-19 | 116 | [Retained working colour profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-116) |
| 2026-10-19 | 117 | [RGB32 Normal rendering and PSD merged output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-117) |
| 2026-10-19 | 118 | [RGB32 grouped and clipped document qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-118) |
| 2026-10-19 | 119 | [PSB document-format integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-119) |
| 2026-10-19 | 120 | [bounded PSD/PSB row decoding](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-120) |
| 2026-10-19 | 121 | [bounded PSD/PSB file input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-121) |
| 2026-10-19 | 122 | [streamed PSD/PSB output and safe saving](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-122) |
| 2026-10-19 | 123 | [scratch-backed undo history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-123) |
| 2026-10-19 | 124 | [native archive streaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-124) |
| 2026-10-19 | 125 | [shared tile storage during history restoration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-125) |
| 2026-10-19 | 126 | [cancellable asynchronous history navigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-126) |
| 2026-10-19 | 127 | [crash recovery lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-127) |
| 2026-10-19 | 128 | [background recovery writing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-128) |
| 2026-10-19 | 129 | [recovery preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-129) |
| 2026-10-19 | 130 | [atomic persistence and interruption handling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-130) |
| 2026-10-19 | 131 | [recovery source identity](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-131) |
| 2026-10-20 | 132 | [independent recovery discovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-132) |
| 2026-10-20 | 133 | [coordinated document closing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-133) |
| 2026-10-20 | 134 | [format-aware background document opening](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-134) |
| 2026-10-20 | 135 | [persistent recent files and queued document opens](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-135) |
| 2026-10-20 | 136 | [recovery backup review and maintenance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-136) |
| 2026-10-20 | 137 | [explicit recovery salvage and index reset](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-137) |
| 2026-10-20 | 138 | [background startup recovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-138) |
| 2026-10-20 | 139 | [recovery memory admission](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-139) |
| 2026-10-20 | 140 | [shared format-specific save and export options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-140) |
| 2026-10-20 | 141 | [PSD and PSB compression](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-141) |
| 2026-10-20 | 142 | [Photoshop file compression preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-142) |
| 2026-10-20 | 143 | [TIFF floating-point preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-143) |
| 2026-10-20 | 144 | [TIFF storage options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-144) |
| 2026-10-20 | 145 | [Layered TIFF interoperability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-145) |
| 2026-10-20 | 146 | [Editable layered TIFF output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-146) |
| 2026-10-20 | 147 | [TIFF rich records and global mask metadata](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-147) |
| 2026-10-20 | 148 | [JPEG native and API save controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-148) |
| 2026-10-20 | 149 | [Original PhotoCraft container foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-149) |
| 2026-10-20 | 150 | [Original PhotoCraft project graph and payload reader](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-150) |
| 2026-10-20 | 151 | [Layer protection references and model](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-151) |
| 2026-10-20 | 152 | [Layer protection runtime integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-152) |
| 2026-10-20 | 153 | [Editable original PhotoCraft project adapter](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-153) |
| 2026-10-20 | 154 | [Source comparison and off-canvas mask correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-154) |
| 2026-10-26 | 155 | [File visibility repair and feather reference measurements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-155) |
| 2026-10-26 | 156 | [Feather research deferred for major functions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-156) |
| 2026-10-26 | 157 | [Native raster-filter workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-157) |
| 2026-10-26 | 158 | [Editable layer styles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-158) |
| 2026-10-26 | 159 | [Automatic subject selection and background removal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-159) |
| 2026-10-26 | 160 | [Embedded Smart Object workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-160) |
| 2026-10-26 | 161 | [Editable Smart Filter stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-161) |
| 2026-10-26 | 162 | [Native text editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-162) |
| 2026-10-26 | 163 | [Classic adjustment workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-163) |
| 2026-10-26 | 164 | [Color Lookup workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-164) |
| 2026-10-26 | 165 | [Native Liquify workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-165) |
| 2026-10-26 | 166 | [Native Select and Mask workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-166) |
| 2026-10-26 | 167 | [Alpha channels and Quick Mask](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-167) |
| 2026-10-26 | 168 | [Content-Aware Fill workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-168) |
| 2026-10-26 | 169 | [Content-Aware Scale](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-169) |
| 2026-10-26 | 170 | [Crop and content-aware edges](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-170) |
| 2026-10-26 | 171 | [Native retouching tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-171) |
| 2026-10-26 | 172 | [Camera Raw Filter](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-172) |
| 2026-10-26 | 173 | [Sensor RAW development](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-173) |
| 2026-10-26 | 174 | [Photo blending and focus stacking](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-174) |
| 2026-10-26 | 175 | [Native Auto-Align Layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-175) |
| 2026-10-26 | 176 | [Native Photomerge workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-176) |
| 2026-10-26 | 177 | [Native HDR merge workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-177) |
| 2026-10-26 | 178 | [Native editable Smart Object image stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-178) |
| 2026-10-26 | 179 | [Native Warp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-179) |
| 2026-10-27 | 180 | [Native Puppet Warp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-180) |
| 2026-10-27 | 181 | [Native Perspective Warp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-181) |
| 2026-10-27 | 182 | [Native Actions and Batch workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-182) |
| 2026-10-27 | 183 | [Native Artboards workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-183) |
| 2026-10-27 | 184 | [Native Frames workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-184) |
| 2026-10-27 | 185 | [Native Blur Gallery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-185) |
| 2026-10-27 | 186 | [Native Lens Correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-186) |
| 2026-10-27 | 187 | [Native Adaptive Wide Angle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-187) |
| 2026-10-27 | 188 | [Native Vanishing Point](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-188) |
| 2026-10-27 | 189 | [Native Brush Settings and presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-189) |
| 2026-10-27 | 190 | [Native painting and eraser tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-190) |
| 2026-10-27 | 191 | [Native Adjustment Brush](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-191) |
| 2026-10-27 | 192 | [Native selection tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-192) |
| 2026-10-27 | 193 | [Native Sky Selection and Sky Replacement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-193) |
| 2026-10-27 | 194 | [Native Focus Area](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-194) |
| 2026-10-27 | 195 | [Native Mask All Objects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-195) |
| 2026-10-27 | 196 | [Native Object Finder](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-196) |
| 2026-10-27 | 197 | [Native Select People](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-197) |
| 2026-10-27 | 198 | [People feature segmentation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-198) |
| 2026-10-27 | 199 | [Native live shapes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-199) |
| 2026-10-27 | 200 | [Native Pen and Paths](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-200) |
| 2026-10-27 | 201 | [Native advanced typography](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-201) |
| 2026-10-27 | 202 | [Editable shaped text](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-202) |
| 2026-10-27 | 203 | [Native Filter Gallery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-203) |
| 2026-10-27 | 204 | [Pause and current progress dashboard](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-204) |
| 2026-10-27 | 205 | [Photo detail investigation and requested pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-205) |
| 2026-10-27 | 206 | [Native photo detail workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-206) |
| 2026-10-27 | 207 | [Native Lens Blur](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-207) |
| 2026-10-27 | 208 | [Document title and canvas containment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-208) |
| 2026-10-27 | 209 | [Photato identity cleanup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-209) |
| 2026-10-27 | 210 | [Website developer diary and source link](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-210) |
| 2026-10-27 | 211 | [Private GitHub development build](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-211) |
| 2026-10-27 | 212 | [Native distortion workflows and window-build handoff](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-212) |
| 2026-10-27 | 213 | [Native Pixelate workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-213) |
| 2026-10-27 | 214 | [Native Stylize workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-214) |
| 2026-10-27 | 215 | [Native procedural Render filters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-215) |
| 2026-10-27 | 216 | [Native Flame, Tree and Picture Frame](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-216) |
| 2026-10-27 | 217 | [Native Other and Video filter workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-217) |
| 2026-10-27 | 218 | [Native Blur, Noise and Sharpen workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-218) |
| 2026-10-27 | 219 | [Classic tone and color adjustments](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-219) |
| 2026-10-27 | 220 | [Document color modes — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-220) |
| 2026-10-28 | 221 | [Native Indexed Color and Bitmap — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-221) |
| 2026-10-28 | 222 | [Duotone and Multichannel — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-222) |
| 2026-10-28 | 223 | [Native proofing and print workflows — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-223) |
| 2026-10-28 | 224 | [Native printing and hard proofs — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-224) |
| 2026-10-28 | 225 | [Native color profile workflows — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-225) |
| 2026-10-28 | 226 | [Persistent working color settings — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-226) |
| 2026-10-28 | 227 | [Opening and paste color policies, working proof](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-227) |
| 2026-10-28 | 228 | [A portable, single-file developer diary](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-228) |
| 2026-10-28 | 229 | [Editable frame animation and Timeline](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-229) |
| 2026-10-28 | 230 | [Native animated GIF interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-230) |
| 2026-10-28 | 231 | [Native video layers and PNG sequences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-231) |
| 2026-10-28 | 232 | [Native image-sequence export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-232) |
| 2026-10-28 | 233 | [Native movie import and video-layer placement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-233) |
| 2026-10-28 | 234 | [Editable video Timeline keyframes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-234) |
| 2026-10-28 | 235 | [Video editing investigation — implementation pending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-235) |
| 2026-10-28 | 236 | [A master homepage for Forensic Intelligence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-236) |
| 2026-10-28 | 237 | [A pure FOSS release, without purchases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-237) |
| 2026-10-28 | 238 | [Video arrangement and precise splitting](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-238) |
| 2026-10-28 | 239 | [Graphical Timeline and editable transitions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-239) |
| 2026-10-28 | 240 | [Native Timeline audio](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-240) |
| 2026-10-28 | 241 | [Native Render Video](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-241) |
| 2026-10-28 | 242 | [Timeline work areas and onion-skin previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-242) |
| 2026-10-28 | 243 | [Universal Timeline preview qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-243) |
| 2026-10-29 | 244 | [Timeline work-area trimming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-244) |
| 2026-10-29 | 245 | [Frame-to-video Timeline conversion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-245) |
| 2026-10-29 | 246 | [Video-to-frame conversion and original recovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-246) |
| 2026-10-29 | 247 | [Variables and data-driven graphics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-247) |
| 2026-10-29 | 248 | [Contact Sheet II](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-248) |
| 2026-10-29 | 249 | [Crop and Straighten Photos](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-249) |
| 2026-10-29 | 250 | [Image Processor](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-250) |
| 2026-10-29 | 251 | [Video Frames to Layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-251) |
| 2026-10-29 | 252 | [Native PDF page import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-252) |
| 2026-10-29 | 253 | [Embedded PDF images](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-253) |
| 2026-10-29 | 254 | [Stable source publication](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-254) |
| 2026-10-29 | 255 | [Native PDF Smart Object placement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-255) |
| 2026-10-29 | 256 | [Publish qualified PDF Smart Object source](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-256) |
| 2026-10-29 | 257 | [General embedded placement workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-257) |
| 2026-10-29 | 258 | [Publish qualified embedded placement source](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-258) |
| 2026-10-29 | 259 | [PDF source editing and completion dashboard repair](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-259) |
| 2026-10-29 | 260 | [Retained PDF page PSD/PSB interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-260) |
| 2026-10-29 | 261 | [Linked-source work, preserved and parked](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-261) |
| 2026-10-29 | 262 | [Interactive painting responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-262) |
| 2026-10-29 | 263 | [Interactive retouching responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-263) |
| 2026-10-29 | 264 | [Large-image toning responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-264) |
| 2026-10-29 | 265 | [Retained Focus-tool feedback](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-265) |
| 2026-10-29 | 266 | [Faster stroke startup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-266) |
| 2026-10-29 | 267 | [Prepare the canvas at the right zoom](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-267) |
| 2026-10-29 | 268 | [Redraw only changing feedback](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-268) |
| 2026-10-29 | 269 | [Measure native editing feedback](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-269) |
| 2026-10-30 | 270 | [Present accepted editing previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-270) |
| 2026-10-30 | 271 | [Use the current preview and restore tool focus](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-271) |
| 2026-10-30 | 272 | [Layer opacity slider](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-272) |
| 2026-10-30 | 273 | [Held-pointer brush smoothing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-273) |
| 2026-10-30 | 274 | [Brush release responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-274) |
| 2026-10-30 | 275 | [Retouch release responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-275) |
| 2026-10-30 | 276 | [Stable preview pause and retouch automation handoff](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-276) |
| 2026-10-30 | 277 | [Semantic retouch Actions and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-277) |
| 2026-10-30 | 278 | [Large-document architecture](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-278) |
| 2026-10-30 | 279 | [Disk-backed dense raster input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-279) |
| 2026-10-30 | 280 | [Paged native persistence and large file IO](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-280) |
| 2026-10-30 | 281 | [Publish qualified native source280](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-281) |
| 2026-10-30 | 282 | [Indexed native archives](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-282) |
| 2026-10-30 | 283 | [Modifier-aware tool cursors](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-283) |
| 2026-10-30 | 284 | [Paged runtime tile index (under test)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-284) |
| 2026-10-30 | 285 | [Persistent native tile ordinal reuse (software qualified; UI pending)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-285) |
| 2026-10-30 | 286 | [Large PSD/PSB file workflows (software qualified; UI pending)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-286) |
| 2026-10-30 | 287 | [Paged document geometry (software qualified; native acceptance pending)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-287) |
| 2026-10-31 | 288 | [Paged selections and bounded channel views (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-288) |
| 2026-10-31 | 289 | [Publish qualified source288](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-289) |
| 2026-10-31 | 290 | [Paged layer-stack composition (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-290) |
| 2026-10-31 | 291 | [Paged vector-mask preparation (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-291) |
| 2026-10-31 | 292 | [Paged basic raster filters (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-292) |
| 2026-10-31 | 293 | [Paged Smart Filter workflows (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-293) |
| 2026-10-31 | 294 | [Private qualified-source backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-294) |
| 2026-10-31 | 295 | [Streamed Smart Filter cache interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-295) |
| 2026-10-31 | 296 | [Large isolated resource jobs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-296) |
| 2026-10-31 | 297 | [Modern adjustment layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-297) |
| 2026-10-31 | 298 | [Apply Image and Calculations (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-298) |
| 2026-10-31 | 299 | [Linked Smart Objects (in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-299) |
| 2026-10-31 | 300 | [Rich PhotoCraft migration (in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-300) |
| 2026-10-31 | 301 | [Diary refreshed against current evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-301) |
| 2026-10-31 | 302 | [Exposure workflow prerequisite (in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-302) |
| 2026-10-31 | 303 | [Editable source vector shapes (unbuilt, in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-303) |
| 2026-10-31 | 304 | [Diary synchronized with actual source and test evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-304) |
| 2026-10-31 | 305 | [Editable source shapes: native/API workflows tested, strict gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-305) |
| 2026-10-31 | 306 | [Rich source text migration (unbuilt, in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-306) |
| 2026-10-31 | 307 | [Diary synchronized with current work and verified evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-307) |
| 2026-10-31 | 308 | [Rich source text native/API workflows tested; exact gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-308) |
| 2026-10-31 | 309 | [Source Smart Object prerequisites; workflow crash remains open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-309) |
| 2026-10-31 | 310 | [Diary synchronized with current work, tests and failures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-310) |
| 2026-10-31 | 311 | [Command-worker crash repaired; full inventory and strict gates recorded](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-311) |
| 2026-10-31 | 312 | [Editable source Smart import: cached workflows tested; nesting failure open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-312) |
| 2026-10-31 | 313 | [Diary synchronized with current import and retained failures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-313) |
| 2026-10-31 | 314 | [Nested source worker repaired; native/API workflows pass, strict gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-314) |
| 2026-11-01 | 315 | [Editable source filter mappings expand to107; functional tests pass, strict gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-315) |
| 2026-11-01 | 316 | [Native Relight engine and integration draft; testing pending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-316) |
| 2026-11-01 | 317 | [Diary synchronized with working316 and tested315](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-317) |
| 2026-11-01 | 318 | [Native Relight workflows and exact original-engine reference subset qualified](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-318) |
| 2026-11-01 | 319 | [Multi-light Lighting Effects; partial tests and failed repair](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-319) |
| 2026-11-01 | 320 | [Diary synchronized with current319 evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-320) |
| 2026-11-01 | 321 | [Lighting Effects functional qualification and complete test inventory](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-321) |
| 2026-11-01 | 322 | [Source Displace functional qualification and diary synchronization](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-322) |
| 2026-11-01 | 323 | [Original adjustment-layer functional breadth and source composition](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-323) |
| 2026-11-01 | 324 | [Original layer effects: staged native controls and rendering helpers, unfinished](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-324) |
| 2026-11-01 | 325 | [Diary synchronized with tested323 and unfinished324](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-325) |
| 2026-11-01 | 326 | [Original layer-effects functional qualification and shared Global Light menu](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-326) |
| 2026-11-01 | 327 | [Diary reconciled with tested source, installed preview and remaining major work](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-327) |
| 2026-11-01 | 328 | [Original channels and auxiliary spot workflows functionally qualified](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-328) |
| 2026-11-01 | 329 | [PSD/PSB auxiliary channel interchange functionally qualified](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-329) |
| 2026-11-01 | 330 | [Document guides and source layout import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-330) |
| 2026-11-01 | 331 | [Xcode archive and alpha store preparation; validation and media pending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-331) |
| 2026-11-01 | 332 | [Window lifecycle, recovery and updated Xcode archive](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-332) |
| 2026-11-01 | 333 | [App Store validation after Xcode sign-in](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-333) |
| 2026-11-01 | 334 | [Native File Info and source document metadata](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-334) |
| 2026-11-01 | 335 | [Photoshop 2026 as the reference](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-335) |
| 2026-11-01 | 336 | [Layer Comps and production export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-336) |
| 2026-11-01 | 337 | [Smart Object comp selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-337) |
| 2026-11-01 | 338 | [Parent Layer Comp Smart Object choices](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-338) |
| 2026-11-01 | 339 | [Editable PSD/PSB Layer Comps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-339) |
| 2026-11-02 | 340 | [Editable PSD/PSB Global Light](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-340) |
| 2026-11-02 | 341 | [Production Export As workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-341) |
| 2026-11-02 | 342 | [Layers to Files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-342) |
| 2026-11-02 | 343 | [Color Range selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-343) |
| 2026-11-02 | 344 | [Magnetic Lasso tool](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-344) |
| 2026-11-02 | 345 | [Selection Modify and Reselect](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-345) |
| 2026-11-02 | 346 | [Transform Selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-346) |
| 2026-11-02 | 347 | [Selected-pixel Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-347) |
| 2026-11-02 | 348 | [Background layer semantics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-348) |
| 2026-11-02 | 349 | [Background selected-pixel Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-349) |
| 2026-11-02 | 350 | [Move and copy selected pixels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-350) |
| 2026-11-02 | 351 | [Pixel-mask Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-351) |
| 2026-11-02 | 352 | [Auxiliary-channel Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-352) |
| 2026-11-02 | 353 | [Multi-layer and group transforms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-353) |
| 2026-11-02 | 354 | [Projective layer transforms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-354) |
| 2026-11-02 | 355 | [Layer links and whole-layer Move](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-355) |
| 2026-11-02 | 356 | [Color Fill and Stroke](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-356) |
| 2026-11-02 | 357 | [Pattern Fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-357) |
| 2026-11-02 | 358 | [Large-document Crop](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-358) |
| 2026-11-02 | 359 | [Layer capacity](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-359) |
| 2026-11-02 | 360 | [Flatten Image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-360) |
| 2026-11-02 | 361 | [Duplicate Image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-361) |
| 2026-11-02 | 362 | [Trim and Reveal All](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-362) |
| 2026-11-02 | 363 | [Private full-source backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-363) |
| 2026-11-02 | 364 | [Rich layer merging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-364) |
| 2026-11-02 | 365 | [Linked preview sampling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-365) |
| 2026-11-02 | 366 | [Quick Mask and saved selections](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-366) |
| 2026-11-02 | 367 | [Saved-selection documents; next major function selected](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-367) |
| 2026-11-02 | 368 | [Quick Mask workflow checks; C01 next](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-368) |
| 2026-11-03 | 369 | [Quick Mask visibility and hidden brush target](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-369) |
| 2026-11-03 | 370 | [Private source backup and next major function](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-370) |
| 2026-11-03 | 371 | [Hidden Quick Mask commands and pixel Invert](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-371) |
| 2026-11-03 | 372 | [Quick Mask target transitions; C01 queued](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-372) |
| 2026-11-03 | 373 | [Mask paint colors and S05 audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-373) |
| 2026-11-03 | 374 | [Large saved-selection files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-374) |
| 2026-11-03 | 375 | [PSB file compatibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-375) |
| 2026-11-03 | 376 | [Shared paint colours](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-376) |
| 2026-11-03 | 377 | [App Store listing and media](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-377) |
| 2026-11-04 | 378 | [App Store familiarity wording](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-378) |
| 2026-11-04 | 379 | [Multichannel Quick Mask files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-379) |
| 2026-11-04 | 380 | [Mask paint-colour contexts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-380) |
| 2026-11-04 | 381 | [Mask target lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-381) |
| 2026-11-04 | 382 | [Current full test inventory](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-382) |
| 2026-11-04 | 383 | [Document lifecycle regression repairs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-383) |
| 2026-11-04 | 384 | [Animated layer-style transactions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-384) |
| 2026-11-04 | 385 | [Fit Image and reusable batch constraints](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-385) |
| 2026-11-04 | 386 | [Find and Replace Text](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-386) |
| 2026-11-04 | 387 | [Numeric component-plane storage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-387) |
| 2026-11-04 | 388 | [Native component blocks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-388) |
| 2026-11-04 | 389 | [Private source backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-389) |
| 2026-11-04 | 390 | [Component archive streaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-390) |
| 2026-11-04 | 391 | [Large native component documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-391) |
| 2026-11-04 | 392 | [Large component geometry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-392) |
| 2026-11-04 | 393 | [Large component tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-393) |
| 2026-11-04 | 394 | [RGB8 component routing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-394) |
| 2026-11-04 | 395 | [Private source backup and listing wording](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-395) |
| 2026-11-04 | 396 | [Large native channel arithmetic](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-396) |
| 2026-11-04 | 397 | [Independent channel eyes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-397) |
| 2026-11-04 | 398 | [Temporary mask channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-398) |
| 2026-11-04 | 399 | [Consolidated S05 validation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-399) |
| 2026-11-04 | 400 | [Quick Mask options and gestures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-400) |
| 2026-11-04 | 401 | [Quick Mask reference matrix; repair parked](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-401) |
| 2026-11-04 | 402 | [Seven-pass work order](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-402) |
| 2026-11-04 | 403 | [Delete All Empty Layers native baseline](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-403) |
| 2026-11-04 | 404 | [Single-pixel marquee and quick-win audits](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-404) |
| 2026-11-04 | 405 | [Color Lookup export and quick-win audits](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-405) |
| 2026-11-04 | 406 | [RGB8 component selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-406) |
| 2026-11-04 | 407 | [Duplicate saved actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-407) |
| 2026-11-04 | 408 | [Shape stroke presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-408) |
| 2026-11-04 | 409 | [Quick-win source audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-409) |
| 2026-11-05 | 410 | [Gradient Fill API and Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-410) |
| 2026-11-05 | 411 | [Last Filter and Pattern Fill audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-411) |
| 2026-11-05 | 412 | [Filter Gallery dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-412) |
| 2026-11-05 | 413 | [Brush Settings sidebar controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-413) |
| 2026-11-05 | 414 | [Smart Filter dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-414) |
| 2026-11-05 | 415 | [Select Subject options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-415) |
| 2026-11-05 | 416 | [Selected-mask removal and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-416) |
| 2026-11-05 | 417 | [Statistical image stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-417) |
| 2026-11-05 | 418 | [Frame Timeline dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-418) |
| 2026-11-05 | 419 | [Rename sky presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-419) |
| 2026-11-05 | 420 | [Rasterization responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-420) |
| 2026-11-05 | 421 | [Channel thumbnail options and major quick-win sweep](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-421) |
| 2026-11-05 | 422 | [Arrange selected layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-422) |
| 2026-11-05 | 423 | [Layer filtering and isolation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-423) |
| 2026-11-05 | 424 | [Asynchronous layer content filters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-424) |
| 2026-11-05 | 425 | [Layer selection and deselection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-425) |
| 2026-11-05 | 426 | [Customize Save Dialog File Formats](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-426) |
| 2026-11-05 | 427 | [Adjacent artboard controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-427) |
| 2026-11-05 | 428 | [Animated selection borders](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-428) |
| 2026-11-05 | 429 | [Transform reference point](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-429) |
| 2026-11-05 | 430 | [Large-document Equalize](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-430) |
| 2026-11-05 | 431 | [Color Lookup output formats](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-431) |
| 2026-11-05 | 432 | [Pattern Patch](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-432) |
| 2026-11-05 | 433 | [Channels footer Save/Load](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-433) |
| 2026-11-05 | 434 | [Batch file naming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-434) |
| 2026-11-05 | 435 | [Precise shape creation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-435) |
| 2026-11-05 | 436 | [Extended Fill Path](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-436) |
| 2026-11-06 | 437 | [Character and Paragraph panels — development](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-437) |
| 2026-11-06 | 438 | [Point-text layout and native editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-438) |
| 2026-11-06 | 439 | [Direct native path typing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-439) |
| 2026-11-06 | 440 | [Paged Curves and Levels histograms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-440) |
| 2026-11-06 | 441 | [Light painting and retouch previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-441) |
| 2026-11-06 | 442 | [Gradient creation and portable Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-442) |
| 2026-11-06 | 443 | [Pattern groups and PAT hierarchy](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-443) |
| 2026-11-06 | 444 | [Public repository and Shape Blur development](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-444) |
| 2026-11-06 | 445 | [Public Git history credential audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-445) |
| 2026-11-06 | 446 | [Custom Shape Blur numerical investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-446) |
| 2026-11-06 | 447 | [Custom Kernel ACF preset interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-447) |
| 2026-11-06 | 448 | [Blur Gallery mask output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-448) |
| 2026-11-06 | 449 | [Public source and unpublished build backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-449) |
| 2026-11-06 | 450 | [Liquify last mesh reuse](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-450) |
| 2026-11-06 | 451 | [Local build cleanup; lens-default audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-451) |
| 2026-11-06 | 452 | [Camera and lens defaults](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-452) |
| 2026-11-06 | 453 | [Custom Filter Gallery textures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-453) |
| 2026-11-06 | 454 | [Brush pattern textures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-454) |
| 2026-11-06 | 455 | [Eraser mode reference](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-455) |
| 2026-11-06 | 456 | [Eraser modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-456) |
| 2026-11-06 | 457 | [Blur, Sharpen and Smudge blend modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-457) |
| 2026-11-06 | 458 | [Content-Aware Fill without leaving the workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-458) |
| 2026-11-06 | 459 | [Eyedropper averaging and source controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-459) |
| 2026-11-06 | 460 | [Mask and channel clipboard](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-460) |
| 2026-11-06 | 461 | [Advanced blending channel controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-461) |
| 2026-11-06 | 462 | [Saved layer style presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-462) |
| 2026-11-06 | 463 | [Smart Object Convert to Layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-463) |
| 2026-11-06 | 464 | [Smart Filter stack and mask transfer](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-464) |
| 2026-11-06 | 465 | [Magic Wand averaged sampling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-465) |
| 2026-11-07 | 466 | [Selection source policy and Magic Wand Subject](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-466) |
| 2026-11-07 | 467 | [Select and Mask source workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-467) |
| 2026-11-07 | 468 | [Layer and Smart Filter mask filtering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-468) |
| 2026-11-07 | 469 | [Large auxiliary-channel filtering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-469) |
| 2026-11-07 | 470 | [Split Channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-470) |
| 2026-11-07 | 471 | [Large-document soft proofing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-471) |
| 2026-11-07 | 472 | [Large image stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-472) |
| 2026-11-07 | 473 | [Embedded originals in source projects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-473) |
| 2026-11-07 | 474 | [OpenEXR HDR files](part-01.md#dev-step-474) |
| 2026-11-07 | 475 | [Generated image jobs and originals](part-01.md#dev-step-475) |
| 2026-11-07 | 476 | [Blank video drawing layers](part-01.md#dev-step-476) |
| 2026-11-07 | 477 | [Sky preset groups and batch import](part-01.md#dev-step-477) |
| 2026-11-07 | 478 | [Local Color Lookup painting](part-01.md#dev-step-478) |
| 2026-11-07 | 479 | [Color Lookup property responsiveness](part-01.md#dev-step-479) |
| 2026-11-07 | 480 | [Independent Color Lookup references](part-01.md#dev-step-480) |
| 2026-11-07 | 481 | [Repeatable archive validation](part-01.md#dev-step-481) |
| 2026-11-07 | 482 | [Menu inventory reconciliation](part-01.md#dev-step-482) |
| 2026-11-07 | 483 | [Script Events Manager](part-01.md#dev-step-483) |
| 2026-11-07 | 484 | [Quick Mask selection semantics](part-01.md#dev-step-484) |
| 2026-11-07 | 485 | [Sampled Hue/Saturation ranges](part-01.md#dev-step-485) |
| 2026-11-07 | 486 | [Classic RGB16 gradient boundaries](part-01.md#dev-step-486) |
| 2026-11-08 | 487 | [Share the person-selection model](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-487) |
| 2026-11-08 | 488 | [Image styles and canvas size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-488) |
| 2026-11-08 | 489 | [Native Remove tool](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-489) |
| 2026-11-08 | 490 | [Generated backgrounds](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-490) |
| 2026-11-08 | 491 | [Reference images for generation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-491) |
| 2026-11-08 | 492 | [Reviewed edit plans](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-492) |
| 2026-11-08 | 493 | [Profile changes on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-493) |
| 2026-11-08 | 494 | [Directory durability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-494) |
| 2026-11-08 | 495 | [Paged Warp](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-495) |
| 2026-11-08 | 496 | [PSD vector path semantics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-496) |
| 2026-11-08 | 497 | [Untagged files and sandboxed copies](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-497) |
| 2026-11-08 | 498 | [Large colour-mode files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-498) |
| 2026-11-08 | 499 | [Paths to Illustrator](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-499) |
| 2026-11-08 | 500 | [Repair native asset export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-500) |
| 2026-11-08 | 501 | [Select People on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-501) |
| 2026-11-08 | 502 | [Report Apple text-service availability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-502) |
| 2026-11-08 | 503 | [Review people before removal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-503) |
| 2026-11-08 | 504 | [Background generation on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-504) |
| 2026-11-08 | 505 | [Edit a reference image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-505) |
| 2026-11-08 | 506 | [Local learned upscaling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-506) |
| 2026-11-08 | 507 | [Reviewed adjustment values](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-507) |
| 2026-11-08 | 508 | [AI, language and plugin acceptance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-508) |
| 2026-11-08 | 509 | [Plugin host requirements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-509) |
| 2026-11-08 | 510 | [Editable gradient profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-510) |
| 2026-11-08 | 511 | [Gray32 Photoshop file export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-511) |
| 2026-11-09 UTC | 512 | [Merge Channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-512) |
| 2026-11-09 UTC | 513 | [Legacy Macintosh proof](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-513) |
| 2026-11-09 UTC | 514 | [Editable photo blending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-514) |
| 2026-11-09 UTC | 515 | [Editable artboard project import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-515) |
| 2026-11-09 | 516 | [Editable PSD/PSB artboards](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-516) |
| 2026-11-09 | 517 | [Saved generated-image variations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-517) |
| 2026-11-09 | 518 | [Editing video keyframes as a group](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-518) |
| 2026-11-09 | 519 | [Large Sky documents and full-detail previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-519) |
| 2026-11-09 | 520 | [Color and vibrance with Adjustment Brush](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-520) |
| 2026-11-09 | 521 | [Sky preview containment and brush measurements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-521) |
| 2026-11-09 | 522 | [Masked adjustment preview performance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-522) |
| 2026-11-09 | 523 | [Retained layer-mask and Adjustment Brush previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-523) |
| 2026-11-09 | 524 | [Selection borders and Canvas Size zoom](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-524) |
| 2026-11-16 | 525 | [Selection-preview responsiveness; 22 Debug checks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-525) |
| 2026-11-16 | 526 | [Marquee creation and polygon routing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-526) |
| 2026-11-17 | 527 | [Save format checks on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-527) |
| 2026-11-17 | 528 | [Open JPEG XL still images](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-528) |
| 2026-11-17 | 529 | [Share unchanged canvas preview pages](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-529) |
| 2026-11-17 | 530 | [Send ready previews directly to the AppKit canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-530) |
| 2026-11-17 | 531 | [Find changed tiles without sorting the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-531) |
| 2026-11-17 | 532 | [Reuse recomposited tiles in the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-532) |
| 2026-11-17 | 533 | [Start the first Brush frame sooner](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-533) |
| 2026-11-17 | 534 | [Start the background worker with Brush input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-534) |
| 2026-11-17 | 535 | [Match the ordinary Brush smoothing default](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-535) |
| 2026-11-17 | 536 | [Connect Brush and Pencil strokes with Shift-click](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-536) |
| 2026-11-17 | 537 | [Record Pencil strokes in Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-537) |
| 2026-11-17 | 538 | [Support 5,000 px primary brush diameters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-538) |
| 2026-11-17 | 539 | [Process Brush coverage and output by tile](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-539) |
| 2026-11-17 | 540 | [Align linear Float32 brush output across architectures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-540) |
| 2026-11-17 | 541 | [Publish retained Brush and flat compositor output by tile](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-541) |
| 2026-11-17 | 542 | [Round Linear and Perceptual gradient transfers consistently](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-542) |
| 2026-11-17 | 543 | [Reuse exact gradient samples and publish tiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-543) |
| 2026-11-17 | 544 | [Prepare wide brush dabs once and start the first preview sooner](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-544) |
| 2026-11-17 | 545 | [Compose flat tone stacks in one tile pass](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-545) |
| 2026-11-17 | 546 | [Write changed canvas bytes directly](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-546) |
| 2026-11-18 | 547 | [Retain coverage for wide raster brushes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-547) |
| 2026-11-18 | 548 | [Speed up Normal brush tile output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-548) |
| 2026-11-18 | 549 | [Sample wide brush coverage in parallel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-549) |
| 2026-11-18 | 550 | [Parallelize large raster composition and display packing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-550) |
| 2026-11-18 | 551 | [Parallelize brush tile output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-551) |
| 2026-11-18 | 552 | [Add brush opacity and flow number keys](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-552) |
| 2026-11-18 | 553 | [Widen the zero-hardness Soft Round tip](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-553) |
| 2026-11-18 | 554 | [Calibrate the round brush hardness range](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-554) |
| 2026-11-18 | 555 | [Add brush hardness, rotation and smoothing keys](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-555) |
| 2026-11-18 | 556 | [Add Behind and Clear painting modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-556) |
| 2026-11-18 | 557 | [Add Brush and Pencil blend-mode shortcuts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-557) |
| 2026-11-18 | 558 | [Page large Paint Bucket and Magic Wand regions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-558) |
| 2026-11-18 | 559 | [Add Paint Bucket Clear and automation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-559) |
| 2026-11-18 | 560 | [Add Clear to Edit Fill and Stroke](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-560) |
| 2026-11-18 | 561 | [Record Paint Bucket Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-561) |
| 2026-11-18 | 562 | [Record Brush Actions for masks and channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-562) |
| 2026-11-18 | 563 | [Record and replay Quick Mask Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-563) |
| 2026-11-18 | 564 | [Record Brush Actions for color channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-564) |
| 2026-11-18 | 565 | [Add Allow Tool Recording to Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-565) |
| 2026-11-18 | 566 | [Preserve opaque Gray32 merged samples in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-566) |
| 2026-11-18 | 567 | [Use the source tone curves for 32-bit RGB and Gray](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-567) |
| 2026-11-18 | 568 | [Match half-gamma promotion and Gray32 PSD layer stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-568) |
| 2026-11-18 | 569 | [Match HDR grayscale conversion and ICC gamma boundaries](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-569) |
| 2026-11-18 | 570 | [Preserve the working profile when merging before conversion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-570) |
| 2026-11-18 | 571 | [Fix HDR PSD and PSB compression for Photoshop](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-571) |
| 2026-11-18 | 572 | [Match Intel HDR Normal layer and group compositing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-572) |
| 2026-11-18 | 573 | [Match HDR Normal rounding at the Float32 underflow boundary](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-573) |
| 2026-11-18 | 574 | [Add Stamp Layers and Stamp Visible](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-574) |
| 2026-11-18 | 575 | [Render sparse stamps at maximum canvas size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-575) |
| 2026-11-18 | 576 | [Match stored RGB32 Normal merge and stamp samples](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-576) |
| 2026-11-18 | 577 | [Preserve stored RGB32 pixel masks when merging and stamping](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-577) |
| 2026-11-18 | 578 | [Add contextual Merge Clipping Mask](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-578) |
| 2026-11-18 | 579 | [Add in-place Stamp Down and Stamp Group](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-579) |
| 2026-11-18 | 580 | [Match Screen clipping and unchanged stamp history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-580) |
| 2026-11-18 | 581 | [Merge and stamp adjacent clipped layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-581) |
| 2026-11-18 | 582 | [Preserve independent clipping in merges and stamps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-582) |
| 2026-11-18 | 583 | [Add four clipped blend modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-583) |
| 2026-11-19 | 584 | [Preserve pixel masks in clipping merges and stamps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-584) |
| 2026-11-19 | 585 | [Add three arithmetic clipping blend modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-585) |
| 2026-11-19 | 586 | [Bound pixel-mask Feather rendering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-586) |
| 2026-11-19 | 587 | [Match staged RGB32 pixel-mask Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-587) |
| 2026-11-19 | 588 | [Support layer-mask Feather through 1,000 px](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-588) |
| 2026-11-19 | 589 | [Apply Feather in raster clipping merges and stamps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-589) |
| 2026-11-19 | 590 | [Match integer raster-mask Feather stages](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-590) |
| 2026-11-19 | 591 | [Match measured fractional RGB32 Feather schedules](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-591) |
| 2026-11-19 | 592 | [Bound Smart Filter mask Feather on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-592) |
| 2026-11-19 | 593 | [Bound vector mask Feather on large canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-593) |
| 2026-11-19 | 594 | [Match measured short vector-mask Feather responses](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-594) |
| 2026-11-19 | 595 | [Prepare vector-mask Feather around the viewport](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-595) |
| 2026-11-19 | 596 | [Reuse source bands during wide mask Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-596) |
| 2026-11-19 | 597 | [Reuse window sums during wide mask Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-597) |
| 2026-11-19 | 598 | [Render whole-canvas rectangular vector masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-598) |
| 2026-11-19 | 599 | [Reuse wide vector-mask Feather windows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-599) |
| 2026-11-19 | 600 | [Prove RGB32 raster-base opacity with rectangular Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-600) |
| 2026-11-19 | 601 | [Render sparse curved Feather from stored coverage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-601) |
| 2026-11-19 | 602 | [Skip solid pieces of dense feathered vector masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-602) |
| 2026-11-19 | 603 | [Reuse exact composited tiles under solid vector Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-603) |
| 2026-11-19 | 604 | [Reuse wide vector Feather profiles at canvas edges](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-604) |
| 2026-11-19 | 605 | [Stream repeated rows in sparse PSB files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-605) |
| 2026-11-19 | 606 | [Reopen sparse editable PSB raster layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-606) |
| 2026-11-19 | 607 | [Choose sparse Photoshop layer samples across the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-607) |
| 2026-11-19 | 608 | [Save full-width sparse raster edits to PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-608) |
| 2026-11-19 | 609 | [Set PSD and PSB file compatibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-609) |
| 2026-11-19 | 610 | [Read saved Photoshop channels without a merged preview](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-610) |
| 2026-11-19 | 611 | [Import large PSD and PSB saved channels into sparse tiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-611) |
| 2026-11-19 | 612 | [Save large PSD and PSB channels with repeated rows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-612) |
| 2026-11-19 | 613 | [Import large flattened RGB PSD and PSB without staging all process planes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-613) |
| 2026-11-19 | 614 | [Read large ZIP-compressed Photoshop layers and masks as sparse rasters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-614) |
| 2026-11-19 | 615 | [Keep large Grayscale, CMYK and Lab Photoshop planes sparse](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-615) |
| 2026-11-19 | 616 | [Write native Photoshop separations and Gray32 previews from stored blocks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-616) |
| 2026-11-19 | 617 | [Add the optional Workflow Guide](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-617) |
| 2026-11-19 | 618 | [Save deep RGB Photoshop files without a merged preview](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-618) |
| 2026-11-19 | 619 | [Rank Workflow Guide suggestions and highlight each step](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-619) |
| 2026-11-19 | 620 | [Keep maximum-size Multichannel printing plates editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-620) |
| 2026-11-19 | 621 | [Follow native menus and dialogs in the Workflow Guide](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-621) |
| 2026-11-19 | 622 | [Resize and crop editable Multichannel plates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-622) |
| 2026-11-19 | 623 | [Convert layerless ink documents back to editable image modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-623) |
| 2026-11-19 | 624 | [Duplicate channels into the current image or another document](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-624) |
| 2026-11-19 | 625 | [Merge spot ink into the supported process channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-625) |
| 2026-11-19 | 626 | [Delete process channels through the Channels panel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-626) |
| 2026-11-19 | 627 | [Integrate Workflow Guide cues with the expanded Channels panel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-627) |
| 2026-11-19 | 628 | [Drag channel rows and keep menu cues aligned](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-628) |
| 2026-11-19 | 629 | [Keep saved masks and printing plates in one Multichannel order](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-629) |
| 2026-11-19 | 630 | [Keep Workflow Guide highlights visible across controls and dialogs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-630) |
| 2026-11-19 | 631 | [Preserve spot inks in Multichannel Photoshop files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-631) |
| 2026-11-19 | 632 | [Keep native CMYK and Lab components when flattening to Multichannel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-632) |
| 2026-11-19 | 633 | [Return standard Multichannel plates to editable CMYK](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-633) |
| 2026-11-19 | 634 | [Print native CMYK and saved spot separations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-634) |
| 2026-11-19 | 635 | [Print a selection from a large document](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-635) |
| 2026-11-19 | 636 | [Fit and clip large prints at their original sample resolution](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-636) |
| 2026-11-19 | 637 | [Remember print defaults and restore supported Photoshop settings](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-637) |
| 2026-11-19 | 638 | [Save document print settings with the artwork](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-638) |
| 2026-11-19 | 639 | [Keep vector outlines when printing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-639) |
| 2026-11-19 | 640 | [Keep Photoshop rectangles editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-640) |
| 2026-11-19 | 641 | [Keep rounded rectangles and dashed ellipses editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-641) |
| 2026-11-19 | 642 | [Read older solid shapes and their pixel masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-642) |
| 2026-11-19 | 643 | [Open nested Photoshop Smart Objects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-643) |
| 2026-11-19 | 644 | [Match linked raster previews to saved mask samples](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-644) |
| 2026-11-19 | 645 | [Keep Gradient Overlay editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-645) |
| 2026-11-19 | 646 | [Speed up large editable Smart Filter files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-646) |
| 2026-11-19 | 647 | [Keep large generated Smart Object sources editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-647) |
| 2026-11-19 | 648 | [Keep large embedded sources once](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-648) |
| 2026-11-19 | 649 | [Place and reopen larger Photoshop originals](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-649) |
| 2026-11-19 | 650 | [Retain large embedded originals on disk](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-650) |
| 2026-11-19 | 651 | [Keep gigabyte-scale originals through Edit Contents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-651) |
| 2026-11-19 | 652 | [Keep gigabyte-scale originals in Undo and Redo](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-652) |
| 2026-11-20 | 653 | [Preserve Smart Object placement identifiers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-653) |
| 2026-11-20 | 654 | [Place and update gigabyte-scale linked Smart Objects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-654) |
| 2026-11-20 | 655 | [Add General placement preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-655) |
| 2026-11-20 | 656 | [Recover linked Smart Objects after moving a folder](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-656) |
| 2026-11-20 | 657 | [Place Smart Objects at their source print size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-657) |
| 2026-11-20 | 658 | [Custom Smart Object geometry for template jobs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-658) |
| 2026-11-20 | 659 | [Read the original transform of linked Smart Objects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-659) |
| 2026-11-20 | 660 | [Free Transform follows Smart Object artwork](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-660) |
| 2026-11-20 | 661 | [Smart Object templates get editable masks and blending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-661) |
| 2026-11-20 | 662 | [Fit replacement artwork inside Smart Object frames](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-662) |
| 2026-11-20 | 663 | [Inspect Photoshop templates through the Adobe-compatible manifest](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-663) |
| 2026-11-20 | 664 | [Export thumbnail and Smart Object assets from Photoshop manifests](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-664) |
| 2026-11-20 | 665 | [Reopen perspective Smart Objects and continue editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-665) |
| 2026-11-20 | 666 | [Relink perspective artwork after reopening PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-666) |
| 2026-11-20 | 667 | [Keep Smart Object Warp editable in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-667) |
| 2026-11-20 | 668 | [Wrap editable Smart Objects around a cylinder](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-668) |
| 2026-11-20 | 669 | [Keep PDF Smart Object Warp editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-669) |
| 2026-11-20 | 670 | [Keep PDF Smart Object perspective editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-670) |
| 2026-11-20 | 671 | [Keep vector masks editable in Perspective and Distort](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-671) |
| 2026-11-20 | 672 | [Transform selected paths, contours and anchors](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-672) |
| 2026-11-20 | 673 | [Select path anchors with a Direct Selection marquee](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-673) |
| 2026-11-20 | 674 | [Transform editable paths across layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-674) |
| 2026-11-20 | 675 | [Warp editable paths on the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-675) |
| 2026-11-20 | 676 | [Switch between path Warp and Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-676) |
| 2026-11-20 | 677 | [Isolate a path’s layer while editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-677) |
| 2026-11-20 | 678 | [Align and distribute components on an editable path](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-678) |
| 2026-11-20 | 679 | [Reorder, combine and merge path components](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-679) |
| 2026-11-20 | 680 | [Subtract the first component of a shape layer](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-680) |
| 2026-11-20 | 681 | [Keep the shape exterior attached to the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-681) |
| 2026-11-20 | 682 | [Render gradients and strokes on large editable cutouts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-682) |
| 2026-11-20 | 683 | [Keep shape gradients editable in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-683) |
| 2026-11-20 | 684 | [Keep patterns and straight lines editable in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-684) |
| 2026-11-20 | 685 | [Improve RGB8 shape opacity and legacy pattern placement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-685) |
| 2026-11-20 | 686 | [Match sampled Photoshop legacy pattern scales](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-686) |
| 2026-11-20 | 687 | [Keep Pattern Overlay editable in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-687) |
| 2026-11-21 | 688 | [Render Pattern Overlay on large canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-688) |
| 2026-11-21 | 689 | [Preview opaque Pattern Overlay on large canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-689) |
| 2026-11-21 | 690 | [Bound rotated Pattern Overlay viewports](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-690) |
| 2026-11-21 | 691 | [Fit quarter-turn Pattern Overlays on large canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-691) |
| 2026-11-21 | 692 | [Reduce wide oblique Pattern Overlays in bounded patches](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-692) |
| 2026-11-21 | 693 | [Reuse prepared pattern samples across render patches](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-693) |
| 2026-11-21 | 694 | [Write layer styles by tile and reuse opacity checks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-694) |
| 2026-11-21 | 695 | [Keep advanced Drop Shadows editable in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-695) |
| 2026-11-21 | 696 | [Render Drop Shadows in bounded canvas regions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-696) |
| 2026-11-21 | 697 | [Reduce Fit and proof previews for large uniform Drop Shadows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-697) |
| 2026-11-21 | 698 | [Read raster alpha directly for regional Drop Shadows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-698) |
| 2026-11-21 | 699 | [Add local Generative Fill from surrounding pixels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-699) |
| 2026-11-21 | 700 | [Add prompted Generative Fill on Apple Silicon](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-700) |
| 2026-11-21 | 701 | [Blend Generative Fill selection edges](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-701) |
| 2026-11-21 | 702 | [Keep editable Generative Fill variations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-702) |
| 2026-11-21 | 703 | [Add batches to an existing Generative Fill layer](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-703) |
| 2026-11-21 | 704 | [Generate similar variations from a saved local fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-704) |
| 2026-11-21 | 705 | [Extend the canvas with local generation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-705) |
| 2026-11-21 | 706 | [Extend wide borders with overlapping model windows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-706) |
| 2026-11-21 | 707 | [Reuse the local prompt model across an editing job](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-707) |
| 2026-11-21 | 708 | [Add more variations to a saved wide expansion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-708) |
| 2026-11-21 | 709 | [Generate and iterate on a local background](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-709) |
| 2026-11-21 | 710 | [Replace a masked background with colour or artwork](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-710) |
| 2026-11-21 | 711 | [Match a subject to its background with editable Harmonize variations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-711) |
| 2026-11-21 | 712 | [Generate editable images from a text prompt on-device](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-712) |
| 2026-11-21 | 713 | [Edit a whole image with local instructions and saved variations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-713) |
| 2026-11-21 | 714 | [Guide Generate Image with Style and Composition references](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-714) |
| 2026-11-21 | 715 | [Fill a selection from a local reference image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-715) |
| 2026-11-21 | 716 | [Remove extended wire and cable runs in one edit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-716) |
| 2026-11-21 | 717 | [Review and remove general distractions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-717) |
| 2026-11-21 | 718 | [Use on-device Generative Remove from the brush and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-718) |
| 2026-11-23 | 719 | [Review related shadows and reflections before removing them](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-719) |
| 2026-11-23 | 720 | [Recover partial transparency in product cutouts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-720) |
| 2026-11-23 | 721 | [Preserve editable type and RGB32 composites in layered Photoshop files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-721) |
| 2026-11-23 | 722 | [Keep projected Smart Object edges stable when relinking](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-722) |
| 2026-11-23 | 723 | [Refine hair in Select and Mask](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-723) |
| 2026-11-23 | 724 | [Reuse the canvas composite for Clone Stamp and Healing Brush](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-724) |
| 2026-11-23 | 725 | [Speed up RGB8 and RGB16 retouch sample conversion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-725) |
| 2026-11-23 | 726 | [Keep cropped-layer retouch previews regional](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-726) |
| 2026-11-23 | 727 | [Extend perspective texture repair to large canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-727) |
| 2026-11-23 | 728 | [Reuse the editor composite for Vanishing Point previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-728) |
| 2026-11-23 | 729 | [Keep narrow Vanishing Point strokes visible](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-729) |
| 2026-11-23 | 730 | [Preserve Vanishing Point cameras at the canvas size limit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-730) |
| 2026-11-23 | 731 | [Blend projected repairs with Vanishing Point Heal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-731) |
| 2026-11-23 | 732 | [Repair directly on cropped Vanishing Point layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-732) |
| 2026-11-24 | 733 | [Keep Vanishing Point grids editable in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-733) |
| 2026-11-25 | 734 | [Keep Vanishing Point grid spacing and export square planes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-734) |
| 2026-11-25 | 735 | [Measure and calibrate Vanishing Point planes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-735) |
| 2026-11-25 | 736 | [Render Vanishing Point measurement annotations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-736) |
| 2026-11-25 | 737 | [Export Vanishing Point scenes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-737) |
| 2026-11-25 | 738 | [Add perspective Marquee and floating patches](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-738) |
| 2026-11-25 | 739 | [Wrap Vanishing Point selections across linked planes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-739) |
| 2026-11-25 | 740 | [Recover editable right-angle Photoshop hinges](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-740) |
| 2026-11-25 | 741 | [Preserve Vanishing Point fold angles in Photoshop files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-741) |
| 2026-11-25 | 742 | [Improve floating selection sampling in Vanishing Point](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-742) |
| 2026-11-25 | 743 | [Paint and clone across linked Vanishing Point planes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-743) |
| 2026-11-25 | 744 | [Constrain perspective retouching to a Marquee](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-744) |
| 2026-11-25 | 745 | [Paint straight perspective strokes with Shift](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-745) |

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-08.md) · [Next page](part-06.md)
