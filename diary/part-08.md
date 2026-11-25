[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-09.md) · [Next page](part-07.md)

## 2026-11-21 — Step 714 — Guide Generate Image with Style and Composition references

Generate Image accepts an optional reference. Style transfers colours and textures to the image described by the prompt. Composition uses edges to guide layout during generation. Photato keeps the reference with the editable Smart Object for Generate More and Generate Similar. The authenticated Photato API uses the same edit and history.

Changing only the Composition reference moved the measured orange centre from x=151.5 to x=386.5 in a 512-pixel image. Changing only the Style reference moved mean red minus blue from 0.506 to -0.506. Editor and authenticated HTTP pixels matched exactly at the same seed for both modes. All four owned renders and their embedded reference samples survived Photato, PSD, and PSB reopens. An independent merged-preview reader matched each PSD and PSB to its PNG. Generate More after reopening PSB matched a fresh generation at the same seed and retained the earlier result. The optimized Apple Silicon worker and a signed sandbox harness each reproduced all four outputs byte for byte.

Local models are optional on Apple Silicon with macOS 26 or later. The Style model operates at 224 pixels internally and can soften fine detail. Composition can add objects when edges are ambiguous. The Photoshop 27.2.0 AppleEvent query timed out. Direct Photoshop reopen, Firefly output fidelity, the Firefly ActionJSON descriptor, keyboard and assistive-technology testing remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-714) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_714.md).

## 2026-11-21 — Step 713 — Edit a whole image with local instructions and saved variations

Edit → Prompt to Edit and the canvas action use the selected pixel layer and a text instruction to create alternatives on this Mac. The new editable Smart Object preserves the original layer and source alpha. The original is hidden and can be restored in one Undo. Generate More uses the saved reference. Edit This Variation starts from a chosen result. The Photato HTTP API shares the same edit and history.

The real InstructPix2Pix model delivered identical same-seed pixels through the native editor and authenticated HTTP API. A saved second variation matched the same seed run independently.On a locally generated 512 × 512 still life, a blue-teapot instruction moved the average red-minus-blue value in the sampled pot from 0.879 to −0.775. The model also changed some surrounding colours. Photato, PSD and PSB reopened with both variants and identical rendered bytes. An independent reader compared all 2,097,152 merged RGBA bytes from the PSD and PSB previews to the PNG. A 300,000 × 8 PSB kept the original source, editable placement and exact pixels at both sampled edges.

The local workflow uses the optional 512 × 512 Core ML model on Apple Silicon and macOS 26 or later. Current input support is still RGB and visible root pixel or supported generative layers outside clipping stacks. The installed Photoshop 27.2.0 document query timed out. Direct Photoshop reopening, Adobe model output equality, shared Firefly action descriptors, and live keyboard and assistive technology checks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-713) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_713.md).

## 2026-11-21 — Step 712 — Generate editable images from a text prompt on-device

Edit → Generate Image and the canvas controls now generate artwork from a text prompt on eligible Macs. The optional local Core ML model creates one to three alternatives in a single editable Smart Object and preserves the original layers and selection. Properties switches variations and can generate more from the prompt or generate similar results from a saved variation. The Photato API shares the same prepared edit and history. The existing Apple Intelligence route remains available.

The real local model produced identical same-seed rendered pixels through the native editor and authenticated HTTP API. Edited test documents retained their variations in Photato, PSD and PSB at RGB8, RGB16 and RGB32. A 768 × 512 locally generated still life retained both variants and identical rendered bytes across all three formats. An independent reader matched all 3,145,728 merged RGBA bytes in the PSD and PSB previews to the PNG. A 300,000 × 8 PSB reopened with exact edge samples, editable placement and the original square model resolution.

The on-device model generates at 512 × 512 and offers a centered canvas crop. Adobe’s model picker and hosted Firefly output have separate engines and remain unqualified. The installed Photoshop 27.2.0 document query timed out. Direct Photoshop reopening, live keyboard and assistive technology checks, and Adobe-compatible Generate Image action coverage remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-712) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_712.md).

## 2026-11-21 — Step 711 — Match a subject to its background with editable Harmonize variations

Harmonize adds Subtle, Balanced and Ambient colour, tone and contact-shadow variations for a pixel subject over a background. Use the contextual bar, Layer menu or Properties. The original subject and mask are retained. The group contains ordinary editable Curves and separate shadow layers. Properties switches alternatives and each change can be undone.

The native editor and Photato HTTP commands produced the same RGBA8 results from a selected pixel mask. All three variations and rendered samples survived native, PSD and PSB reopening in the RGB8, RGB16 and RGB32 test fixtures. On the 1,024 × 1,024 project mascot, all three formats reopened with identical rendered bytes. The independent reader matched all 8,388,608 merged RGBA bytes in the two Photoshop-format files to the PNG. A 300,000 × 28 file retained the original mask, editable variations and matching sampled regions through native and paged PSB reopening.

Harmonize estimates the adjustment and shadow locally. Adobe documents its separate Firefly model. No corresponding public Harmonize request schema was found in the pinned Photoshop v2 contract. The installed Photoshop reported 27.2.0, but its document scripting timed out. Firefly output equivalence, direct Photoshop reopening, and live keyboard and assistive technology checks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-711) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_711.md).

## 2026-11-21 — Step 710 — Replace a masked background with colour or artwork

After Remove Background, the contextual bar and Properties offer Background Color and Import Background. Photato adds an editable Solid Color layer or an embedded Smart Object below the masked subject. Import supports Fill Canvas, Fit Inside Canvas and Original Size. Both actions work without a model and take one Undo step.

Desktop and Photato HTTP edits produced identical RGBA8 samples and preserved the subject layer. Solid Color remained editable through native, PSD and PSB round trips at RGB8, RGB16 and RGB32. Imported artwork retained the original bytes and exact rendered samples in all three formats for the tested placement modes. A 300,000 × 8 PSB reopened through the native file opener with opaque outer edges and the unmodified subject mask. Four 576 × 376 PSD and PSB merged previews matched all 3,465,216 RGBA bytes in the corresponding PNGs using an independent reader.

Installed Photoshop identified itself as 27.2.0. Its scripting interface timed out on both owned reopen probes and a read-only JavaScript version probe. Photoshop reopening, reference placement and interpolation fidelity, interactive colour panel and Import dialog behavior, and non-RGB contexts still need qualification. The editable background placement marker is supported starting with Photato build 710. The manual background workflow has no dedicated Adobe v2 route in the referenced contract. The existing Adobe-compatible remove-background colour output and create-composite layer operations remain available.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-710) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_710.md).

## 2026-11-21 — Step 709 — Generate and iterate on a local background

Generate Background now offers a local model after Remove Background. Photato places the result on an editable Smart Object below the masked subject. The document retains the original subject context for Generate More and Generate Similar after reopening. The Image Playground workflow is available through its Apple Intelligence action.

The Vision and Runway test on project artwork preserved 422,792 fully opaque subject pixels and filled 578,461 transparent pixels. Both results retained their stacks and rendered samples after a Photato and PSB reopen. A signed App Sandbox harness passed the same owned-artwork checks. The native action and Photato HTTP API matched byte for byte in a separate same-seed test. A 6,200-pixel-wide test preserved editable placement and opacity at the far corner. A 300,000 × 8 PSB retained the same outer-edge pixels and editable source when reopened. At actual size, the RGB8, RGB16 and linear RGB32 fixtures preserved their rendered bytes through native, PSD and PSB reopening.

The local model samples the document within a 512-pixel frame and scales the result to the canvas. Dense maximum-area export, lighting and texture quality, dedicated background colour and import choices, and Firefly output equivalence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-709) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_709.md).

## 2026-11-21 — Step 708 — Add more variations to a saved wide expansion

Generate More and Generate Similar now work on prompted Generative Expand layers that used overlapping model windows. The embedded PSB stores the original perimeter pixels, including when the edit starts with one result. Changing the underlying layers after saving leaves the model context intact. The edit keeps the earlier results and the current outer mask.

A 4,104-pixel-wide fixture matched every original Float32 model input after reopening in native, PSD and PSB, even after edits to the base pixels and mask. The real Runway model reproduced the first build 707 result byte for byte on a 4,104 × 120 image, then generated a new result from that saved reference. The proof kept both results, 393,984 original pixels, the edited mask and one-step Undo. The two results reopened byte for byte in PSB and Photato. The native Properties draft accepted the saved reference. The prepared edit and HTTP produced the same RGBA8 results and mask after reopening. A signed App Sandbox proof retained all 11 model inputs and 73,836 original pixels in PSB at each of RGB8, RGB16 and RGB32. The first result took 312.2 seconds and the similar variation took 164.8 seconds while build qualification ran.

Older tiled files still open and retain the saved results. They lack the captured source needed to regenerate. Large dense borders, long-range prompt continuity, rotation, blank-prompt alternatives and Adobe Firefly output equivalence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-708) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_708.md).

## 2026-11-21 — Step 707 — Reuse the local prompt model across an editing job

Prompted Generative Expand now keeps one isolated worker and loaded model for all windows and alternatives in an edit. Cancel still aborts the edit and removes its temporary files. The desktop and Photato HTTP commands use the same worker.

A paired four-request Core ML benchmark used 89.9 seconds with fresh workers and 80.9 seconds with one reusable worker. All four Float32 RGBA buffers matched exactly. A signed App Sandbox harness reproduced all four buffers. A separate 4,104-pixel-wide two-alternative run took 547.8 seconds and reproduced both build 706 alternatives and the editable mask byte for byte after reopening. A cancellation test forced a non-cooperative test child to exit and verified scratch cleanup.

Generation still takes time for large borders. Prompt quality across distant windows, saved tiled context for Generate More and Generate Similar, and Adobe Firefly output equivalence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-707) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_707.md).

## 2026-11-21 — Step 706 — Extend wide borders with overlapping model windows

Generative Expand now processes wider and deeper borders in overlapping model windows. The Crop tool and Photato API use the same engine and apply the expansion as one Undo step. Multiple prompted results share an editable mask and appear as layer comps in one embedded PSB.

LaMa preserved all 720,896 original pixels on a 5,632 × 128 source and added 225,280 pixels. The mean step at the model-window joins was 0.47 RGB8 levels. A real 30,144-pixel-wide outpaint preserved 482,304 original pixels and reopened with identical composite bytes in the native format and PSB. A separate 300,000 × 16 outpaint added eight rows at Photoshop’s published maximum canvas width, preserving all 4,800,000 originals through native and PSB reopening. The native Crop action and HTTP produced identical pixels on a separate 4,160-pixel-wide run. Both prompted alternatives on the real 4,104-pixel-wide input stayed distinct and editable after native and PSB reopening. A deterministic deep four-sided test covered editable PSD/PSB alternatives, joined pixels and interior transparency. A separate PSB test retained exact RGB16 and RGB32 sample words.

Tiled alternatives retain their results and mask for editing. Generate More and Generate Similar after reopening still require the single-patch saved context. The two-alternative prompt proof took 572 seconds with other qualification jobs running. Reusing the prompted worker between windows remains a performance task. Dense maximum-area generation, prompted quality across distant windows and Firefly output equivalence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-706) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_706.md).

## 2026-11-21 — Step 705 — Extend the canvas with local generation

Generative Expand is available in Crop after dragging the handles outward. Use a blank prompt or describe the new area. Photato adds an editable masked layer and commits the canvas and generation in one Undo step. Prompted results can be switched in Properties. The Photato API uses the same editing path.

On the owned apple image, each local model preserved all 65,536 original pixels and added 25,632 opaque pixels. The largest mean RGB8 step immediately outside the old canvas dropped from 88.29 levels with LaMa512 and 54.54 with prompted generation to 0.00. Photato reopened the editable PSD and PSB results with identical RGBA bytes. The native editor and local HTTP route produced identical bytes at the same seed. Both models also passed the file and Undo checks in an ad hoc signed App Sandbox test harness.

This generation pass requires the new border’s bounding rectangle to fit within 4,194,304 pixels and 4,096 pixels per side. Local models can leave artifacts near the outer edge of the addition. Larger multi-edge generation, rotation, inward cropping during expansion, multiple blank-prompt results and Firefly equivalence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-705) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_705.md).

## 2026-11-21 — Step 704 — Generate similar variations from a saved local fill

Generate Similar uses a chosen variation as the reference for another batch in the same local Generative Fill layer. Open Variation actions in Properties or pass the reference ID through the Photato API. The earlier results, mask and reference stay editable after reopening, and one Undo removes the new batch.

On one owned example, the mean RGB8 difference from the reference fell from 52.91 levels with full regeneration to 10.32 with conditioning at the same seed. Changing the reference changed the generated output by 46.57 levels on average. The sandboxed comparison preserved 49,283 pixels outside the original mask and the four earlier variation records. The generated result and reference ID survived reopening in Photato, PSD and PSB. The native editor and HTTP produced identical RGBA output when they used the same reference and seed on a reopened PSD.

484 of 485 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The existing PhotoCraft layer-effect fixture repeated its 118 assertions from build 703 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. Generate Similar in this build supports Photato’s local prompted Generative Fill layers with saved context. Adobe also documents it for Expand, Background and Generate Image. Adobe Execute Actions compatibility and Firefly output equivalence remain open. The installed Photoshop session timed out on a read-only scripting query.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-704) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_704.md).

## 2026-11-21 — Step 703 — Add batches to an existing Generative Fill layer

Generate More adds another batch to the selected Generative Fill layer. Edit the prompt in Properties or send the layer ID through the Photato API. New results use the original selection and image samples after reopening. Earlier results and the current layer mask stay editable. One Undo removes the batch.

The reopened-layer tests preserve the earlier result bytes, original inference inputs, current mask, placement and selection across Photato, PSD and PSB at RGB8, RGB16 and RGB32. The sandboxed Core ML probe generated four distinct results. Both original results matched the build 702 fixture at the same seeds. Each result preserved all 49,283 pixels outside the original selection and reopened byte for byte in all three formats in Photato. The editor and HTTP also produced identical RGBA output when adding to a reopened PSD at the tested seed.

483 of 484 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 702 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. A layer holds up to 64 variations within the Smart Object storage limits. Layers saved by build 702 retain variation selection and lack the captured context needed for new batches. The installed Photoshop session timed out on a read-only query. Generate Similar, the Adobe Execute Actions descriptor, and Firefly output equivalence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-703) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_703.md).

## 2026-11-21 — Step 702 — Keep editable Generative Fill variations

Prompted Generative Fill can now keep up to three results in one editable masked layer. Choose a variation in Properties or through the Photato API. The original generation takes one Undo step.

Synthetic RGB8, RGB16 and RGB32 tests preserved exact rendered samples, mask coverage and the selected variation after reopening Photato, PSD and PSB files in Photato. The real Core ML model generated identical first results through the editor and HTTP at the tested seed. A separate sandboxed test generated three different results and preserved all 49,283 pixels outside the selection in each. Each of those real variations also matched its original RGBA bytes after reopening in all three formats in Photato.

482 of 483 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 701 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. Generating more results into the same layer, Generate Similar, the Adobe Execute Actions descriptor, and Firefly pixel equivalence remain open. The installed Photoshop session timed out on two read-only scripting queries. Adobe's desktop documentation confirms variation selection in Properties.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-702) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_702.md).

## 2026-11-21 — Step 701 — Blend Generative Fill selection edges

Generative Fill now uses opaque pixels around the selection to reduce color seams. The correction tapers into the selected area. The editor and Photato API preserve the editable mask and one-step Undo.

Mean RGB8 drift across 505 boundary samples fell from 4.39 to 0.31 levels on the apple and from 3.95 to 0.24 on the mug. Each result preserved all 49,283 protected samples and all 9,898 tested interior samples. Both fills retained exact pixels and editable masks when reopened in Photato as native, PSD and PSB files. A synthetic fill exercised a 4,194,304-pixel selection on a 300,000 × 300,000 sparse canvas.

480 of 481 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 700’s assertions. Both signed preview slices opened offscreen, and the checked-in Xcode project built in arm64 Debug. Application-managed variation sets and the Adobe Execute Actions descriptor remain open. A separate seed probe hit a Core ML GPU exception once and succeeded on retry. The installed Photoshop session timed out on a read-only scripting query, so Photoshop output equivalence has yet to be verified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-701) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_701.md).

## 2026-11-21 — Step 700 — Add prompted Generative Fill on Apple Silicon

Generative Fill accepts a text prompt and selection mask in Photato’s native editing sheet and HTTP API. An optional Core ML model generates the content locally. The existing blank-prompt mode uses LaMa512.

Using the same source, selection and seed, a red-apple prompt and a blue-mug prompt produced distinct subjects. The native and authenticated HTTP paths matched RGB8 output bytes for the same prompt and seed. Both prompts preserved all 49,283 protected pixels. The editable mask retained feathering and a protected hole, and one Undo restored the original document. Both edits reopened in Photato with exact RGB8 composites and mask coverage in native, PSD and PSB files.

477 of 478 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 699’s assertions. Both signed preview slices opened offscreen. The checked-in Xcode project built in arm64 Debug, and the sheet was inspected offscreen in Light and Dark. Hard selection edges can show a tonal seam. Editable variation sets, Adobe Execute Actions descriptor compatibility and Firefly output equivalence remain open. The installed Photoshop session timed out on both scripting queries.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-700) · [Model setup](../PhotoCraftSwift/docs/LOCAL_GENERATIVE_FILL.md).

## 2026-11-21 — Step 699 — Add local Generative Fill from surrounding pixels

Generative Fill now uses an optional Apple Silicon Core ML model to fill a selection from surrounding pixels. Photato places the result above the visible stack on a raster layer with an editable mask and one Undo step.

The pinned LaMa512 model ran in Debug and optimized Apple Silicon builds. The native transaction and authenticated loopback API returned identical composite samples on the same RGB8 fixture. Tests at RGB8, RGB16 and RGB32 matched protected pixels and every output-mask sample. The owned example retained the editable mask on native, PSD and PSB reopening in Photato.

476 of 477 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with identical assertions in build 698. Both signed preview slices opened offscreen. The local provider fills from context. Text prompts, variant sets and Adobe Execute Actions support remain open. The installed Photoshop session timed out, so Adobe output and physical workflow comparison remain pending.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-699) · [Details](../PhotoCraftSwift/docs/GENERATIVE_FILL_699.md).

## 2026-11-21 — Step 698 — Read raster alpha directly for regional Drop Shadows

Regional Drop Shadow preparation reads coverage directly from eligible raster tiles and applies the same mask sampler as the layer compositor. The spread filter skips covered samples whose distance cannot be improved by a neighbor.

The coverage copy matched the isolated compositor in RGB8, RGB16 and RGB32, including translated layers and feathered pixel masks. Dense noisy Fit fixtures with and without transparent holes matched each architecture's build 697 Float32 composite and soft-proof samples byte for byte.

475 of 476 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with the same assertions in build 697. Both signed preview slices opened offscreen. Noisy previews still require per-pixel evaluation. Whole-document Fit on a maximum-size dense file still needs further work. The local Photoshop document query timed out, so Adobe shadow pixels and Fit sampling remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-698) · [Details](../PhotoCraftSwift/docs/DENSE_SHADOW_COVERAGE_698.md).

## 2026-11-21 — Step 697 — Reduce Fit and proof previews for large uniform Drop Shadows

Large RGB previews reuse uniform Drop Shadow spans while rendering the edges and output affected by sparse raster or mask changes. Eligible reduced HTTP viewports use the same path.

RGB8, RGB16 and RGB32 reductions with raster and mask edits matched the streamed renderer. The native Fit view and explicit HTTP composite, green-channel and soft-proof PNGs matched on a 300,000 × 300,000 document. The 70,000 × 520 benchmark reproduced each architecture's build 696 Float32 composite and soft-proof samples byte for byte.

474 of 475 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The same original PhotoCraft effect fixture failed with identical assertions in build 696. Both signed preview slices opened offscreen. A coordinate-dependent shadow, such as one with noise, still needs the ordinary renderer. Broad edited areas and unsupported stacks also retain their prior rendering path. The local Photoshop document query timed out, so Adobe Fit sampling and Adobe shadow pixels remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-697) · [Details](../PhotoCraftSwift/docs/DENSE_SHADOW_FIT_697.md).

## 2026-11-21 — Step 696 — Render Drop Shadows in bounded canvas regions

Basic and advanced Drop Shadows now render on large RGB canvases. A viewport prepares the shifted source and the required filter margin.

Twenty-four RGB8, RGB16 and RGB32 viewport comparisons matched the whole-canvas renderer at tile and document edges. Another 384 varied viewport comparisons matched on each optimized architecture. A sparse 300,000 × 300,000 canvas found a 30,000-pixel displaced shadow and retained under 4 MiB of output tiles in the test. The native menu, advanced controls, preview, Undo, local HTTP edit and PNG were verified on that canvas size. A 4,096 × 4,096 editable PSB reopened with the same effect settings and regional pixels. All 138 prior effect fixtures produced identical direct and imported-project output on both architectures.

471 of 472 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture reproduced its existing assertions. Both signed macOS 14+ preview slices opened offscreen. The native Layer Style sheet was inspected offscreen in Light and Dark on the maximum-size document. The installed Photoshop instance timed out on a document query. Direct Adobe pixel comparison remains open. Very wide filters retain a scratch budget. A shadow already filling an entire canvas can require additional preview work. Other effects still use their existing whole-canvas limits.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-696) · [Details](../PhotoCraftSwift/docs/REGIONAL_DROP_SHADOW_696.md).

## 2026-11-21 — Step 695 — Keep advanced Drop Shadows editable in PSD and PSB

Drop Shadow contour corners, anti-aliasing, noise and knockout now work through the editor and the Adobe-compatible create-composite route. Supported shadows remain editable in PSD and PSB.

A native editor test covers Preview, commit and Undo/Redo. The Photato style-patch and Adobe-compatible job tests preserve the contour and its corner flags. Owned 8-, 16- and 32-bit files reopen with their controls and Photato renders unchanged. An independent descriptor reader checked noise, knockout, anti-aliasing, local light, and all five contour points in six exports. The complete files match across all three builds tested. All 138 prior effect fixtures produced identical direct and imported-project output on both architectures.

468 of 469 selected tests passed in arm64 Debug, optimized arm64 and Intel under Rosetta. The same strict original PhotoCraft effect fixture still fails with identical assertions. The two unrelated hard-coded Automation count expectations now use the shared catalog count. The checked-in Xcode project built in arm64 Debug with signing disabled. Both signed macOS 14+ preview slices opened offscreen. The changed controls were inspected offscreen in Light and Dark. The installed Photoshop instance timed out on a document query. Exact Adobe shadow opacity, curve interpolation, anti-aliasing and randomized noise output still need Adobe-authored reference measurements. Large-canvas advanced style processing and advanced interchange for other effects remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-695) · [Details](../PhotoCraftSwift/docs/ADVANCED_DROP_SHADOW_695.md).

## 2026-11-21 — Step 694 — Write layer styles by tile and reuse opacity checks

Advanced layer effects write their final pixels by tile. Ordinary raster writes also reuse an opacity result owned by a single surface.

Both tested wide oblique Pattern Overlay fits and the separate native Fit and soft-proof PNGs match build 693 byte for byte. The RGB8, RGB16 and RGB32 layer-style regression probe matched the previous build for all 138 cases in both direct rendering and imported-project rendering. The mapped-raster tests check that an edited copy and its original can certify opacity independently, and that tile writes reproduce scalar storage in each tested sample encoding and depth.

462 of 465 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The three inherited failures reproduced the same assertions: two outdated Automation count expectations and one strict original PhotoCraft effect fixture. All 27 additional Brush Dynamics and canvas diagnostics tests passed in Debug. The Xcode Debug build and both ad hoc signed macOS 14+ preview slices opened workspaces offscreen. The installed Photoshop instance timed out on a document query. The saved Photoshop Pattern Overlay reference still passes. Live Photoshop Fit sampling and physical editing cadence remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-694) · [Details](../PhotoCraftSwift/docs/STYLE_PIXEL_WRITES_694.md).

## 2026-11-21 — Step 693 — Reuse prepared pattern samples across render patches

Pattern Fill layers and Pattern Overlays share prepared source texels across patches of the same composition.

The 5 × 5 and 512 × 512 oblique sources matched build 692 byte for byte in both optimized architectures. Native Fit and soft proof for the separate 70,000 × 520 reference document produced the same PNGs as build 692. Tests covered negative wrap, transparent texels, linked origins, RGB8 reduced grids, source replacement and the cache budget.

460 of 463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 692's assertions. Four additional storage tests passed in Debug. Both signed macOS 14+ preview slices launched offscreen. Xcode built the corrected project directly in arm64 Debug with signing disabled, then the built app opened a workspace offscreen. Wide nonperiodic fit still evaluates each source pixel. Interactive timing on fully covered maximum-size documents and Photoshop zoom comparison remain open. The local Photoshop document query timed out.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-693) · [Details](../PhotoCraftSwift/docs/PATTERN_SAMPLING_693.md).

## 2026-11-21 — Step 692 — Reduce wide oblique Pattern Overlays in bounded patches

Fit on Screen and the local PNG overview reduce supported wide oblique Pattern Overlays without retaining the full composite.

Fractional edges matched retained rendering at RGB8, RGB16 and RGB32 in the tested composite, channel and proof views. The proof test also preserved a sparse implicit backdrop across the maximum canvas. Authenticated composite, channel and proof PNGs matched their retained native controls. The separate AppKit probe fitted and proofed a fully covered 70,000 × 520 document on both architectures.

458 of 461 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 691's assertions. Both signed macOS 14+ preview slices launched offscreen. Large nonperiodic fits still evaluate source pixels and can take seconds or longer. End-to-end timing for a fully covered maximum-size oblique Fit remains open. The Photoshop 2026 document-count query timed out, leaving live zoom comparison open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-692) · [Details](../PhotoCraftSwift/docs/PAGED_PATTERN_REDUCTION_692.md).

## 2026-11-21 — Step 691 — Fit quarter-turn Pattern Overlays on large canvases

Fit on Screen and the local PNG overview now handle eligible quarter-turn Pattern Overlays on canvases up to 300,000 × 300,000.

Actual-size crops from four parts of the canvas matched the ordinary compositor in RGB8, RGB16 and RGB32. Six angle, scale and phase combinations also matched an independent whole-period area control. The native test exercised Fit, pan, Brush, Undo and the authenticated overview. An owned 90° probe with a sparse edit produced identical fit and actual-size bytes across all three test configurations.

455 of 458 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 690’s assertions. Both signed macOS 14+ preview slices launched offscreen. The optimization requires a dyadic scale and Float32-safe phase on both pattern axes. Integral-phase 100% placements that fail this proof and oblique angles retain the existing path. Large nonperiodic Fit on Screen and live Photoshop zoom comparison remain open. The installed Photoshop 2026 document-count query timed out.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-691) · [Details](../PhotoCraftSwift/docs/QUARTER_TURN_PATTERN_691.md).

## 2026-11-21 — Step 690 — Bound rotated Pattern Overlay viewports

Rotated and nonperiodic Pattern Overlay renders in bounded document viewports on canvases up to 300,000 × 300,000.

At actual size, overlapping panned views matched at 8-, 16-, and 32-bit depth. A 31° pattern at 56% matched the ordinary renderer at actual size, at fractional zoom and above the direct in-memory patch limit. The native canvas and all three local PNG viewport routes produced identical PNGs in the tested RGB8 composite, channel and proof views. Eighteen samples from the saved Adobe Photoshop PSD also matched.

453 of 456 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The same three failures reproduced the build 689 assertions. Both signed macOS 14+ preview slices launched offscreen. Fit-to-window on very large nonperiodic canvases still uses full rendering. The bounded route has a source budget of 16,777,216 pixels and an output budget of 4,194,304 pixels. Photoshop’s document-count query timed out, so direct comparison of live zoom presentation remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-690) · [Details](../PhotoCraftSwift/docs/PATTERN_VIEWPORT_690.md).

## 2026-11-21 — Step 689 — Preview opaque Pattern Overlay on large canvases

The native editor and local API preview supported opaque Pattern Overlay on canvases up to 300,000 × 300,000.

Fit uses the area covered by each screen pixel. At 100% the preview reads the same samples as a full render. Painted pixels, aligned pixel masks and translated raster layers remain visible. Tests also checked isolated RGB channels, soft proofing, native Brush and Undo, and a 2,048 × 2,048 PNG from the local API.

451 of 454 selected tests passed in each of Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three inherited failures reproduced build 688’s assertions. Both signed macOS 14+ preview slices launched offscreen. The preview requires supported axis-aligned pattern periods and bounded local changes. Other angles and nonperiodic scales still use ordinary rendering. Full-resolution export has its own capacity limits. Photoshop’s document-count query timed out, so live zoom and preview equivalence remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-689) · [Details](../PhotoCraftSwift/docs/OPAQUE_PATTERN_PREVIEW_689.md).

## 2026-11-21 — Step 688 — Render Pattern Overlay on large canvases

Basic RGB Pattern Overlay can be edited and previewed on sparse canvases up to 300,000 × 300,000.

Across RGB8, RGB16 and RGB32, a 30 × 30 crop that crossed tile boundaries matched the small-canvas control byte for byte. The test covered linked and document-relative placement, partial layer coverage, a pixel mask, and a translucent backdrop. The largest PSB reopened through the native file-backed reader and preserved the style and all 3,600 crop bytes. A 6,000 × 2,000 PSB was byte-identical across the three builds. The loopback API applied and patched the overlay on a maximum-size document and transferred an editable 4,096 × 4,096 PSB.

448 of 451 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated with the same assertions as build 687. Both signed macOS 14+ preview slices launched offscreen. Dense full-canvas output, mixed spatial effects and maximum-size HTTP PSB transfers remain open. Photoshop 2026 reported version 27.2.0. Its document and JavaScript commands timed out, so live pixel and reopen comparisons remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-688) · [Details](../PhotoCraftSwift/docs/LARGE_PATTERN_OVERLAY_688.md).

## 2026-11-20 — Step 687 — Keep Pattern Overlay editable in PSD and PSB

Photato now opens and saves supported Photoshop Pattern Overlays as editable layer effects with embedded tiles.

The Photoshop-authored document retained all 13 layers, six editable overlays, and all 196,608 merged RGB bytes in unchanged PSD and PSB exports. Changes to all six overlays reopened with their revised settings. The four exports were byte-identical across build configurations.

446 of 449 selected tests passed in each configuration, including Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated on build 686 with the same assertions. Both signed macOS 14+ preview slices launched offscreen. The Photoshop color comparison covers the authored linked Normal overlays at 200% and 50% opacity. The existing style renderer still limits canvas area to 8,388,608 pixels. Other blend modes, rotated and fractional placement, and live Photoshop 2026 reopening require further comparison.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-687) · [Details](../PhotoCraftSwift/docs/EDITABLE_PATTERN_OVERLAY_687.md).

## 2026-11-20 — Step 686 — Match sampled Photoshop legacy pattern scales

Legacy RGB8 shape patterns now use rounded half-size tiles and quantized corner interpolation in supported cases.

At 25%, 50%, 56%, and 200% the regenerated layer colors matched all 9,309 sampled opaque interior pixels per case. Four other pattern-placement cases matched the same number of pixels each. The edited and untouched exports were byte-identical across build configurations. The native saves and both Photoshop formats reopened with editable patterns.

All 351 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both signed macOS 14+ preview slices launched offscreen. The comparisons cover the authored tiles and placements. Rotated and transparent tiles, odd-size reductions, other depths, and full shape-edge output still require comparison. Preparing a synthetic 4,000 × 4,000 sparse tile at 25% took 0.75 seconds on this test Mac. Live Photoshop 2026 reopen remains unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-686) · [Details](../PhotoCraftSwift/docs/LEGACY_PATTERN_SCALING_686.md).

## 2026-11-20 — Step 685 — Improve RGB8 shape opacity and legacy pattern placement

Plain Normal RGB8 shape layers round effective and accumulated alpha at each layer. Supported legacy pattern shapes retain editable phase and the original reference point in PSD and PSB.

All 310 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Scaled pattern repaint at 200%, 56%, and 25% still differs. Independent sampling matched the 200% fixture with a half-pixel coordinate shift and the 25% fixture with two rounded 2 × 2 reductions. Masked, styled, transformed and other depth or blend cases have separate acceptance requirements. Reopening in a live Photoshop 2026 session remains unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-685) · [Details](../PhotoCraftSwift/docs/SHAPE_EDGE_COMPOSITING_685.md).

## 2026-11-20 — Step 684 — Keep patterns and straight lines editable in PSD and PSB

Supported RGB8 and RGB16 PSD and PSB shape layers keep their embedded pattern fills and strokes editable. Arrowless straight lines retain their endpoints and weight.

All 302 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The regenerated merged preview differs in 331 color-channel bytes across 224 antialiased pixels, with a maximum difference of 1 in RGB and exact alpha. The 56% polygon pattern sample supports a document-origin phase. Its scaled sampling still differs. The 60° gradient diagnostic did not establish a universal half-pixel placement correction. Arrowheads and live Photoshop 2026 reopen and repaint checks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-684) · [Details](../PhotoCraftSwift/docs/EDITABLE_SHAPE_PATTERNS_684.md).

## 2026-11-20 — Step 683 — Keep shape gradients editable in PSD and PSB

Supported RGB8 and RGB16 shape layers retain their editable gradient fills and strokes in PSD and PSB. An unchanged import keeps its source descriptors and pixel cache.

All 300 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The original file containing patterned shape paint and the original file containing unsupported pattern layer effects still reject. The derivative fixtures isolate shape metadata and leave pattern paint, line controls, seeded dither and whole-file compatibility open. An equivalent-angle native repaint differed in alpha by up to three 8-bit levels throughout a 32 × 32 interior sample. Its RGB values matched. A separate diagnostic shifted the gradient center by half a pixel and matched all 1,024 alpha samples in that window. Reopening the new files in a live Photoshop 2026 session remains unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-683) · [Details](../PhotoCraftSwift/docs/EDITABLE_SHAPE_PAINT_683.md).

## 2026-11-20 — Step 682 — Render gradients and strokes on large editable cutouts

Gradient, pattern, and stroke paint on a large shape cutout now renders over the visible area. Panning retains the full shape’s paint coordinates and antialiasing.

All 297 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Gradient and pattern shape paint remain editable in native files. Editable Photoshop file transport for this paint and a live Photoshop comparison are still open. Whole-document materialization uses the available scratch storage. Full editing frame rate remains a separate measurement.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-682) · [Details](../PhotoCraftSwift/docs/BOUNDED_SHAPE_PAINT_682.md).

## 2026-11-20 — Step 681 — Keep the shape exterior attached to the canvas

Moving a cutout now moves its contour while the fill reaches the current canvas edges. Canvas Size and Crop update the exterior, and supported PSD and PSB files retain the editable shape.

All 292 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The owned live Photoshop comparison timed out. Adobe’s public vector-mask and canvas documentation informed the expected behavior. Exact Photoshop live-shape output, transformed exteriors and very large styled fills remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-681) · [Details](../PhotoCraftSwift/docs/EDITABLE_SHAPE_CANVAS_681.md).

## 2026-11-20 — Step 680 — Subtract the first component of a shape layer

A leading Subtract cuts a hole in the shape layer’s canvas fill. The contour remains editable in Photato and in supported PSD and PSB files.

All 287 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Sparse full-canvas rendering has been qualified for an integer-aligned solid fill on a 300,000 × 300,000 document without a visible stroke. The exterior currently retains the canvas frame set when it was created. Canvas resizing, moved or rotated exteriors in PSD, large gradients and strokes, and a direct Photoshop comparison of live shape data remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-680) · [Details](../PhotoCraftSwift/docs/SHAPE_SUBTRACTION_680.md).

## 2026-11-20 — Step 679 — Reorder, combine and merge path components

Move selected path components forward or backward, change how they overlap, or merge their closed outlines. Merged vector shapes remain editable in supported PSD and PSB files.

All 263 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison and Adobe-authored byte equality remain open. Merge requires closed contours and a mergeable overlap region. The unbounded exterior of a leading subtraction on a shape layer remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-679) · [Details](../PhotoCraftSwift/docs/PATH_COMPONENT_OPERATIONS_679.md).

## 2026-11-20 — Step 678 — Align and distribute components on an editable path

Select several whole components on one path and align their edges, distribute their centers, or space them evenly. Supported compound shape layers remain editable in PSD and PSB.

All 256 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop layout comparison, exact Adobe-produced file bytes, arbitrary live origins and shapes outside the supported PSD paint and stroke settings remain open. Native Photato archives retain the edited curves.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-678) · [Details](../PhotoCraftSwift/docs/PATH_COMPONENT_LAYOUT_678.md).

## 2026-11-20 — Step 677 — Isolate a path’s layer while editing

Double-click a selected shape path or vector mask with either path selection tool to isolate its layer in the Layers and Paths panels. Double-click away from the path, turn off layer filtering, or choose another filter to exit.

All 225 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison and physical Intel and macOS 14 testing remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-677) · [Details](../PhotoCraftSwift/docs/PATH_ISOLATION_677.md).

## 2026-11-20 — Step 676 — Switch between path Warp and Free Transform

Switch between Warp and Free Transform while editing paths, masks or shape contours. The mesh follows later placement changes, and the whole edit applies in one Undo.

All 202 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Photoshop-authored path output, exact guide and mode behavior in Photoshop, and physical canvas speed remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-676) · [Details](../PhotoCraftSwift/docs/PATH_WARP_SWITCH_676.md).

## 2026-11-20 — Step 675 — Warp editable paths on the canvas

Warp saved paths, vector masks and shape contours in the main canvas. Switch from Free Transform and apply both changes in one Undo. The same edit works in the Photato API and Actions.

All 198 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Photoshop-authored warp output, switching from edited Warp back to Free Transform, and physical canvas performance remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-675) · [Details](../PhotoCraftSwift/docs/PATH_WARP_675.md).

## 2026-11-20 — Step 674 — Transform editable paths across layers

Select saved paths, vector masks and shape contours across layers and transform them together with Command-T. The Photato API and native Actions support the same atomic edit.

All 192 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison, native path isolation, and editable Warp for paths remain open. Direct edits to shape contours can replace live primitive controls with editable cubic geometry.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-674) · [Details](../PhotoCraftSwift/docs/CROSS_LAYER_PATHS_674.md).

## 2026-11-20 — Step 673 — Select path anchors with a Direct Selection marquee

Direct Selection now previews and selects anchors inside a dragged marquee. Shift adds to the selection. The same operation is available through the Photato API.

All 186 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The marquee operates on the active path. Simultaneous path selection across layers and exact Photoshop hit testing, modifiers and cursor comparisons remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-673) · [Details](../PhotoCraftSwift/docs/DIRECT_SELECTION_MARQUEE_673.md).

## 2026-11-20 — Step 672 — Transform selected paths, contours and anchors

Command-T now transforms a saved path, vector mask or shape contour independently of its layer. Select whole contours or individual anchors and apply the same edit through the Photato API or an Action.

All 156 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Shape contours remain editable as Bézier geometry. A contour edit can replace the live primitive controls. Direct Selection marquee, path selection across layers, path Warp, and live Photoshop comparisons of partial projective transforms remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-672) · [Details](../PhotoCraftSwift/docs/PATH_TRANSFORM_672.md).

## 2026-11-20 — Step 671 — Keep vector masks editable in Perspective and Distort

Perspective and Distort now move linked vector masks with the artwork and keep unlinked masks fixed. Masks remain editable after native, PSD and PSB saves.

All 131 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The original PDF was placed by Photoshop. Photato applied the reference transforms. Exact Photoshop anchors and pixels, independent Free Transform on a selected path, and vector masks with non-neutral Warp remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-671) · [Details](../PhotoCraftSwift/docs/PROJECTIVE_VECTOR_MASKS_671.md).

## 2026-11-20 — Step 670 — Keep PDF Smart Object perspective editable

Embedded and linked PDF pages keep editable Perspective and Distort placement in PSD and PSB. Photato renders the source PDF at a density suited to the projected detail and retains the saved corners.

All 109 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. Photoshop 2026 reported version 27.2.0, then timed out on its read-only document query. The original test PDF was placed by Photoshop. The projected test variants were generated by Photato. Live Photoshop perspective comparisons and maximum dense source capacity remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-670) · [Details](../PhotoCraftSwift/docs/PDF_PERSPECTIVE_670.md).

## 2026-11-20 — Step 669 — Keep PDF Smart Object Warp editable

Embedded and linked PDF Smart Objects retain editable Warp in PSD and PSB. The renderer resamples the original PDF when the Warp magnifies the artwork. The page, crop and layer controls stay editable.

All 88 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The running Photoshop scripting interface timed out. The independent Photoshop-authored PSD supplies the original PDF page and crop. A Photoshop-authored PDF with Warp, live Adobe rendering comparisons and full dense PDF capacity remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-669) · [Details](../PhotoCraftSwift/docs/PDF_SMART_OBJECT_WARP_669.md).

## 2026-11-20 — Step 668 — Wrap editable Smart Objects around a cylinder

Cylinder Warp curves artwork around a product mockup in the native Warp sheet. PSD and PSB keep the editable shape when a Smart Object is reopened, replaced or relinked.

All 134 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The prior Intel RGB32 difference reproduced in a separate run. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. The Cylinder renderer uses published measurements. A Photoshop-authored Cylinder PSD, live mouse interaction and byte-identical Photoshop rerendering remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-668) · [Details](../PhotoCraftSwift/docs/CYLINDER_WARP_668.md).

## 2026-11-20 — Step 667 — Keep Smart Object Warp editable in PSD and PSB

PSD and PSB now reopen supported Smart Object Warp presets, cubic meshes and nonuniform split grids as editable settings. Relinking a missing original restores its live Warp.

1,537 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. Unchanged saved samples and Photato-regenerated pixels were checked separately. An independent reader compared the encoded merged image planes in both outputs against Photoshop’s stored preview. In each format, 24 of 1,048,576 component bytes differ by one level, including three alpha bytes. Live Photoshop rerendering, Cylinder, PDF Warp and pre-Warp reconstruction of saved pixel masks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-667) · [Details](../PhotoCraftSwift/docs/EDITABLE_SMART_OBJECT_WARP_667.md).

## 2026-11-20 — Step 666 — Relink perspective artwork after reopening PSD and PSB

PSD and PSB preserve the image preview, location and four-corner placement of a linked Smart Object when its original is missing. Free Transform uses the saved artwork frame. Relinking restores source-based perspective editing.

1,511 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Photoshop's live document query timed out. The file and pixel comparisons use Photato and owned fixtures. Live Photoshop interchange, linked PDF perspective and non-identity Warp descriptors remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-666) · [Details](../PhotoCraftSwift/docs/LINKED_PROJECTIVE_SMART_OBJECTS_666.md).

## 2026-11-20 — Step 665 — Reopen perspective Smart Objects and continue editing

Embedded Smart Objects with perspective placement keep their original bytes and editable corners in PSD and PSB. Free Transform starts from the saved artwork frame.

1,507 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Live Photoshop document scripting timed out after the read-only version query. Projective linked files, projective PDFs and editable non-identity Warp still need Photoshop-file coverage. Intel tests ran under Rosetta.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-665) · [Details](../PhotoCraftSwift/docs/PROJECTIVE_SMART_OBJECT_ROUNDTRIP_665.md).

## 2026-11-20 — Step 664 — Export thumbnail and Smart Object assets from Photoshop manifests

Photoshop document manifests can include JPEG or PNG layer previews and exact copies of embedded Smart Object originals. The assets use Photato's authenticated local download URLs.

1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Direct Adobe-hosted comparison of thumbnail geometry, defaults and bytes remains open. The native encoder chooses its progressive JPEG scan count. Intel tests ran under Rosetta.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-664) · [Details](../PhotoCraftSwift/docs/ADOBE_MANIFEST_ASSETS_664.md).

## 2026-11-20 — Step 663 — Inspect Photoshop templates through the Adobe-compatible manifest

The Adobe-compatible manifest reports Photoshop document and layer metadata. Use the returned layer IDs to edit the same PSD or PSB through create-composite.

1,498 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional masked RGB32 test passed on Apple Silicon. On Intel, eight PSD composites matched the previous build byte for byte and reproduced its existing differences from the Photoshop fixtures. Both slices of the signed macOS 14+ universal preview launched offscreen. Layer thumbnails, original Smart Object extraction, full layer descriptors and comparisons with Adobe's hosted results remain open. Intel tests ran under Rosetta. The preview binaries declare macOS 14.0 as the minimum system version.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-663) · [Details](../PhotoCraftSwift/docs/ADOBE_DOCUMENT_MANIFEST_663.md).

## 2026-11-20 — Step 662 — Fit replacement artwork inside Smart Object frames

Fit or fill replacement artwork inside an existing embedded Smart Object frame. The new ingredient remains editable as a nested Smart Object, including artwork outside the visible frame. Both the Photato and Adobe-compatible APIs expose content placement.

All 1,493 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop did not respond to read-only AppleEvent or Accessibility window checks. Independent Adobe output and the hosted service remain unverified. Intel ran under Rosetta and the signed binaries declare macOS 14.0.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-662) · [Details](../PhotoCraftSwift/docs/SMART_OBJECT_CONTENT_PLACEMENT_662.md).

## 2026-11-20 — Step 661 — Smart Object templates get editable masks and blending

Smart Object template jobs can set opacity, blend mode and editable pixel masks when they place or replace artwork. Photato exposes the supported fields in its API capabilities.

The 1,482 selected cases passed across qualification and replay in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Each initial run passed 1,481 cases. After updating the obsolete mask assertion, all 142 replay cases passed in each configuration. The application inputs and signed binary stayed byte-identical. Both slices of the signed macOS 14+ universal preview launched offscreen. Adobe's hosted service was not run. Exact Adobe mask edge, placement and color output remain unverified. The Intel runtime used Rosetta, and the macOS 14 minimum was verified in the signed binary.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-661) · [Details](../PhotoCraftSwift/docs/SMART_OBJECT_TEMPLATE_APPEARANCE_661.md).

## 2026-11-20 — Step 660 — Free Transform follows Smart Object artwork

Free Transform handles follow an affine Smart Object's saved corners. Side and corner drags scale along the artwork's axes, and the angle field reads its current rotation. The Photato API exposes the frame and commit delta.

All 1,477 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe handle behavior, displayed scale percentages and output fidelity remain unverified. The Intel runtime used Rosetta, and the macOS 14 minimum was checked in the signed binary.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-660) · [Details](../PhotoCraftSwift/docs/ORIENTED_SMART_OBJECT_TRANSFORM_660.md).

## 2026-11-20 — Step 659 — Read the original transform of linked Smart Objects

Properties and Free Transform now use the original geometry of linked artwork when a reopened PSD or PSB has only a cached preview. The Photato API reports the same source transform, rotation and bounds.

All 1,472 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe Properties values, rounding, handle orientation, physical Intel, a macOS 14 runtime and full assistive-technology behavior remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-659) · [Details](../PhotoCraftSwift/docs/LINKED_SMART_OBJECT_GEOMETRY_659.md).

## 2026-11-20 — Step 658 — Custom Smart Object geometry for template jobs

The Adobe-compatible template API can set Smart Object size, position, rotation, skew and anchor. Jobs can place artwork relative to other layers and change the geometry of a linked PSD without supplying its original artwork again.

All 1,468 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe hosted-service pixels, unobserved geometry defaults, physical Intel and a macOS 14 runtime remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-658) · [Details](../PhotoCraftSwift/docs/ADOBE_SMART_OBJECT_TEMPLATE_658.md).

## 2026-11-20 — Step 657 — Place Smart Objects at their source print size

Place Embedded and Place Linked now size artwork from its print resolution and the destination ppi. Resize Image During Place fits oversized artwork after converting to document pixels. The Photato API exposes the same geometry through an explicit physical sizing option.

All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-657) · [Details](../PhotoCraftSwift/docs/PLACEMENT_RESOLUTION_657.md).

## 2026-11-20 — Step 656 — Recover linked Smart Objects after moving a folder

PSD and PSB files now keep both linked-file locations. Locate Package Sources can find approved artwork in nested folders after a document moves. Desktop and API operations use the same lookup when updating or packaging the document.

All 1,457 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-656) · [Details](../PhotoCraftSwift/docs/PORTABLE_LINKED_PATHS_656.md).

## 2026-11-20 — Step 655 — Add General placement preferences

General settings now control automatic fit, the placement transform preview and whether new embedded artwork becomes a Smart Object or a pixel layer. Command–K opens the native General pane. The Photato API exposes the three persistent preferences and explicit pixel-layer placement for new embedded and PDF artwork.

All 1,452 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The direct Photoshop comparison is still open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-655) · [Details](../PhotoCraftSwift/docs/PLACEMENT_PREFERENCES_655.md).

## 2026-11-20 — Step 654 — Place and update gigabyte-scale linked Smart Objects

A 1.18 GB linked PSB passed native and approved API placement, background refresh, repeated packaging, relink, embedding and Undo. Linked native, PSD and PSB outputs matched across both compiled architectures.

All 1,446 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-654) · [Details](../PhotoCraftSwift/docs/LARGE_LINKED_ORIGINALS_654.md).

## 2026-11-20 — Step 653 — Preserve Smart Object placement identifiers

Apple Silicon and Intel under Rosetta wrote identical 1,182,448,710-byte PSBs from the same nested edit. Duplicate Smart Filter masks and copied linked previews survive save and reopen.

All 1,407 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-653) · [Details](../PhotoCraftSwift/docs/PLACED_LAYER_IDENTIFIERS_653.md).

## 2026-11-19 — Step 652 — Keep gigabyte-scale originals in Undo and Redo

Spilled history states share the existing file-backed original. Undo and Redo keep the bytes, and insufficient disk space rejects the edit atomically.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-652) · [Details](../PhotoCraftSwift/docs/GIGABYTE_SMART_OBJECT_HISTORY_652.md).

## 2026-11-19 — Step 651 — Keep gigabyte-scale originals through Edit Contents

A 1.18 GB PSB retains its exact original and editable samples through placement, a nested edit and reopen. Native files use archive version 97 for these originals.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-651) · [Details](../PhotoCraftSwift/docs/GIGABYTE_SMART_OBJECTS_651.md).

## 2026-11-19 — Step 650 — Retain large embedded originals on disk

Large PSB originals remain editable in native projects, PSD and PSB. The 275.7 MB test retained two shared instances, and the 525.1 MB file retained its original bytes.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-650) · [Details](../PhotoCraftSwift/docs/FILE_BACKED_SMART_ORIGINALS_650.md).

## 2026-11-19 — Step 649 — Place and reopen larger Photoshop originals

PSD, PSB and chunked native Smart Object sources have a local 256 MiB budget. The two previously rejected PSBs retained exact bytes and editable contents, and a 262.5 MB reference passed native and PSB round trips.

All 1,372 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed an offscreen launch. The Debug save-sheet check passed on an isolated rerun after the sheet missed the suite's deadline.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-649) · [Details](../PhotoCraftSwift/docs/LARGE_EMBEDDED_ORIGINALS_649.md).

## 2026-11-19 — Step 648 — Keep large embedded sources once

A three-source native save dropped from 201.8 MB to 100.9 MB. The parent PSB and the three original sources kept identical bytes.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-648) · [Details](../PhotoCraftSwift/docs/EMBEDDED_SOURCE_RECORDS_648.md).

## 2026-11-19 — Step 647 — Keep large generated Smart Object sources editable

Two large deep-colour Smart Objects keep editable child data in PSD and PSB. Independent checks matched all 134,316,048 child samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-647) · [Details](../PhotoCraftSwift/docs/EMBEDDED_SMART_SOURCE_647.md).

## 2026-11-19 — Step 646 — Speed up large editable Smart Filter files

The 9-megapixel editable Smart Filter test dropped from 164.4 to 7.2 seconds on optimized Apple Silicon. Three PSD and PSB exports matched the previous Photato codec byte for byte.

All 1,357 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed offscreen launch checks.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-646) · [Details](../PhotoCraftSwift/docs/PSD_SMART_FILTER_PAGING_646.md).

## 2026-11-19 — Step 645 — Keep Gradient Overlay editable

Standard Gradient Overlay keeps its stops and placement through PSD and PSB. Six exports of three Photoshop 27.4 RGB8 files matched all 737,280 merged RGBA samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-645) · [Details](../PhotoCraftSwift/docs/PSD_GRADIENT_OVERLAY_645.md).

## 2026-11-19 — Step 644 — Match linked raster previews to saved mask samples

Supported linked RGB8 and RGB16 previews apply the separately quantized Photoshop layer and mask samples. Six file comparisons confirmed the tested output.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-644) · [Details](../PhotoCraftSwift/docs/LINKED_PREVIEW_644.md).

## 2026-11-19 — Step 643 — Open nested Photoshop Smart Objects

An iterative decoder opens nested editable Smart Objects without exhausting the worker stack. The eight-level round trip and the previously failing Execute Actions workflow passed.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-643) · [Details](../PhotoCraftSwift/docs/PSD_NESTED_SOURCES_643.md).

## 2026-11-19 — Step 642 — Read older solid shapes and their pixel masks

Older live solid-fill shapes open as editable layers and keep the separate pixel mask. Both unchanged exports matched the reference layer, mask and preview samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-642) · [Details](../PhotoCraftSwift/docs/PSD_LEGACY_SHAPES_642.md).

## 2026-11-19 — Step 641 — Keep rounded rectangles and dashed ellipses editable

PSD and PSB retain supported solid fills, rounded corners and dotted or dashed ellipse strokes. Six independently checked exports retained the tested layer samples and shape records.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-641) · [Details](../PhotoCraftSwift/docs/PSD_ROUNDED_ELLIPSE_641.md).

## 2026-11-19 — Step 640 — Keep Photoshop rectangles editable

Supported axis-aligned RGB rectangles open as editable layers. Photoshop-format tests verified the rendered samples and the retained rectangle descriptors.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-640) · [Details](../PhotoCraftSwift/docs/PSD_LIVE_RECTANGLES_640.md).

## 2026-11-19 — Step 639 — Keep vector outlines when printing

Include Vector Data preserves eligible outline shapes and text in native print and PDF output. An independent PDF check verified the vector paths and raster backdrop.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-639) · [Details](../PhotoCraftSwift/docs/VECTOR_PRINT_639.md).

## 2026-11-19 — Step 638 — Save document print settings with the artwork

Native documents retain committed print settings and hard-proof conditions. Editable PSD and PSB update supported Photoshop Print Information and Print Style fields.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-638) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_638.md).

## 2026-11-19 — Step 637 — Remember print defaults and restore supported Photoshop settings

Photato remembers accepted native print defaults and restores supported Print Information and Print Style fields when opening Photoshop files.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-637) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_637.md).

## 2026-11-19 — Step 636 — Fit and clip large prints at their original sample resolution

Photato fits high-resolution photos to paper while retaining original samples, and can prepare just the visible region of a much larger document printed at a fixed scale.

All 1,168 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-636) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_636.md).

## 2026-11-19 — Step 635 — Print a selection from a large document

The desktop and authenticated PDF route can prepare a small selection from a sparse document at the maximum canvas dimensions.

All 1,166 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-635) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_635.md).

## 2026-11-19 — Step 634 — Print native CMYK and saved spot separations

Print and the authenticated PDF download create named process and spot pages for eligible CMYK, Duotone and Multichannel artwork.

All 1,163 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-634) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_634.md).

## 2026-11-19 — Step 633 — Return standard Multichannel plates to editable CMYK

Returning a standard ordered process set to CMYK keeps extra plates as editable spots. Eligible PSD and PSB files retain the merged process values through the round trip.

All 1,139 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-633) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_633.md).

## 2026-11-19 — Step 632 — Keep native CMYK and Lab components when flattening to Multichannel

Eligible layered CMYK and Lab documents preserve their numerical components through the Multichannel conversion and Delete Channels, including independent black ink.

All 1,136 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-632) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_632.md).

## 2026-11-19 — Step 631 — Preserve spot inks in Multichannel Photoshop files

Multichannel PSD and PSB output preserves saved spot inks as printing plates, including their density, swatch, Solidity and identifier.

All 1,133 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-631) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_631.md).

## 2026-11-19 — Step 630 — Keep Workflow Guide highlights visible across controls and dialogs

The Workflow Guide moves clear of a covered target. Its lessons highlight specific dialog fields and buttons and accept Show Me to replay the cue.

All 1,130 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-630) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_630.md).

## 2026-11-19 — Step 629 — Keep saved masks and printing plates in one Multichannel order

The Channels panel can place masks before or between printing plates. Photato archives, PSD and PSB preserve the same sequence.

All 1,129 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-629) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_629.md).

## 2026-11-19 — Step 628 — Drag channel rows and keep menu cues aligned

Drag an individual channel to duplicate, copy, reorder or delete it. The Workflow Guide follows the actual popup row once AppKit has positioned the menu.

All 1,125 selected tests passed in each configuration. The two signed macOS 14+ archive slices also passed offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-628). [Development notes](../PhotoCraftSwift/docs/CHANNEL_DRAG_628.md).

## 2026-11-19 — Step 627 — Integrate Workflow Guide cues with the expanded Channels panel

The validated source combines menu and dialog cues, process-channel deletion, and isolated Sky Replacement wheel input.

A repaired Debug candidate passed 44 targeted cases. A remaining intermittent popup placement issue was resolved before the 628 source qualification.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-627). [Development notes](../PhotoCraftSwift/docs/CHANNEL_GUIDE_INTEGRATION_627.md).

## 2026-11-19 — Step 626 — Delete process channels through the Channels panel

Deleting selected RGB, CMYK or Lab components converts the retained separations into editable Multichannel plates. Layered input requests merge consent.

All 29 selected development cases passed, including shared native and HTTP validation.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-626). [Development notes](../PhotoCraftSwift/docs/PROCESS_CHANNEL_DELETION_626.md).

## 2026-11-19 — Step 625 — Merge spot ink into the supported process channels

The shared spot-merge command keeps the expected component layout and performs one undoable document edit.

All 29 selected development cases passed. Exact comparison against Adobe-authored physical printing samples remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-625).

## 2026-11-19 — Step 624 — Duplicate channels into the current image or another document

Duplicate Channel uses native numerical samples and the dimensions, depth and channel rules of the destination. The app and API share that path.

All 25 selected development cases passed, including ownership, cancellation and document history.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-624).

## 2026-11-19 — Step 623 — Convert layerless ink documents back to editable image modes

Mode conversion can use the retained native separations and preserves supported large ink rasters. The Image Mode menu and Photato API share the conversion.

The development runs covered exact native component samples, mode round trips and large workspaces. The publication gate is the combined 628 matrix.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-623).

## 2026-11-19 — Step 622 — Resize and crop editable Multichannel plates

Canvas Size, Crop and supported nearest-neighbour geometry retain editable sparse printing plates and saved channel data.

The development run covered native and API geometry plus sparse file round trips. The public cumulative qualification is recorded in 628.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-622).

## 2026-11-19 — Step 621 — Follow native menus and dialogs in the Workflow Guide

The guide follows menu rows and submenus as they open. Supported dialog controls flash automatically, with Show Me available to replay the cue.

The repaired preview passed 11 selected cases, including Duplicate Layer, Save As and an unrelated sheet. A later matrix exposed a popup placement issue repaired in 628.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-621). [Development notes](../PhotoCraftSwift/docs/WORKFLOW_GUIDE_HIGHLIGHTS_621.md).

## 2026-11-19 — Step 620 — Keep maximum-size Multichannel printing plates editable

PSB can retain sparse editable spots and masks up to 300,000 × 300,000 pixels. Large Photato archives use format 93.

All 1025 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-620) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_620.md).

## 2026-11-19 — Step 619 — Rank Workflow Guide suggestions and highlight each step

Open Photato > Settings > Workflow Guide to control visibility, launch behavior and the suggestion limit. Choose Show Me while a guide is open to repeat its highlight. Preferences are stored locally.

All 972 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-619) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_619.md).

## 2026-11-19 — Step 618 — Save deep RGB Photoshop files without a merged preview

The File Handling preference and explicit Photato API setting apply to eligible native saves, Image Processor output, and file downloads. Adobe v2 continues to write its existing merged preview.

All 970 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-618) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_618.md).

## 2026-11-19 — Step 617 — Add the optional Workflow Guide

Open Window > Workflow Guide to browse suggestions for the selected layer, tool or other editor context. The guide runs locally and links to the development diary. The authenticated Photato capability catalogue exposes the same lessons.

All 968 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-617) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_617.md).

## 2026-11-19 — Step 616 — Write native Photoshop separations and Gray32 previews from stored blocks

A two-layer 1,531 × 5,491 Gray32 control matched all 34,060,421 bytes from build 615. Restoring the same sparse layers and writing the file took 274.9 milliseconds in the paired Apple Silicon Debug run, down from 44.80 seconds.

All 964 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-616) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_616.md).

## 2026-11-19 — Step 615 — Keep large Grayscale, CMYK and Lab Photoshop planes sparse

The native file reader opened an independently authored 300,000 × 300,000 Grayscale/16 PSB and matched all 18,432 checked gray and alpha words. The Apple Silicon Debug run took 2.61 seconds and retained 24 KiB of mapped component samples.

Build 614 exhausted a 384 KiB scratch limit on the smaller 1,531 × 5,491 control. Build 615 opened it under that allowance and matched all 19,842 checked words. All 963 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-615) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_615.md).

## 2026-11-19 — Step 614 — Read large ZIP-compressed Photoshop layers and masks as sparse rasters

The native file reader opened an independently authored 300,000 × 128 RGB8 PSB with a ZIP-compressed layer, translated mask and saved alpha. All 36,864 checked component words matched. The Apple Silicon Debug run took 5.48 seconds.

Build 613 reached the 768 KiB scratch limit on the same control. Build 614 read the editable layer, mask and saved alpha into six tiles using 384 KiB of mapped storage. All 962 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-614) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_614.md).

## 2026-11-19 — Step 613 — Import large flattened RGB PSD and PSB without staging all process planes

The native file reader opened a 300,000 × 300,000 flattened RGB8 PSB with transparency and saved alpha in 13.58 seconds in one Apple Silicon Debug run. All 36,864 checked RGBA and 1,024 saved alpha words matched the independent input.

Build 612 reached a 768 KiB scratch limit on the 1,201 × 30,001 control. Build 613 opened it with three RGBA tiles and one saved-alpha tile. All 961 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-613) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_613.md).

## 2026-11-19 — Step 612 — Save large PSD and PSB channels with repeated rows

The file writer and reader round-tripped a 300,000 × 300,000 RGB8 PSB with an editable fill, a saved alpha, a spot channel and Quick Mask. All 15,360 stored alpha and spot samples matched. The 15.48 GB file took 6.95 seconds to write and 16.77 seconds to reopen in one Apple Silicon Debug run.

Independent executions saved the same 1,201 × 30,001 document on 611 and 612. All 7,924,054 output bytes matched. One Debug run took 38.41 seconds on 611 and 37.3 ms on 612. All 960 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-612) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_612.md).

## 2026-11-19 — Step 611 — Import large PSD and PSB saved channels into sparse tiles

The native reader opened a synthetic 300,000 × 300,000 grayscale PSB in 4.22 seconds in one Apple Silicon Debug run. All 9,216 stored alpha samples and both editable grayscale layer samples matched the authored input. The saved alpha used 192 KiB of mapped sample storage.

A smaller 1,201 × 30,001 PSB retained all 10,593 checked alpha samples within a 768 KiB scratch allowance. Build 610 exceeded that allowance. The test set covers RGB8 Raw and PackBits and RGB16 and RGB32 PackBits. All 958 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-611) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_611.md).

## 2026-11-19 — Step 610 — Read saved Photoshop channels without a merged preview

A synthetic sparse 300,000 × 300,000 PSB opened with the exact editable raster in 3.5 ms on Apple Silicon Debug. The reader skipped 270 GB of unused logical raw preview data.

The native reader matched all 4,016 editable-layer and saved-channel sample words across 80 independently assembled PSD and PSB controls. A loopback regression covered Photato import, truncated-input rejection, and both job interfaces. All 957 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-610) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_610.md).

## 2026-11-19 — Step 609 — Set PSD and PSB file compatibility

Always includes a merged preview. Ask prompts during eligible desktop saves. Never skips the preview for RGB8 documents without saved channels. Unattended Ask saves include the preview by default.

All 1,974 PSD and 1,732 PSB placeholder bytes matched across five Adobe controls. Native saves, copy and cancellation passed, along with loopback API saves and downloads for all three settings. All 954 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-609) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_609.md).

## 2026-11-19 — Step 608 — Save full-width sparse raster edits to PSB

The 300,000 × 300,000 RGB8 PSB with paint across the first row saved in 9.20 s on Apple Silicon and 10.40 s under Rosetta. It reopened in 1.78 s and 2.86 s respectively. All authored raster bits matched.

An independent encoder matched all 8,445,600,024 bytes of RLE tables and payloads on each architecture. Separate Apple Silicon RGB16 and RGB32 checks preserved both raster layers and their mask. All 941 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-608) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_608.md).

## 2026-11-19 — Step 607 — Choose sparse Photoshop layer samples across the canvas

The editable 300,000 × 300,000 RLE PSB with paint across its first row reopened in 1.72 s on Apple Silicon and 2.70 s under Rosetta. All raster bits matched. Its 4,690 retained tiles occupied about 293 MiB.

The raw and mixed-compression controls each went from 8,911 mapped tiles to 21. Row inspection preserved the live cursor and continued to reject malformed input in both PSD and PSB. All 940 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-607) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_607.md).

## 2026-11-19 — Step 606 — Reopen sparse editable PSB raster layers

Photato reopened the 8.45 GB, 300,000 × 300,000 RGB8 PSB in 1.65 s on Apple Silicon and 2.61 s under Rosetta. Every raster bit matched and six tiles used 384 KiB of mapped sample storage. The independent decoder checked 900,000 layer and 900,000 merged row lengths per architecture, plus 72 sampled channel values.

The 300,000 × 131 RGB8 file went from 14,064 mapped tiles to four. RGB16 and RGB32 PSBs and RGB8 and RGB16 PSDs reopened with every raster bit preserved in the tested deep and legacy fixtures. All 938 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-606) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_606.md).

## 2026-11-19 — Step 605 — Stream repeated rows in sparse PSB files

Photato saved the 11.26 GB editable solid-fill PSB at 300,000 × 300,000 pixels in 3.22 s and reopened it in 2.12 s. An independent reader checked all 1,200,000 merged row lengths and 140 sampled channel values. These were single runs on the same Mac.

The 300,000 × 131 RLE file was byte-identical to build 604. Save time went from 10.97 s to 0.30 s on Apple Silicon and from 17.54 s to 0.34 s under Rosetta. All 932 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-605) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_605.md).

## 2026-11-19 — Step 604 — Reuse wide vector Feather profiles at canvas edges

At 110.25 px Feather, the rounded 300,000 × 300,000 control went from 5,632 rendered patches to 119. Apple Silicon went from 110.45 s to 13.47 s. Under Rosetta it went from 171.10 s to 25.76 s. All 226,872 sampled RGBA words matched the build 603 whole render on each architecture. These are single runs on the same Mac.

All 307,518,180 RGBA words in four complete renders matched build 603 on each architecture. The controls include RGB8, RGB16, RGB32, an inverted group mask, and independent raster and pixel-mask edits. All 924 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-604) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_604.md).

## 2026-11-19 — Step 603 — Reuse exact composited tiles under solid vector Feather

The 300,000 × 75 control went from 39 rendered patches to 15. The RGB16 wide-Feather control went from 156 to 111.

The full 300,000 × 300,000 rounded-mask control completed in 6.47 s on Apple Silicon and 13.10 s under Rosetta, with 28 rendered patches. The maximum-size ellipse completed in 64.16 s on Apple Silicon and 113.97 s under Rosetta, with 9,804 rendered patches. The rounded mask at 110.25 px Feather completed in 110.45 s on Apple Silicon and 171.10 s under Rosetta, with 5,632 rendered patches. Across the three composites, all 745,024 RGBA words in 26 sampled regions matched build 602 viewports on each architecture. These are single runs on the same Mac.

All 922 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-603) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_603.md).

## 2026-11-19 — Step 602 — Skip solid pieces of dense feathered vector masks

At 1,000 px Feather, the interior viewport of the maximum-size document needed no scratch transfer, down from 51,595,425 source pixels. The whole 49,155 × 73 wide-Feather control transferred 18,434,046 source pixels, down from 36,890,622.

Whole-mask preparation for the 300,000 × 300,000 control at 110.25 px Feather took 10.39 s on Apple Silicon and 14.14 s under Rosetta. The four checked regions matched all 42,286 coverage words against build 601 viewport output on each architecture. These measurements are single runs on the same Mac.

Ten mask controls matched build 601 across all 10,873,881 Float32 coverage words per architecture. Two additional whole-canvas RGB32 layer stacks matched all 28,706,520 RGBA words per architecture. The controls cover both mask polarities, short and wide Feather through 1,000 px, Boolean holes, partial cells, and near-edge viewports on a 300,000 × 300,000 document. All 920 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-602) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_602.md).

## 2026-11-19 — Step 601 — Render sparse curved Feather from stored coverage

The sparse inverted rectangle control rendered in two patches, down from 36. The distant curved mask on a 300,000 × 300,000 canvas used 46, down from 92. Both controls matched the complete build 600 render.

All 918 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-601) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_601.md).

## 2026-11-19 — Step 600 — Prove RGB32 raster-base opacity with rectangular Feather

The 37.8 MP opaque-base test with 2 px Feather went from 52.80 s to 0.02 s on Apple Silicon and from 69.40 s to 0.02 s under Rosetta. These are single runs on the same host.

The 300,000 × 300,000 opaque-base test at 1,000 px completed in 1.27 s on Apple Silicon and 1.79 s under Rosetta. The narrow and wide opaque controls and the distant inverted-hole control each matched 9,248 sampled Float32 words on each architecture against the corresponding build 599 37.8 MP controls.

All 916 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-600) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_600.md).

## 2026-11-19 — Step 599 — Reuse wide vector-mask Feather windows

The 300,000 × 300,000 stress case with an inverted 1,000 px Feather mask completed in 35.71 s on Apple Silicon and 49.08 s under Rosetta. Build 598 exceeded the 200-second cutoff on Apple Silicon. The new whole-canvas output matched all 11,560 sampled Float32 words of the previous viewport output on each architecture.

All 914 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-599) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_599.md).

## 2026-11-19 — Step 598 — Render whole-canvas rectangular vector masks

A 300,000 × 300,000 document with a rectangular vector mask and a sparse raster edit rendered in 197 tiles in the regression test. The tile index reuses the rendered samples across the canvas. On a 37.8 MP RGB32 control, median whole-canvas render time went from 3.912 s to 0.103 s on Apple Silicon and from 8.245 s to 0.194 s under Rosetta. Each median uses three alternating runs on the same host.

All 912 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-598) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_598.md).

## 2026-11-19 — Step 597 — Reuse window sums during wide mask Feather

Wide Feather reuses the second filter pass’s window sums when they fit a bounded cache. The 1,000 px vector viewport went from 1.001 s to 0.933 s on Apple Silicon. The RGB32 pixel-mask control went from 0.180 s to 0.135 s and the oversize Smart Filter mask from 0.867 s to 0.821 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 596 bit for bit on each architecture across eight vector, raster and Smart Filter cases.

All 909 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-597) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_597.md).

## 2026-11-19 — Step 596 — Reuse source bands during wide mask Feather

Wide Feather reuses source row bands for vector, pixel and Smart Filter masks. The 1,000 px vector viewport went from 1.343 s to 0.995 s on Apple Silicon. The oversize Smart Filter mask control went from 1.483 s to 0.862 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 595 bit for bit on each architecture across eight vector, raster and Smart Filter cases.

All 908 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-596) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_596.md).

## 2026-11-19 — Step 595 — Prepare vector-mask Feather around the viewport

Large-canvas vector-mask Feather limits broad coverage preparation to the viewport and its filter margin. On Apple Silicon, the 15 × 7 viewport through a 24,576 px mask at 1,000 px Feather took 8.506 s in build 594 and 1.367 s in build 595. The 250 px curved control took 6.063 s and 0.206 s.

All 907 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-595) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_595.md).

## 2026-11-19 — Step 594 — Match measured short vector-mask Feather responses

The 1.5 px and 2 px vector-mask Feather settings now reproduce the measured Photoshop step and corner responses. Dense rendering, paged whole-canvas rendering and tiled viewports produced identical alpha words at the tested coordinates.

All 905 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-594) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_594.md).

## 2026-11-19 — Step 593 — Bound vector mask Feather on large canvases

Vector masks accept Feather through 1,000 px and keep their paths editable in native documents, PSD and PSB. The maximum sparse canvas test used four patches, and the native and HTTP settings share the same 1,000 px range.

All 904 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-593) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_593.md).

## 2026-11-19 — Step 592 — Bound Smart Filter mask Feather on large documents

Smart Filter masks accept Feather through 1,000 px and render projected mask regions on sparse large documents. The maximum sparse canvas test updates two distant mask regions. The Properties controls and Photato API use the same limit and retain an editable mask on save.

All 887 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-592) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_592.md).

## 2026-11-19 — Step 591 — Match measured fractional RGB32 Feather schedules

Aligned 32-bit raster masks now use Photoshop’s measured filter schedules at 14 fractional Feather settings. The comparisons cover texture, lines and edges. Apple Silicon matched every sample. The Intel texture comparison found five differences, each one Float32 step.

All 861 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-591) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_591.md).

## 2026-11-19 — Step 590 — Match integer raster-mask Feather stages

Aligned RGB8 and RGB16 raster-layer masks now use integer-rounded Feather stages in rendering and clipping merges. The 34 Photoshop control files cover points, textures and translated masks. An independent reader checked 51,578 native PSD colour words in each test configuration. All matched the saved Apple Silicon Photoshop references.

All 858 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The independent Photoshop Rosetta capture remains pending.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-590) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_590.md).

## 2026-11-19 — Step 589 — Apply Feather in raster clipping merges and stamps

Merge Clipping Mask, Stamp Group, and eligible Merge Down and Stamp Down commands now use Feather on contributing raster clips. Saved RGB32 layer output matches five Photoshop cases at 250 or 1,000 px on both architectures. The tests also exercise sparse 300,000 × 300,000 documents and verify Undo through the desktop model and HTTP.

All 856 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The lower-radius Intel comparisons still have differences of up to two Float32 steps.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-589) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_589.md).

## 2026-11-19 — Step 588 — Support layer-mask Feather through 1,000 px

Layer-mask Feather now accepts 0–1,000 px in the native controls, Photato API and editable files. The renderer streams the wide filter. The saved 250 and 1,000 px RGB32 controls match exactly on both tested architectures, and the editable 1,000 px setting survives native, PSD and PSB round trips.

All 850 selected checks passed across the suite and focused recheck in Debug, optimized Apple Silicon and Intel under Rosetta. Fractional settings and other mask geometries still need exact Photoshop comparisons.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-588) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_588.md).

## 2026-11-19 — Step 587 — Match staged RGB32 pixel-mask Feather

Aligned RGB32 layer masks use a staged square filter at whole-pixel Feather radii from 3 to 100 px. It follows the canvas and stored mask edges, including masks that extend outside the canvas. In the app tests, 34,975 coverage samples matched the 21 saved Apple Silicon references exactly. All 844 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta.

Photoshop's 250 and 1,000 px textured controls also match the model. The current app range is 100 px. Fractional radii, a few Intel rounding cases, and the wider control are still in development.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-587) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_587.md).

## 2026-11-19 — Step 586 — Bound pixel-mask Feather rendering

Pixel-mask Feather now renders requested regions on 300,000 × 300,000 documents without preparing a full padded mask. Existing Feather output is preserved across the tested depths and transforms. All 842 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta.

Separate Photoshop tests reproduced the saved 100, 250 and 1,000 px line samples. The two-dimensional Intel results still need investigation before widening the control.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-586) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_586.md).

## 2026-11-19 — Step 585 — Add three arithmetic clipping blend modes

Linear Dodge (Add), Subtract and Divide now work in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. The HDR checks include masked clips, mixed opacity and translated Divide layers.

All 787 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The tests compare 96 saved Photoshop results per architecture.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-585) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_585.md).

## 2026-11-19 — Step 584 — Preserve pixel masks in clipping merges and stamps

Supported clipping merges and stamps preserve the editable base pixel mask and apply contributing masks at 8, 16 and 32 bits per channel. The tests cover disabled masks, integer offsets, Density and partial clip opacity. Stamp Group and Stamp Down retain the contributing mask on its own layer.

All 782 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. Feather on a contributing mask remains in development.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-584) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_584.md).

## 2026-11-18 — Step 583 — Add four clipped blend modes

Multiply, Darken, Lighten and Difference now participate in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel.

The saved Photoshop comparison matched 62,736 stored sample words per architecture. All 776 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-583) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_583.md).

## 2026-11-18 — Step 582 — Preserve independent clipping in merges and stamps

Supported raster clipping merges and stamps preserve Blend Clipped Layers as Group, the base blend mode, and its opacity. The saved pixels for the tested Multiply cases matched with the underlying backdrop visible or hidden.

The native editor and both local API families share the updated behavior. All 773 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-582) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_582.md).

## 2026-11-18 — Step 581 — Merge and stamp adjacent clipped layers

Merge Down and Stamp Down now work between adjacent Normal raster clips in the same clipping stack. Merge Down keeps the destination clipped and removes the upper layer. Stamp Down keeps both rows and the upper selection.

The stored raster matches the tested 8-, 16- and 32-bit Photoshop outputs. The first ActionJSON expansion found a stack overflow. Reusing the raster-output helper repaired it, and all 769 selected tests passed on each configuration.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-581) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_581.md).

## 2026-11-18 — Step 580 — Match Screen clipping and unchanged stamp history

Screen clips now participate in supported RGB8 and RGB16 merges and stamps. In-place stamps create an Undo step even when the stored pixels stay identical.

The saved-layer comparisons cover 36 Photoshop results. The 12 larger results account for 93,264 exact stored samples. The native editor and both local API families use the same implementation. All 765 selected checks passed in each configuration.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-580) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_580.md).

## 2026-11-18 — Step 579 — Add in-place Stamp Down and Stamp Group

Option-Command-E now stamps into an existing raster when one eligible layer is selected. Stamp Down updates the layer beneath it. Stamp Group updates the base of a supported clipping stack. Both commands preserve the selected layer and the rest of the stack.

The updated raster matched saved 8-, 16- and 32-bit Photoshop references. The native menu, local API, Actions and Undo share the two operations. All 761 selected tests passed in each of the three configurations.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-579) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_579.md).

## 2026-11-18 — Step 578 — Add contextual Merge Clipping Mask

Selecting the base of a supported raster clipping stack now makes Command-E run Merge Clipping Mask. The command combines visible clips into the base and removes the consumed clips. Hidden clips contribute no color. The base keeps its opacity, blend mode and stored geometry, including transparent or off-canvas samples.

The save-and-reopen tests compare 8-, 16- and 32-bit Photoshop reference layers. Undo, Actions and both local Adobe-compatible job routes are covered. All 757 selected checks passed on each of the three build configurations.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-578) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_578.md).

## 2026-11-18 — Step 577 — Preserve stored RGB32 pixel masks when merging and stamping

Normal 32-bit layer output now uses stored pixel masks. The comparison covers saved binary coverage and feathered selections, including transparency and the Intel rounding at tiny alpha values. A small translated mask in a 300,000 × 300,000 document used two render patches.

All 752 selected tests passed in Debug and in both optimized configurations. Both slices of the extracted local validation archive passed their offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-577) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_577.md).

## 2026-11-18 — Step 576 — Match stored RGB32 Normal merge and stamp samples

Merging and stamping 32-bit Normal layers now matches the saved Photoshop samples in the tested raster stacks. These tests cover very low alpha, transparent pixels, partial layer opacity and an opaque Background. A fresh Intel capture also confirmed that its saved alpha differs from Apple Silicon on one older fixture.

The new tests compare the stored layer before and after reopening a PSD. All 750 selected tests passed in each of the three build configurations. Both slices in the local universal archive passed their offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-576) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_576.md).

## 2026-11-18 — Step 575 — Render sparse stamps at maximum canvas size

Stamp Layers and Stamp Visible now skip large empty areas of a sparse document. A 300,000-pixel-square test document with two separated layers used two render patches. The tests covered raster stacks, simple groups, a translucent canvas background and both stamp operations at 8, 16 and 32 bits per channel.

Both ActionJSON job routes matched saved Photoshop layer samples for tagged and untagged files. All 749 selected tests passed in all three build configurations. Both slices of the local universal archive passed their offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-575) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_575.md).

## 2026-11-18 — Step 574 — Add Stamp Layers and Stamp Visible

Stamp Layers combines selected artwork on a new layer. Stamp Visible does the same for visible artwork. Both preserve the original layers and can be undone in one step. Photato exposes the shortcuts in the Layer menu and supports the same operation in recorded Actions and through the API.

The saved Photoshop references match at 8, 16 and 32 bits per channel. The test documents include locked layers, clipping, hidden layers and selections across different groups. All 745 selected tests passed in each of the three configurations. Both slices of the universal validation archive passed their offscreen workspace checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-574) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_574.md).

## 2026-11-18 — Step 573 — Match HDR Normal rounding at the Float32 underflow boundary

On Intel, very small color contributions can disappear during 32-bit Normal compositing. Photato now matches the measured rounding, including products just below the smallest normal Float32 value. The Apple Silicon build keeps its fused calculation.

The new tests compare 57,504 straight color and alpha words with separately saved Photoshop results on each architecture. An ordinary opaque source that covers the canvas retains its original colors over uniform backdrop alpha. Grouped clipping can preserve those colors even when the base alpha varies. All 708 selected tests passed in all three configurations. The local universal archive passed both offscreen workspace checks. The translucent test also exposed a difference in Merge Visible that remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-573) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_573.md).

## 2026-11-18 — Step 572 — Match Intel HDR Normal layer and group compositing

Photoshop's Intel build rounds the multiply and add separately when compositing 32-bit Normal layers. On Apple Silicon it uses a fused operation. Photato now follows those results for color, alpha and the opacity of supported groups. The tests use separately captured Photoshop results for each architecture.

The tested results match 264,192 Photoshop sample words on each architecture. That includes the masked Display P3 conversion that differed on Intel in build 571. All 705 selected tests passed in each configuration. Independent HDR clipping still differs.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-572) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_572.md).

## 2026-11-18 — Step 571 — Fix HDR PSD and PSB compression for Photoshop

Photoshop was reading plain ZIP as predicted ZIP on 32-bit layers. This could corrupt HDR colors when opening a PSD or PSB exported by Photato. New exports use the prediction expected for those layers. ZIP requests for the merged preview write raw data because Photoshop refused ZIP in that section. Photato still reads its older files.

Photoshop opened the tested files on Apple Silicon and Intel under Rosetta. The saved 32-bit grayscale samples match across both formats and save encodings. All 694 selected tests passed in each of three build configurations. The local universal archive passed both offscreen workspace checks. A separate mismatch remains in the Intel masked merge.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-571) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_571.md).

## 2026-11-18 — Step 570 — Preserve the working profile when merging before conversion

Merging eligible RGB layers before an Image Mode change now uses their working-profile samples. If the composite is already a single full-canvas layer, the conversion uses its original color and alpha planes. The existing Normal merge routine handles integer rounding for supported RGB stacks before promotion to 32 Bits/Channel.

All 35,840 words in the three valid Photoshop references match on each optimized architecture. All 678 selected tests passed in each build configuration. The two external HDR merge cases still need readable references.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-570) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_570.md).

## 2026-11-18 — Step 569 — Match HDR grayscale conversion and ICC gamma boundaries

32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves.

All 8,510,976 samples in 257 tested precision promotions and 194,560 samples in 38 RGB32-to-Gray32 cases match Photoshop on each architecture. All 661 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

Follow-up testing measured 4,410 rounding thresholds for 16-bit grayscale. Separate Float32 luminance products ordered all of the samples correctly. A 4,096-interval curve fits the measured thresholds, but its exact endpoint calculation remains open. Build 569 continues to use ColorSync for this conversion.

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

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-09.md) · [Next page](part-07.md)
