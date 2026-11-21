# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **710** · The 10 most recent entries, newest first.

## 2026-11-21 — Step 710 — Replace a masked background with colour or artwork

After Remove Background, the contextual bar and Properties offer Background Color and Import Background. Photato adds an editable Solid Color layer or an embedded Smart Object below the masked subject. Import supports Fill Canvas, Fit Inside Canvas and Original Size. Both actions work without a model and take one Undo step.

Desktop and Photato HTTP edits produced identical RGBA8 samples and preserved the subject layer. Solid Color remained editable through native, PSD and PSB round trips at RGB8, RGB16 and RGB32. Imported artwork retained the original bytes and exact rendered samples in all three formats for the tested placement modes. A 300,000 × 8 PSB reopened through the native file opener with opaque outer edges and the unmodified subject mask. Four 576 × 376 PSD and PSB merged previews matched all 3,465,216 RGBA bytes in the corresponding PNGs using an independent reader.

Installed Photoshop identified itself as 27.2.0. Its scripting interface timed out on both owned reopen probes and a read-only JavaScript version probe. Photoshop reopening, reference placement and interpolation fidelity, interactive colour panel and Import dialog behavior, and non-RGB contexts still need qualification. The editable background placement marker is supported starting with Photato build 710. The manual background workflow has no dedicated Adobe v2 route in the referenced contract. The existing Adobe-compatible remove-background colour output and create-composite layer operations remain available.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-710) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_710.md).

## 2026-11-21 — Step 709 — Generate and iterate on a local background

Generate Background now offers a local model after Remove Background. Photato places the result on an editable Smart Object below the masked subject. The document retains the original subject context for Generate More and Generate Similar after reopening. The Image Playground workflow is available through its Apple Intelligence action.

The Vision and Runway test on project artwork preserved 422,792 fully opaque subject pixels and filled 578,461 transparent pixels. Both results retained their stacks and rendered samples after a Photato and PSB reopen. A signed App Sandbox harness passed the same owned-artwork checks. The native action and Photato HTTP API matched byte for byte in a separate same-seed test. A 6,200-pixel-wide test preserved editable placement and opacity at the far corner. A 300,000 × 8 PSB retained the same outer-edge pixels and editable source when reopened. At actual size, the RGB8, RGB16 and linear RGB32 fixtures preserved their rendered bytes through native, PSD and PSB reopening.

The local model samples the document within a 512-pixel frame and scales the result to the canvas. Dense maximum-area export, lighting and texture quality, dedicated background colour and import choices, and Firefly output equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-709) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_709.md).

## 2026-11-21 — Step 708 — Add more variations to a saved wide expansion

Generate More and Generate Similar now work on prompted Generative Expand layers that used overlapping model windows. The embedded PSB stores the original perimeter pixels, including when the edit starts with one result. Changing the underlying layers after saving leaves the model context intact. The edit keeps the earlier results and the current outer mask.

A 4,104-pixel-wide fixture matched every original Float32 model input after reopening in native, PSD and PSB, even after edits to the base pixels and mask. The real Runway model reproduced the first build 707 result byte for byte on a 4,104 × 120 image, then generated a new result from that saved reference. The proof kept both results, 393,984 original pixels, the edited mask and one-step Undo. The two results reopened byte for byte in PSB and Photato. The native Properties draft accepted the saved reference. The prepared edit and HTTP produced the same RGBA8 results and mask after reopening. A signed App Sandbox proof retained all 11 model inputs and 73,836 original pixels in PSB at each of RGB8, RGB16 and RGB32. The first result took 312.2 seconds and the similar variation took 164.8 seconds while build qualification ran.

Older tiled files still open and retain the saved results. They lack the captured source needed to regenerate. Large dense borders, long-range prompt continuity, rotation, blank-prompt alternatives and Adobe Firefly output equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-708) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_708.md).

## 2026-11-21 — Step 707 — Reuse the local prompt model across an editing job

Prompted Generative Expand now keeps one isolated worker and loaded model for all windows and alternatives in an edit. Cancel still aborts the edit and removes its temporary files. The desktop and Photato HTTP commands use the same worker.

A paired four-request Core ML benchmark used 89.9 seconds with fresh workers and 80.9 seconds with one reusable worker. All four Float32 RGBA buffers matched exactly. A signed App Sandbox harness reproduced all four buffers. A separate 4,104-pixel-wide two-alternative run took 547.8 seconds and reproduced both build 706 alternatives and the editable mask byte for byte after reopening. A cancellation test forced a non-cooperative test child to exit and verified scratch cleanup.

Generation still takes time for large borders. Prompt quality across distant windows, saved tiled context for Generate More and Generate Similar, and Adobe Firefly output equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-707) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_707.md).

## 2026-11-21 — Step 706 — Extend wide borders with overlapping model windows

Generative Expand now processes wider and deeper borders in overlapping model windows. The Crop tool and Photato API use the same engine and apply the expansion as one Undo step. Multiple prompted results share an editable mask and appear as layer comps in one embedded PSB.

LaMa preserved all 720,896 original pixels on a 5,632 × 128 source and added 225,280 pixels. The mean step at the model-window joins was 0.47 RGB8 levels. A real 30,144-pixel-wide outpaint preserved 482,304 original pixels and reopened with identical composite bytes in the native format and PSB. A separate 300,000 × 16 outpaint added eight rows at Photoshop’s published maximum canvas width, preserving all 4,800,000 originals through native and PSB reopening. The native Crop action and HTTP produced identical pixels on a separate 4,160-pixel-wide run. Both prompted alternatives on the real 4,104-pixel-wide input stayed distinct and editable after native and PSB reopening. A deterministic deep four-sided test covered editable PSD/PSB alternatives, joined pixels and interior transparency. A separate PSB test retained exact RGB16 and RGB32 sample words.

Tiled alternatives retain their results and mask for editing. Generate More and Generate Similar after reopening still require the single-patch saved context. The two-alternative prompt proof took 572 seconds with other qualification jobs running. Reusing the prompted worker between windows remains a performance task. Dense maximum-area generation, prompted quality across distant windows and Firefly output equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-706) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_706.md).

## 2026-11-21 — Step 705 — Extend the canvas with local generation

Generative Expand is available in Crop after dragging the handles outward. Use a blank prompt or describe the new area. Photato adds an editable masked layer and commits the canvas and generation in one Undo step. Prompted results can be switched in Properties. The Photato API uses the same editing path.

On the owned apple image, each local model preserved all 65,536 original pixels and added 25,632 opaque pixels. The largest mean RGB8 step immediately outside the old canvas dropped from 88.29 levels with LaMa512 and 54.54 with prompted generation to 0.00. Photato reopened the editable PSD and PSB results with identical RGBA bytes. The native editor and local HTTP route produced identical bytes at the same seed. Both models also passed the file and Undo checks in an ad hoc signed App Sandbox test harness.

This generation pass requires the new border’s bounding rectangle to fit within 4,194,304 pixels and 4,096 pixels per side. Local models can leave artifacts near the outer edge of the addition. Larger multi-edge generation, rotation, inward cropping during expansion, multiple blank-prompt results and Firefly equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-705) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_705.md).

## 2026-11-21 — Step 704 — Generate similar variations from a saved local fill

Generate Similar uses a chosen variation as the reference for another batch in the same local Generative Fill layer. Open Variation actions in Properties or pass the reference ID through the Photato API. The earlier results, mask and reference stay editable after reopening, and one Undo removes the new batch.

On one owned example, the mean RGB8 difference from the reference fell from 52.91 levels with full regeneration to 10.32 with conditioning at the same seed. Changing the reference changed the generated output by 46.57 levels on average. The sandboxed comparison preserved 49,283 pixels outside the original mask and the four earlier variation records. The generated result and reference ID survived reopening in Photato, PSD and PSB. The native editor and HTTP produced identical RGBA output when they used the same reference and seed on a reopened PSD.

484 of 485 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The existing PhotoCraft layer-effect fixture repeated its 118 assertions from build 703 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. Generate Similar in this build supports Photato’s local prompted Generative Fill layers with saved context. Adobe also documents it for Expand, Background and Generate Image. Adobe Execute Actions compatibility and Firefly output equivalence remain open. The installed Photoshop session timed out on a read-only scripting query.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-704) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_704.md).

## 2026-11-21 — Step 703 — Add batches to an existing Generative Fill layer

Generate More adds another batch to the selected Generative Fill layer. Edit the prompt in Properties or send the layer ID through the Photato API. New results use the original selection and image samples after reopening. Earlier results and the current layer mask stay editable. One Undo removes the batch.

The reopened-layer tests preserve the earlier result bytes, original inference inputs, current mask, placement and selection across Photato, PSD and PSB at RGB8, RGB16 and RGB32. The sandboxed Core ML probe generated four distinct results. Both original results matched the build 702 fixture at the same seeds. Each result preserved all 49,283 pixels outside the original selection and reopened byte for byte in all three formats in Photato. The editor and HTTP also produced identical RGBA output when adding to a reopened PSD at the tested seed.

483 of 484 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 702 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. A layer holds up to 64 variations within the Smart Object storage limits. Layers saved by build 702 retain variation selection and lack the captured context needed for new batches. The installed Photoshop session timed out on a read-only query. Generate Similar, the Adobe Execute Actions descriptor, and Firefly output equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-703) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_703.md).

## 2026-11-21 — Step 702 — Keep editable Generative Fill variations

Prompted Generative Fill can now keep up to three results in one editable masked layer. Choose a variation in Properties or through the Photato API. The original generation takes one Undo step.

Synthetic RGB8, RGB16 and RGB32 tests preserved exact rendered samples, mask coverage and the selected variation after reopening Photato, PSD and PSB files in Photato. The real Core ML model generated identical first results through the editor and HTTP at the tested seed. A separate sandboxed test generated three different results and preserved all 49,283 pixels outside the selection in each. Each of those real variations also matched its original RGBA bytes after reopening in all three formats in Photato.

482 of 483 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 701 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. Generating more results into the same layer, Generate Similar, the Adobe Execute Actions descriptor, and Firefly pixel equivalence remain open. The installed Photoshop session timed out on two read-only scripting queries. Adobe's desktop documentation confirms variation selection in Properties.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-702) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_702.md).

## 2026-11-21 — Step 701 — Blend Generative Fill selection edges

Generative Fill now uses opaque pixels around the selection to reduce color seams. The correction tapers into the selected area. The editor and Photato API preserve the editable mask and one-step Undo.

Mean RGB8 drift across 505 boundary samples fell from 4.39 to 0.31 levels on the apple and from 3.95 to 0.24 on the mug. Each result preserved all 49,283 protected samples and all 9,898 tested interior samples. Both fills retained exact pixels and editable masks when reopened in Photato as native, PSD and PSB files. A synthetic fill exercised a 4,194,304-pixel selection on a 300,000 × 300,000 sparse canvas.

480 of 481 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 700’s assertions. Both signed preview slices opened offscreen, and the checked-in Xcode project built in arm64 Debug. Application-managed variation sets and the Adobe Execute Actions descriptor remain open. A separate seed probe hit a Core ML GPU exception once and succeeded on retry. The installed Photoshop session timed out on a read-only scripting query, so Photoshop output equivalence has yet to be verified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-701) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_701.md).
