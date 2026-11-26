# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **749** · The 10 most recent entries, newest first.

## 2026-11-25 — Step 749 — Paste clipboard pixels before choosing a perspective plane

Clipboard images pasted into Vanishing Point now start at the upper-left of the document at their original pixel size. They can be placed before any plane exists. Dragging the paste onto a fitted face preserves the grabbed point as the image adopts perspective.

All 62 focused Debug tests passed. Each optimized build passed 876 of 878 selected tests, including both new cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay PNG matched byte for byte across Debug and both optimized builds.

The direct 96 × 48 Flip comparison matched Photoshop at 1,789 pixels and differed at 2,819. All pixels outside the patch were preserved. Paste origin and dimensions now match the Photoshop control. Photoshop’s resampling still needs separate qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-749) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_749.md).

## 2026-11-25 — Step 748 — Transform clipboard and layer pastes in Vanishing Point

Vanishing Point selects Marquee after clipboard paste. Press T to show scale and rotation handles and the Flip and Flop controls. Shift constrains scale or movement and snaps rotation. Option centers the resize or duplicates a moved paste. Finishing a gesture adds one workspace Undo.

All 60 focused Debug tests passed. Each optimized build passed 874 of 876 selected tests, including the three new cases. Intel ran under Rosetta. The same two inherited failures repeated their diagnostics. Four replay PNGs matched byte for byte across Debug and both optimized builds.

The comparison used a 96 × 48 Photoshop Flip and a Photato replay aligned to the same pixel origin and size on a synthetic front-facing plane. Of 4,608 pixels in the patch, 1,789 matched and 2,819 differed. Photato preserved every pixel outside the patch. The Photoshop capture stayed at its upper-left paste origin. A second Flip reproduced the same Adobe RGB raster. Opening Transform with both reflection controls off kept the ordinary Adobe paste unchanged. Free canvas placement, side handles, and Photoshop’s on-plane raster and rotation behavior need separate checks.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-748) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_748.md).

## 2026-11-25 — Step 747 — Sample the Vanishing Point preview with Eyedropper

Vanishing Point’s Eyedropper samples the composite at the pointer. With Preview on, it sees the active draft. With Preview off, it sees the original. The sampled color becomes the workspace Brush color. Press I for Eyedropper and B to return to Brush.

The authenticated Photato command `vanishingPoint.sampleColor` accepts an image point and optional preview operations and returns the visible color and coverage without changing the shared document revision or Undo history.

All 57 focused tests passed in Debug. Both optimized builds passed 871 of 873 selected tests. The new desktop and HTTP Eyedropper check passed on Apple Silicon and Intel under Rosetta. The two inherited color-profile and layer-effect failures repeated their previous diagnostics.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-747) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_747.md).

## 2026-11-25 — Step 746 — Scale and rotate floating perspective selections with handles

Floating Marquee selections now have corner scale controls and a rotation handle. Hold Shift when rotating to snap in 15-degree steps. The editor and API use the same perspective transform, and the drag takes one Undo.

All 56 focused tests passed. They cover a linked hinge, cursor feedback, resizing, rotation and matching desktop/API output. Light and Dark captures show the new handles and the existing numeric controls.

Both optimized builds passed 870 of 872 selected tests. The three new tests passed on Apple Silicon and Intel under Rosetta. The two inherited color-profile and layer-effect failures repeated their previous diagnostics. All six transform replays matched byte for byte across Debug and both optimized builds.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-746) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_746.md).

## 2026-11-25 — Step 745 — Paint straight perspective strokes with Shift

Shift-drag draws a straight path with Vanishing Point Brush and Stamp. Shift-click connects to the previous endpoint when it belongs to the same tool on an eligible face. The pointer changes for straight strokes and Stamp source sampling. A Marquee can be cleared while painting.

The 53 focused tests passed. They cover the renderer, cursor modifier combinations, and matching desktop and API edits with Undo. Exact Photoshop stroke pixels remain open.

Both optimized builds passed all three new cases and 867 of 869 overall. The two inherited failures repeated. All eight owned replays matched across Debug, Apple Silicon and Intel. The matching Universal preview ships with this checkpoint.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-745) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_745.md).

## 2026-11-25 — Step 744 — Constrain perspective retouching to a Marquee

Vanishing Point Brush and Stamp now stay inside the drawn Marquee when applying marks. A selection can extend across a hinge. Stamp can still sample from outside the rectangle, and the Photato API accepts the same selection per stroke.

All 50 focused Xcode tests passed, including a one-pixel footprint split at the selection edge and desktop/API output with one Undo. Photoshop exited before producing reference pixels on the owned two-face guide.

Both optimized builds passed the two new tests and 864 of 866 overall. The inherited failures repeated, and all eight native replays matched byte for byte across Debug, Apple Silicon and Intel. The source checkpoint includes the matching Universal preview.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-744) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_744.md).

## 2026-11-25 — Step 743 — Paint and clone across linked Vanishing Point planes

Brush and Stamp now follow the perspective around a hinge with Allow Multi-surface Operations enabled. Destination clipping is a separate control. An aligned Stamp keeps the same donor displacement as the stroke moves to the linked face. The desktop and API use the same renderer and Undo.

On two owned guides, Brush, Stamp and the healed Brush reached both faces. Turning wrapping off kept the Brush on the starting face. A Photoshop stroke raster for direct comparison is still missing.

All 48 focused Xcode tests passed. Both optimized builds passed all four new tests and 862 of 864 selected tests overall. The two inherited failures repeated their previous results. All eight owned replay PNGs match across Debug and both optimized builds. The matching Universal preview now ships with the source checkpoint on GitHub.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-743) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_743.md).

## 2026-11-25 — Step 742 — Improve floating selection sampling in Vanishing Point

Vanishing Point now uses bicubic sampling when a floating selection lands between pixels. Photoshop references on a synthetic pattern of stripes and dots showed the small overshoots produced by cubic interpolation. On the left-to-right two-wall image, the average donor interior error fell from 2.14 to 0.81 RGB levels. All five full patches improved. The narrow receiving area in one synthetic capture got slightly worse.

All 44 focused Xcode tests passed. The desktop editor and authenticated Photato API produce the same subpixel edit with one Undo.

Both optimized builds passed 858 of 860 selected tests. The two inherited failures repeated their diagnostics. All five replay PNGs agree across Debug, Apple Silicon and Intel.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-742) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_742.md).

## 2026-11-25 — Step 741 — Preserve Vanishing Point fold angles in Photoshop files

PSD and PSB guides can keep their editable fold angles when moving between Photato and Photoshop. Photoshop reopened newly written guides at 45°, 90° and 135°. The reader also recovered the same off-centre camera from the three Photoshop saves. Untouched guide records and merged RGB samples survived both file formats.

A new Marquee comparison used the corrected 90° guide. On the centre row, Photato matched Photoshop's patch extent in one direction and was one pixel wider in the other. The colors differ, even with Feather set to 0.

All 43 focused checks passed. Both optimized builds passed 857 of 859 selected tests and repeated the same two existing failures. The twenty test PSD and PSB files match across the three builds.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-741) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_741.md).

## 2026-11-25 — Step 740 — Recover editable right-angle Photoshop hinges

Photato can open both planes in an owned PSD saved after its hinge angle was edited to 90° in Photoshop. The previous build dropped the guides. The three stored vanishing directions reveal an off-centre camera that would be missed by assuming the centre of the image. Using that camera brings the native scene width ratio within 0.00001 of Photoshop's export.

Both PSD and PSB round trips preserve the perspective record and every merged RGB sample. All 40 focused tests passed, including the authenticated Photato API replay. Newly authored hinge angles and exact color and edge coverage of the Marquee edit still need comparison.

Each optimized architecture passed 855 of 857 selected tests. The same two failures repeated their build 739 diagnostics. All six native reference files matched across Debug, Apple Silicon and Intel. Both locally signed preview slices opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-740) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_740.md).
