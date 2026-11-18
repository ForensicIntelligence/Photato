# Photato Developer Diary

[Complete diary](https://www.forensicintelligence.ca/photato/diary.html#entries) · [Full diary Markdown](https://raw.githubusercontent.com/ForensicIntelligence/Photato/main/PhotoCraftSwift/docs/DEVELOPMENT_DIARY.md) · [Detailed development log](PhotoCraftSwift/docs/DEVLOG.md)

The 10 most recent entries, newest first.

## 2026-11-18 — Step 565 — Add Allow Tool Recording to Actions

The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures. Tool gestures still edit pixels and appear in Undo when the setting is off.

All 608 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. In 52 channel-stroke sequences, both recording settings produced the same raw samples as direct editing and the same per-architecture output as build 564. Forty older Brush step encodings also matched. Both universal slices passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-565) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_565.md).

## 2026-11-18 — Step 564 — Record Brush Actions for color channels

Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates. Playback resolves the recorded target against the current document, respects its selection, and takes one Undo to reverse.

All 583 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. On each architecture, 52 tested channel strokes replayed to the same samples as direct editing and matched build 563’s raw planes. Forty legacy Brush step encodings also matched. Both slices of the macOS 14+ validation archive passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-564) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_564.md).

## 2026-11-18 — Step 563 — Record and replay Quick Mask Actions

Enter Quick Mask, edit the selection with Brush or Pencil, and exit in one Action. Replay starts with the new document’s selection and can be undone in one step.

All 558 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. On both architectures, 24 Quick Mask sequences and 24 older Fill Action encodings matched build 562 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-563) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_563.md).

## 2026-11-18 — Step 562 — Record Brush Actions for masks and channels

Brush strokes on Smart Filter masks and saved channels now play back in Actions. A stroke above a shape can still create an ordinary pixel layer.

All 531 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 96 direct and prepared Brush output buffers and 12 older Action encodings matched build 561 byte for byte on each architecture. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-562) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_562.md).

## 2026-11-18 — Step 561 — Record Paint Bucket Actions

Paint Bucket clicks can now be saved in an Action. Playback uses the new document’s layer, mask, or visible composite. A recorded pattern stays with the Action.

All 527 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 240 color-region masks and 18 direct bucket buffers matched build 560 byte for byte on both architectures. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-561) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_561.md).

## 2026-11-18 — Step 560 — Add Clear to Edit Fill and Stroke

Choose Clear to erase pixels within a selection, along an outline, or across a whole pixel layer. Clear uses the existing Fill and Stroke API commands and can be recorded as a Photato Action.

All 522 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. On each architecture, 264 existing Fill, Stroke, and Path Clear pixel buffers and the legacy settings JSON matched build 559 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-560) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_560.md).

## 2026-11-18 — Step 559 — Paint Bucket Clear and automation

Clear removes alpha from the color region you click. The Photato API can configure the Paint Bucket or fill a region using the same options. Separated sparse fills and full solid fills also update much larger canvases without a whole-canvas write loop in the tested cases.

All 486 selected tests passed across three builds. The 624 actual dense and paged writeback comparisons matched on each optimized architecture. Live Photoshop output comparisons remain open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-559) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_559.md).

## 2026-11-18 — Step 558 — Large Paint Bucket and Magic Wand regions

Magic Wand and Paint Bucket now page large color selections. The tested sparse cases work on 300,000-pixel-square canvases, and a uniform opaque fill can update the whole canvas without allocating pixel tiles.

All 481 selected tests passed across three builds. Existing coverage and bucket buffers matched build 557 byte for byte. Dense maximum-size timing, other fill modes and exact Photoshop comparisons remain open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-558) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_558.md).

## 2026-11-18 — Step 557 — Brush and Pencil blend-mode shortcuts

On the canvas, Shift-plus and Shift-minus cycle paint modes. Shift-Option-Q selects Behind and Shift-Option-R selects Clear on Brush. The shortcut changes the next stroke, so you can switch modes without interrupting the stroke underway.

All 454 selected tests passed across three builds. They cover direct shortcuts, focus, the cursor, Undo and the Photato API. Live Photoshop keyboard comparisons remain open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-557) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_557.md).

## 2026-11-18 — Step 556 — Behind and Clear

The Brush Mode picker now has Behind and Clear. Behind puts paint underneath existing pixels. Clear removes their alpha and also works with Pencil. You can hold the grave-accent key to use Clear for a Brush stroke.

All 418 selected tests passed across three builds. They check pixel math, transparent and locked layers, Undo, replay and the Photato API. Exact Photoshop pixel comparisons remain open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-556) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_556.md).
