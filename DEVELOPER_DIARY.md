# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **746** · The 10 most recent entries, newest first.

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

## 2026-11-25 — Step 739 — Wrap Vanishing Point selections across linked planes

Vanishing Point can draw and move a selection across a hinge. The outline follows both planes without an extra edge down the middle. Floating patches can sample and land across the hinge, and the Photato API uses the same edit and Undo rules as the desktop.

All 38 focused Xcode Debug tests passed. The offscreen workspace check covered both appearances and all 16 modifier combinations on each face. On the same two-wall image in Photoshop, a floating patch crossed the hinge but reached 59 pixels less far into the right wall. Exact placement on that face and pixel agreement remain open. A second guide with unequal wall lengths is ready for comparison.

Both optimized architectures passed 853 of 855 selected tests. The two failures repeated the build 738 diagnostics, and the Photato replays matched across the three build configurations. Both slices of the locally signed preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-739) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_739.md).

## 2026-11-25 — Step 738 — Add perspective Marquee and floating patches

Vanishing Point can create and move a rectangle in perspective. A floating selection can sample another part of the image, then move, scale or rotate as a patch. The existing document selection still protects pixels. The authenticated Photato API uses the same sampling and Undo path. All 35 focused tests passed.

Photoshop and Photato moved the same full-plane patch 20 pixels right and 10 down. The untouched strips matched. The translated area still differs in eight-bit rounding and feather coverage. A marquee that wraps across a hinge and live Source-mode drag comparison remain open.

Both optimized architectures passed 850 of 852 selected tests, with the same two failures as build 737. Photato produced identical replay files in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the locally signed preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-738) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_738.md).

## 2026-11-25 — Step 737 — Export Vanishing Point scenes

Vanishing Point can export perspective planes as textured 3DS meshes or as a VPE scene, with one PNG per plane. Export to 3DS includes the VPE companion. The native filter writes a new folder. The authenticated Photato API downloads the exported files as a ZIP and leaves the document and Undo history intact.

Blender opened the camera, meshes and PNG textures from both Photato reference scenes. An independent reader checked the VPE scene and its companion images. All 21 focused Core cases and 11 corrected Xcode Debug app and HTTP cases passed. Photoshop produced different camera values, hinged texture sizes and square texture pixels. After Effects import and DXF remain open.

Both optimized architectures passed 847 of 849 selected tests. The same two cases failed as in build 736. All nine fixture outputs matched byte for byte across Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the signed preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-737) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_737.md).
