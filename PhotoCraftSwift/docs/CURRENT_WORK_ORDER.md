**Source checkpoint 691.** Fit on Screen and the local PNG overview now handle eligible quarter-turn Pattern Overlays on canvases up to 300,000 × 300,000. 455 of 458 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 690’s assertions. Both signed macOS 14+ preview slices launched offscreen. [Qualification](SOURCE_PUBLICATION_691.md).

**Next layer style work.** Extend bounded-memory fit to oblique and nonperiodic patterns. Compare scaled viewport output to a live Photoshop reference when document commands respond.

**Source checkpoint 690.** Rotated and nonperiodic Pattern Overlay renders in bounded document viewports on canvases up to 300,000 × 300,000. 453 of 456 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The same three failures reproduced the build 689 assertions. Both signed macOS 14+ preview slices launched offscreen. [Qualification](SOURCE_PUBLICATION_690.md).

**Next layer style work.** Extend fit-to-window reduction for opaque nonperiodic overlays. Compare scaled viewport output to a live Photoshop reference when document commands respond.

**Source checkpoint 689.** The native editor and local API preview supported opaque Pattern Overlay on canvases up to 300,000 × 300,000. 451 of 454 selected tests passed in each of Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three inherited failures reproduced build 688’s assertions. Both signed macOS 14+ preview slices launched offscreen. [Qualification](SOURCE_PUBLICATION_689.md).

**Next layer style work.** Run a viewport-only compositor for rotated or nonperiodic basic overlays at high zoom, then extend exact reduced display. Compare Photoshop’s zoom presentation and pattern placement when its document commands respond.

**Source checkpoint 688.** Basic RGB Pattern Overlay can be edited and previewed on sparse canvases up to 300,000 × 300,000. 448 of 451 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated with the same assertions as build 687. Both signed macOS 14+ preview slices launched offscreen. [Qualification](SOURCE_PUBLICATION_688.md).

**Next layer style work.** Exercise Pattern Overlay on opaque large backgrounds without a full-resolution backing composite. Measure the existing Photoshop reference cases for further modes and placements, and recheck compact PSB transfer with live Photoshop.

**Source checkpoint 687.** Photato now opens and saves supported Photoshop Pattern Overlays as editable layer effects with embedded tiles. 446 of 449 selected tests passed in each configuration, including Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated on build 686 with the same assertions. Both signed macOS 14+ preview slices launched offscreen. [Qualification](SOURCE_PUBLICATION_687.md).

**Next path editing work.** Use bounded Pattern Overlay rendering for large documents. The current style limit rejects a 30 × 30 viewport on a 300,000 × 300,000 canvas. Extend the Photoshop reference set to other blend modes and placements.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 686.** Legacy RGB8 shape patterns now use rounded half-size tiles and quantized corner interpolation in supported cases. All 351 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both signed macOS 14+ preview slices launched offscreen. [Qualification](SOURCE_PUBLICATION_686.md).

**Next path editing work.** Add editable Pattern Overlay interchange for the Photoshop-authored six-overlay file. Its interiors match the same corner grid when the style uses the stored reference point and 8-bit opacity. Continue the translucent shape-edge RGB checks.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 685.** Plain Normal RGB8 shape layers round effective and accumulated alpha at each layer. Supported legacy pattern shapes retain editable phase and the original reference point in PSD and PSB. All 310 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_685.md).

**Next path editing work.** Qualify bounded pattern minification and the enlarged tile sampling grid. Extend the RGB8 color comparison at translucent shape edges.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 684.** Supported RGB8 and RGB16 PSD and PSB shape layers keep their embedded pattern fills and strokes editable. Arrowless straight lines retain their endpoints and weight. All 302 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_684.md).

**Next path editing work.** Measure scaled pattern resampling, Photoshop's shape-edge compositing and diagonal gradient placement with additional author references.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 683.** Supported RGB8 and RGB16 shape layers retain their editable gradient fills and strokes in PSD and PSB. An unchanged import keeps its source descriptors and pixel cache. All 300 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_683.md).

**Next path editing work.** Measure the suspected half-pixel gradient placement difference across more authored cases. Qualify pattern fills and strokes, including embedded resources and linked phase.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 682.** Gradient, pattern, and stroke paint on a large shape cutout now renders over the visible area. Panning retains the full shape’s paint coordinates and antialiasing. All 297 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_682.md).

**Next path editing work.** Qualify Photoshop-authored gradient shape descriptors and add editable PSD and PSB transport for gradient fills and strokes.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 681.** Moving a cutout now moves its contour while the fill reaches the current canvas edges. Canvas Size and Crop update the exterior, and supported PSD and PSB files retain the editable shape. All 292 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_681.md).

**Next path editing work.** Qualify a Photoshop-authored live cutout and extend bounded rendering of large gradients and strokes.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 680.** A leading Subtract cuts a hole in the shape layer’s canvas fill. The contour remains editable in Photato and in supported PSD and PSB files. All 287 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_680.md).

**Next path editing work.** Compare exterior behavior after layer moves and Canvas Size, and qualify a Photoshop-authored live shape and its PSD and PSB output.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 679.** Move selected path components forward or backward, change how they overlap, or merge their closed outlines. Merged vector shapes remain editable in supported PSD and PSB files. All 263 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_679.md).

**Next path editing work.** Check the bounded exterior for leading shape subtraction and qualify matched Photoshop files.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 678.** Select several whole components on one path and align their edges, distribute their centers, or space them evenly. Supported compound shape layers remain editable in PSD and PSB. All 256 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_678.md).

**Next path editing work.** Check component arrangement order and overlap operations in the Photoshop path workflow.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 677.** Double-click a selected shape path or vector mask with either path selection tool to isolate its layer in the Layers and Paths panels. Double-click away from the path, turn off layer filtering, or choose another filter to exit. All 225 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_677.md).

**Next path editing work.** Check mixed path Warp and Free Transform against Photoshop-authored editable output.

Update the README parity banner when the overall workflow estimate reaches the next ten-point milestone.

**Source checkpoint 676.** Switch between Warp and Free Transform while editing paths, masks or shape contours. The mesh follows later placement changes, and the whole edit applies in one Undo. All 202 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_676.md).

**Next path editing work.** Compare a mixed transform on paths captured in Photoshop and verify path isolation and menu availability.

**Source checkpoint 675.** Warp saved paths, vector masks and shape contours in the main canvas. Switch from Free Transform and apply both changes in one Undo. The same edit works in the Photato API and Actions. All 198 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_675.md).

**Next path Warp work.** Verify paths against files authored in Photoshop and compare switching back to Free Transform, split controls, and target availability.

**Source checkpoint 674.** Select saved paths, vector masks and shape contours across layers and transform them together with Command-T. The Photato API and native Actions support the same atomic edit. All 192 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_674.md).

**Next path editing work.** Audit editable Warp for selected vector paths and compare capture and cancellation with the existing Warp workspace. Verify Photoshop's path isolation and exact control behavior when its desktop session is available.

**Source checkpoint 673.** Direct Selection now previews and selects anchors inside a dragged marquee. Shift adds to the selection. The same operation is available through the Photato API. All 186 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_673.md).

**Next path editing work.** Support selecting paths across layers while retaining the active path used by Pen and Direct Selection. Apply one editable transform to the selected targets and keep the same atomic document history through the API.

**Source checkpoint 672.** Command-T now transforms a saved path, vector mask or shape contour independently of its layer. Select whole contours or individual anchors and apply the same edit through the Photato API or an Action. All 156 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_672.md).

**Next path editing work.** Extend Direct Selection to marquee selection of points and improve multi-path selection across layers. Use a saved Photoshop reference for partial transforms when the installed editor responds.

**Source checkpoint 671.** Perspective and Distort now move linked vector masks with the artwork and keep unlinked masks fixed. Masks remain editable after native, PSD and PSB saves. All 131 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. [Qualification](SOURCE_PUBLICATION_671.md).

**Next Free Transform work.** Verify independent Free Transform for selected saved paths, vector masks, and shape contours. Command-T currently routes to layer or pixel transforms. Add a path target that preserves unselected geometry and uses the same native and API edit.

**Source checkpoint 670.** Embedded and linked PDF pages keep editable Perspective and Distort placement in PSD and PSB. Photato renders the source PDF at a density suited to the projected detail and retains the saved corners. All 109 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_670.md).

**Next Smart Object work.** Apply projective placement to editable vector masks, including the linked mask path and unchanged document-space position for unlinked masks. Obtain a Photoshop-authored reference for camera-angle PDF placement and linked masks.

**Source checkpoint 669.** Embedded and linked PDF Smart Objects retain editable Warp in PSD and PSB. The renderer resamples the original PDF when the Warp magnifies the artwork. The page, crop and layer controls stay editable. All 88 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_669.md).

**Next Smart Object work.** Qualify standalone PDF perspective at document-pixel density and compare the outputs against Photoshop-authored warped and perspective PDF files when the live app responds. In the owned projective case, the original 108 × 72 cache differs in 1,687 of 593,920 bytes from the fourfold PDF sampling comparison.

**Source checkpoint 668.** Cylinder Warp curves artwork around a product mockup in the native Warp sheet. PSD and PSB keep the editable shape when a Smart Object is reopened, replaced or relinked. All 134 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The prior Intel RGB32 difference reproduced in a separate run. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_668.md).

**Next Smart Object work.** Verify Photoshop-authored Cylinder files and live output when the installed app responds. The owned PDF fixture rerenders at 324 × 216 at threefold scale. An identity Warp mesh drops to the 108 × 72 cache and changes 1,278 composite bytes. Reuse the high-resolution PDF render through Warp and qualify editable PSD and PSB output. [Adobe PDF placement workflow](https://helpx.adobe.com/photoshop/desktop/app-integrations/place-illustrator-files-or-pdf-in-photoshop.html)

**Source checkpoint 667.** PSD and PSB now reopen supported Smart Object Warp presets, cubic meshes and nonuniform split grids as editable settings. Relinking a missing original restores its live Warp. 1,537 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_667.md).

**Next Smart Object work.** Continue with Warp presets missing from the native model, starting with Cylinder. Verify a live Photoshop Warp open, adjustment and save when document scripting responds.

**Source checkpoint 666.** PSD and PSB preserve the image preview, location and four-corner placement of a linked Smart Object when its original is missing. Free Transform uses the saved artwork frame. Relinking restores source-based perspective editing. 1,511 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_666.md).

**Next Smart Object work.** Preserve editable non-identity Warp placement in PSD and PSB. Verify a live Photoshop perspective open, relink and save when document scripting responds.

**Source checkpoint 665.** Embedded Smart Objects with perspective placement keep their original bytes and editable corners in PSD and PSB. Free Transform starts from the saved artwork frame. 1,507 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_665.md).

**Next Smart Object work.** Verify a live Photoshop perspective open, edit and save when document scripting responds. Continue linked projective cache geometry and editable Warp coverage.

**Source checkpoint 664.** Photoshop document manifests can include JPEG or PNG layer previews and exact copies of embedded Smart Object originals. The assets use Photato's authenticated local download URLs. 1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_664.md).

**Next manifest work.** Compare the manifest's thumbnail behavior, linked metadata and full layer descriptors with Adobe-hosted examples. Continue independent desktop Smart Object and PSD interchange checks.

**Source checkpoint 663.** The Adobe-compatible manifest reports Photoshop document and layer metadata. Use the returned layer IDs to edit the same PSD or PSB through create-composite. 1,498 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional masked RGB32 test passed on Apple Silicon. On Intel, eight PSD composites matched the previous build byte for byte and reproduced its existing differences from the Photoshop fixtures. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_663.md).

**Next manifest work.** Cover hosted layer thumbnails and export of original Smart Object assets. Compare the result schema and layer geometry with Adobe-hosted examples.

**Source checkpoint 662.** Fit or fill replacement artwork inside an existing embedded Smart Object frame. The new ingredient remains editable as a nested Smart Object, including artwork outside the visible frame. Both the Photato and Adobe-compatible APIs expose content placement. All 1,493 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_662.md).

**Next Smart Object work.** Verify absolute scaling fields and repeated projective edits in Photoshop. The published manifest route still needs to report editable Smart Object sources, masks and blend settings.

**Source checkpoint 661.** Smart Object template jobs can set opacity, blend mode and editable pixel masks when they place or replace artwork. Photato exposes the supported fields in its API capabilities. The 1,482 selected cases passed across qualification and replay in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Each initial run passed 1,481 cases. After updating the obsolete mask assertion, all 142 replay cases passed in each configuration. The application inputs and signed binary stayed byte-identical. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_661.md).

**Next Smart Object work.** Add the published frame-contained replacement workflow and retain the original ingredient as nested editable artwork. Adobe-compatible manifest appearance and independent Photoshop transform comparisons remain open.

**Source checkpoint 660.** Free Transform handles follow an affine Smart Object's saved corners. Side and corner drags scale along the artwork's axes, and the angle field reads its current rotation. The Photato API exposes the frame and commit delta. All 1,477 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_660.md).

**Next Smart Object work.** Verify absolute scaling fields and repeated projective edits against a responsive Photoshop session. The remaining template appearance gaps include blend options and pixel masks.

**Source checkpoint 659.** Properties and Free Transform now use the original geometry of linked artwork when a reopened PSD or PSB has only a cached preview. The Photato API reports the same source transform, rotation and bounds. All 1,472 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_659.md).

**Next transform work.** Compare oriented Free Transform handles and numeric scaling for already rotated layers. The current draft starts from the source's document-aligned bounds. Linked and embedded template appearance fields remain open.

**Source checkpoint 658.** The Adobe-compatible template API can set Smart Object size, position, rotation, skew and anchor. Jobs can place artwork relative to other layers and change the geometry of a linked PSD without supplying its original artwork again. All 1,468 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_658.md).

**Next linked workflow.** The desktop Properties rotation readout and the Photato document state still read the cache transform for missing-source PSDs. Verify and expose the original geometry through the native controls and a compatible API representation. Template blend options and pixel masks remain open.

**Source checkpoint 657.** Place Embedded and Place Linked now size artwork from its print resolution and the destination ppi. Resize Image During Place fits oversized artwork after converting to document pixels. The Photato API exposes the same geometry through an explicit physical sizing option. All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_657.md).

**Next live placement comparisons.** Measure fractional center transforms and RGB pixels at 72, 144 and 300 ppi. Include odd source dimensions, different grid densities, oversized artwork, rasterized placement, linked replacement and PDF page and image selection.

**Next API gap.** Add documented custom transforms to Smart Object template jobs through the existing Smart Object transform engine. Verify geometry, original-source retention and rejected requests. [Adobe schema](https://github.com/AdobeDocs/ffs-photoshop-API/blob/main/static/photoshopv2-api.json).

**Source checkpoint 656.** PSD and PSB files now keep both linked-file locations. Locate Package Sources can find approved artwork in nested folders after a document moves. Desktop and API operations use the same lookup when updating or packaging the document. All 1,457 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_656.md).

**Remaining linked interchange.** With a responsive Photoshop session, place the owned files and compare its package output, relink behavior, and the matching merged and layer samples. Test the original and moved versions and a same-size file saved at a different PPI.

**Source checkpoint 655.** General settings now control automatic fit, the placement transform preview and whether new embedded artwork becomes a Smart Object or a pixel layer. Command–K opens the native General pane. The Photato API exposes the three persistent preferences and explicit pixel-layer placement for new embedded and PDF artwork. All 1,452 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. [Qualification](SOURCE_PUBLICATION_655.md).

**Next placement comparison.** In a responsive Photoshop session, compare oversized and odd-sized sources at equal and unequal source and document PPI, both transform modes, pixel output, and relative package resolution. Use owned disposable documents and a clean restore of any changed preferences.

**Source checkpoint 654.** A 1.18 GB linked PSB passed native and approved API placement, background refresh, repeated packaging, relink, embedding and Undo. Linked native, PSD and PSB outputs matched across both compiled architectures. [Qualification](SOURCE_PUBLICATION_654.md).

**Next linked workflow.** Measure the same owned large PSB in Photoshop's Place Linked workflow and verify relative package resolution, update behavior and relink across the two applications. The installed Photoshop session timed out at checkpoint 653, so review app readiness before opening disposable copies. [Adobe Place Linked workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/import-files/place-a-file-in-photoshop.html).

**Source checkpoint 653.** Apple Silicon and Intel under Rosetta wrote identical 1,182,448,710-byte PSBs from the same nested edit. Duplicate Smart Filter masks and copied linked previews survive save and reopen. [Qualification](SOURCE_PUBLICATION_653.md).

**Next linked workflow.** Desktop Place Linked, relink and update still use `LinkedArtworkRead`'s 64 MiB file guard and in-memory reader. Measure the owned large PSB in Photoshop's Place Linked workflow. Carry verified private backing through Photato's approved file reader, linked preview, source updates and packaging where the file formats permit it. The local API should document file-based capabilities and continue applying its HTTP transfer budget. [Adobe Place Linked workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/import-files/place-a-file-in-photoshop.html).

**Source checkpoint 649.** PSD, PSB and chunked native Smart Object sources have a local 256 MiB budget. The two previously rejected PSBs retained exact bytes and editable contents, and a 262.5 MB reference passed native and PSB round trips. [Qualification](SOURCE_PUBLICATION_649.md).

**Source checkpoint 646.** The 9-megapixel editable Smart Filter test dropped from 164.4 to 7.2 seconds on optimized Apple Silicon. Three PSD and PSB exports matched the previous Photato codec byte for byte. [Qualification](SOURCE_PUBLICATION_646.md).

**Source checkpoint 638.** Native documents retain committed print settings and hard-proof conditions. Editable PSD and PSB update supported Photoshop Print Information and Print Style fields. [Qualification](SOURCE_PUBLICATION_638.md).

**Source checkpoint 637.** Photato remembers accepted native print defaults and restores supported Print Information and Print Style fields when opening Photoshop files. [Qualification](SOURCE_PUBLICATION_637.md).

**Source checkpoint 636.** Photato fits high-resolution photos to paper while retaining original samples, and can prepare just the visible region of a much larger document printed at a fixed scale. [Qualification](SOURCE_PUBLICATION_636.md).

**Source checkpoint 635.** The desktop and authenticated PDF route can prepare a small selection from a sparse document at the maximum canvas dimensions. [Qualification](SOURCE_PUBLICATION_635.md).

**Source checkpoint 634.** Print and the authenticated PDF download create named process and spot pages for eligible CMYK, Duotone and Multichannel artwork. [Qualification](SOURCE_PUBLICATION_634.md).

**Source checkpoint 633.** Returning a standard ordered process set to CMYK keeps extra plates as editable spots. Eligible PSD and PSB files retain the merged process values through the round trip. [Qualification](SOURCE_PUBLICATION_633.md).

**Source checkpoint 632.** Eligible layered CMYK and Lab documents preserve their numerical components through the Multichannel conversion and Delete Channels, including independent black ink. [Qualification](SOURCE_PUBLICATION_632.md).

**Source checkpoint 631.** Multichannel PSD and PSB output preserves saved spot inks as printing plates, including their density, swatch, Solidity and identifier. [Qualification](SOURCE_PUBLICATION_631.md).

**Source checkpoint 630.** The Workflow Guide moves clear of a covered target. Its lessons highlight specific dialog fields and buttons and accept Show Me to replay the cue. [Qualification](SOURCE_PUBLICATION_630.md).

**Source checkpoint 629.** The Channels panel can place masks before or between printing plates. Photato archives, PSD and PSB preserve the same sequence. [Qualification](SOURCE_PUBLICATION_629.md).

**Source checkpoint 628.** Drag an individual channel to duplicate, copy, reorder or delete it. The Workflow Guide follows the actual popup row once AppKit has positioned the menu. [Qualification](SOURCE_PUBLICATION_628.md).

**Source checkpoint 620.** Large 8- and 16-bit Multichannel printing plates and masks open, remain editable, and save through the native paged PSD and PSB pipeline. [Qualification](SOURCE_PUBLICATION_620.md).

**Source checkpoint 619.** The Workflow Guide ranks suggestions by task context, adds a configurable maximum, and flashes the walkthrough target. [Qualification](SOURCE_PUBLICATION_619.md).

**Source checkpoint 618.** Eligible editable RGB8, RGB16, and RGB32 PSD and PSB files can omit the merged preview while keeping saved alpha, spot and Quick Mask planes. [Qualification](SOURCE_PUBLICATION_618.md).

**Source checkpoint 617.** The optional Workflow Guide suggests useful next steps and walks through 20 editing tasks. [Qualification](SOURCE_PUBLICATION_617.md).

**Source checkpoint 616.** Large Grayscale, CMYK and Lab Photoshop saves reuse unchanged layer samples. Eligible Gray32 previews reuse the same row writer. [Qualification](SOURCE_PUBLICATION_616.md).

**Source checkpoint 615.** Large editable and flattened Grayscale, CMYK and Lab Photoshop files keep unchanged separation samples implicit. [Qualification](SOURCE_PUBLICATION_615.md).

Verify large native-mode output and continue dense and live Photoshop interchange checks.

**Source checkpoint 614.** Large Raw, PackBits and ZIP RGB Photoshop layers, masks and saved channels retain sparse editable raster storage. [Qualification](SOURCE_PUBLICATION_614.md).

Verify large Gray, CMYK and Lab native planes next, then measure output and dense interchange.

**Source checkpoint 613.** Large flattened Raw and PackBits RGB documents retain editable pixels, transparency and saved channels without staging all process planes. [Qualification](SOURCE_PUBLICATION_613.md).

Verify sparse ZIP layer and mask import, then measure native-mode and dense document interchange.

**Source checkpoint 612.** Sparse PSD and PSB output reuses unchanged saved alpha, spot, and Quick Mask rows and retains the exact unchanged Float32 source words. [Qualification](SOURCE_PUBLICATION_612.md).

Verify flattened RGB sparse import, then check dense and ZIP paths and compare with Adobe-authored channel files.

**Source checkpoint 611.** Large Raw and PackBits PSD and PSB imports retain saved alpha, spot, and Quick Mask planes as implicit gray and edited tiles. [Qualification](SOURCE_PUBLICATION_611.md).

Verify the paged saved-channel exporter, then check dense and ZIP paths and compare with Adobe-authored channel files.

**Source checkpoint 610.** Layered PSD and PSB can retain saved alpha, spot, and Quick Mask planes when their Version Info declares the merged preview absent. [Qualification](SOURCE_PUBLICATION_610.md).

Measure Adobe compatibility-off export at higher bit depths and with saved channels. Continue dense PSB and File Handling checks.

**Source checkpoint 609.** File Handling, Image Processor and Photato API output can omit the merged preview for eligible RGB8 PSD and PSB files. [Qualification](SOURCE_PUBLICATION_609.md).

Measure Photoshop compatibility-off output at 16/32 bits and with saved channels. Continue dense PSB and wide Feather validation.

**Source checkpoint 608.** Large sparse PSD and PSB saves can stream full-width raster edits through the existing row writer. [Qualification](SOURCE_PUBLICATION_608.md).

Continue Photoshop File Handling and measure Maximize PSD and PSB File Compatibility in owned files. Continue dense PSB and wide Feather validation.

**Source checkpoint 607.** Large Photoshop layers sample across their height and retain sparse storage when their channels use raw or RLE. [Qualification](SOURCE_PUBLICATION_607.md).

Qualify saving wide raster edits with a bounded merged scratch raster. Compare the native file and the entire independent RLE row table and payload. Continue dense PSB and wide Feather validation.

**Source checkpoint 606.** Large RLE Photoshop layers retain their implicit color and store the edited tiles during import. [Qualification](SOURCE_PUBLICATION_606.md).

Sample more than the first row when choosing the implicit values for an import. Verify a painted first row, raw and mixed-compression layers, and metadata and malformed-input guards. Continue dense PSB and wide Feather validation.

**Source checkpoint 605.** Large sparse Photoshop files reuse merged pixels and identical rows during export. [Qualification](SOURCE_PUBLICATION_605.md).

Qualify a nonuniform 300,000 × 300,000 editable RGB raster round trip. Measure retained sample storage, compare every edited tile and implicit pixel, and exercise both deep samples and malformed rows. Continue variable-edge Feather work and retry Photoshop 2026 file verification when the live app responds.

**Source checkpoint 604.** Wide feathered vector masks reuse identical edge profiles in both the filter and the compositor. [Qualification](SOURCE_PUBLICATION_604.md).

Move the proved large-canvas composition into the PSB output workflow. Audit the existing band and PackBits pipelines, then qualify reusable merged rows against independent bytes and real file round trips. Continue broad variable-edge Feather performance and retry live Photoshop capture when document scripting responds.

**Source checkpoint 603.** Large feathered vector masks reuse composited tiles wherever the filter inputs and layer samples are identical. [Qualification](SOURCE_PUBLICATION_603.md).

Measure dense wide-Feather composition at the maximum dimensions and reduce work in repeated boundary rows. Keep the exact streaming input order, straight RGB32 samples, and file format limits. Retry live Photoshop capture when document scripting responds.

**Source checkpoint 602.** Dense feathered vector masks skip scratch rasterization for solid interior and exterior pieces and filter their coverage from the existing piece grid. [Qualification](SOURCE_PUBLICATION_602.md).

Skip repeated composition in dense solid mask interiors. Classify exact Feather footprints, carry those constants through the existing layer compositor and reuse result tiles. Compare whole output and dense boundary limits. Retry live Photoshop capture when document scripting responds.

**Source checkpoint 601.** Large feathered vector masks use stored coverage to limit render work. Sparse inverted rectangles use the existing affected-tile renderer when it has less work. [Qualification](SOURCE_PUBLICATION_601.md).

Exercise dense nonrectangular masks across the full canvas. Start by measuring uniform interior rows and bounding the work in regions where the existing Gray8 rasterizer gives constant coverage. Preserve antialiased edge samples and exact Feather output. Retry live Photoshop capture for wide vector and Smart Filter masks when document scripting responds.

**Source checkpoint 600.** Large RGB32 raster stacks with rectangular vector masks determine bottom-layer opacity from representative mask windows. [Qualification](SOURCE_PUBLICATION_600.md).

Retain the lower patch count for sparse inverted rectangles. Extend bounded whole-canvas Feather to nonrectangular vector paths and check exact opacity around their real coverage support. Collect fresh Photoshop outputs for wide vector and Smart Filter masks.

**Source checkpoint 599.** Wide rectangular vector masks reuse filtered windows across the canvas. [Qualification](SOURCE_PUBLICATION_599.md).

Prove global opacity for RGB32 bottom raster layers with bounded rectangular Feather before enabling whole-canvas tile reuse on those stacks. Extend coverage to broader paths and capture fresh Photoshop references for wide vector and Smart Filter masks.

**Source checkpoint 598.** Whole-canvas rendering reuses feathered tiles for eligible integer-aligned rectangular vector masks. [Qualification](SOURCE_PUBLICATION_598.md).

Extend whole-canvas Feather through the RGB32 bottom-raster opacity proof and broader vector geometry. Collect fresh Photoshop outputs at wide radii and on Smart Filter masks.

**Source checkpoint 597.** Wide Feather reuses the second filter pass’s window sums when they fit a bounded cache. [Qualification](SOURCE_PUBLICATION_597.md).

Use the remaining timing evidence to reduce wide filter arithmetic and cover broad whole-canvas mask execution. Qualify global opacity for large inverted paths and collect wider Photoshop edge and Smart Filter settings references.

**Source checkpoint 596.** Wide Feather reuses source row bands for vector, pixel and Smart Filter masks. [Qualification](SOURCE_PUBLICATION_596.md).

Use the remaining timing evidence to reduce wide filter arithmetic and cover broad whole-canvas mask execution. Qualify global opacity for large inverted paths and collect wider Photoshop edge and Smart Filter settings references.

**Source checkpoint 595.** Large-canvas vector-mask Feather limits broad coverage preparation to the viewport and its filter margin. [Qualification](SOURCE_PUBLICATION_595.md).

Continue broad-mask full-canvas paging and accelerate the remaining Feather kernel work. Qualify global opacity proofs for large inverted and uniformly covered masks. Collect the remaining Photoshop vector and Smart Filter mask references.

**Source checkpoint 594.** The 1.5 px and 2 px vector-mask Feather settings now reproduce the measured Photoshop step and corner responses. [Qualification](SOURCE_PUBLICATION_594.md).

Collect new authored Photoshop references for additional short and wide radii, subpixel and curved paths, and Smart Filter mask coverage and persisted settings. Use the saved whole-composite differences to guide color and antialiasing checks. Continue the broad-shape and dense Feather capacity work.

**Source checkpoint 593.** Vector masks accept Feather through 1,000 px and keep their paths editable in native documents, PSD and PSB. [Qualification](SOURCE_PUBLICATION_593.md).

Use the measured 1.5 px and 2 px vector transitions and corner samples to validate a separable renderer. Capture wider vector and Smart Filter mask coverage and persisted settings when Photoshop responds. Continue the sparse broad-shape and dense Feather performance limits and the remaining mask editing and interchange differences.

**Source checkpoint 592.** Smart Filter masks accept Feather through 1,000 px and render projected mask regions on sparse large documents. [Qualification](SOURCE_PUBLICATION_592.md).

Capture independently saved Photoshop Smart Filter masks to measure the coverage kernel and locate the persisted density and Feather fields. Continue the vector-mask range, arbitrary affine and dense wide-mask performance, and the broader Smart Filter workflow tests.

**Source checkpoint 591.** Aligned 32-bit raster masks now use Photoshop’s measured filter schedules at 14 fractional Feather settings. [Qualification](SOURCE_PUBLICATION_591.md).

Continue bounded Smart Filter mask Feather. Reuse the mask support rules for sparse placed rasters and compare PSD settings with a saved Photoshop filter-mask reference. The installed Photoshop session must respond before collecting fresh references. The remaining layer-mask work includes unmeasured radii, five Intel texture differences, affine masks and dense wide-radius performance.

**Source checkpoint 590.** Aligned RGB8 and RGB16 raster-layer masks now use integer-rounded Feather stages in rendering and clipping merges. [Qualification](SOURCE_PUBLICATION_590.md).

Use the saved textured and translated controls to separate radius scheduling from per-stage rounding. Continue the unmeasured fractional settings, additional short radii, affine sampling and the separate Smart Filter and vector-mask ranges. Resume independent Rosetta captures after the previous Photoshop reference session closes. Test adjacent masked clips and dense wide-mask workloads.

**Source checkpoint 589.** Merge Clipping Mask, Stamp Group, and eligible Merge Down and Stamp Down commands now use Feather on contributing raster clips. [Qualification](SOURCE_PUBLICATION_589.md).

Next, measure stage rounding for editable RGB8 and RGB16 masks and connect it to clipping. Use the saved partial-opacity and outside-canvas controls to track the remaining Intel residuals. Adjacent masked clips, fractional and affine coverage, Smart Filter and vector masks, and wide dense performance remain open.

**Source checkpoint 588.** Layer-mask Feather now accepts 0–1,000 px in the native controls, Photato API and editable files. [Qualification](SOURCE_PUBLICATION_588.md).

Connect the staged coverage to feathered clipping merges and stamps. Evaluate the core support rectangle and implicit coverage independently for normal and clipped output, including partly off-canvas masks and maximum-size sparse documents. Retain the 250 and 1,000 px stored coverage controls. Two Photoshop clipping-mask merge captures agree on all 25,350 stored words across 3, 4 and 8 px on both tested architectures. The first description mislabeled one capture as ordinary Merge Down. Continue fractional schedules, short-radius rounding, RGB8/16 stage storage, affine/vector/filter masks and Intel vertical rounding. Full sparse wide Feather export and physical validation remain open.

**Source checkpoint 587.** Aligned RGB32 layer masks use a staged square filter at whole-pixel Feather radii from 3 to 100 px. [Qualification](SOURCE_PUBLICATION_587.md).

Continue Feather through the documented 1,000 px limit. Use streamed stage intermediates and sparse support on full-size or translated layers. The area model now matches the saved 250 and 1,000 px non-uniform RGB32 controls on both architectures. Measure fractional scheduling on each architecture, dyadic rounding through 2 px, RGB8/16 stage storage, and remaining Intel area residuals. Verify wider desktop and API settings and PSD/PSB interoperability before widening the range. Feathered clipping merges, vector and Smart Filter masks and affine masks remain open.

**Source checkpoint 586.** Pixel-mask Feather now renders requested regions on 300,000 × 300,000 documents without preparing a full padded mask. [Qualification](SOURCE_PUBLICATION_586.md).

Qualify the exact Feather kernel on non-uniform and transformed masks. The per-stage normalized box model matches all saved line samples at 100, 250 and 1,000 px and seven Apple Silicon impulse planes. Intel impulse output differs by up to two Float32 ULPs. Measure fractional schedules and broaden reference coverage. Implement bounded wider-radius rendering, then enable the new range and feathered clipping operations after desktop, API and persistence checks. Sparse full-canvas composition and large Smart Filter and vector masks retain separate work.

**Source checkpoint 585.** Linear Dodge (Add), Subtract and Divide now work in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. [Qualification](SOURCE_PUBLICATION_585.md).

Continue pixel-mask Feather and the remaining clipped blend modes. Measure the filter scheduling and edge rules against owned impulses and non-uniform masks. Owned Photoshop masks save, reopen and render at 1,000 pixels on both tested architectures. Photato currently caps the property at 100 pixels and needs bounded mask rendering for the wider range.

**Source checkpoint 584.** Supported clipping merges and stamps preserve the editable base pixel mask and apply contributing masks at 8, 16 and 32 bits per channel. [Qualification](SOURCE_PUBLICATION_584.md).

Continue contributed pixel-mask Feather. Use saved impulse and non-uniform masks to check the radius schedule, boundary handling, and Float32 operation order. Adjacent masked clips and additional blend modes remain open.

**Source checkpoint 583.** Multiply, Darken, Lighten and Difference now participate in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. [Qualification](SOURCE_PUBLICATION_583.md).

Continue editable pixel masks on clipping merges and stamps. Check partial clip opacity across all three RGB depths and measure Float32 Density and Feather using the saved Photoshop files.

**Source checkpoint 582.** Supported raster clipping merges and stamps preserve Blend Clipped Layers as Group, the base blend mode, and its opacity. [Qualification](SOURCE_PUBLICATION_582.md).

Continue the four additional clipped blend modes and editable pixel-mask work. Measure Float32 mask Density and Feather against the saved Photoshop controls.

**Source checkpoint 581.** Merge Down and Stamp Down now work between adjacent Normal raster clips in the same clipping stack. [Qualification](SOURCE_PUBLICATION_581.md).

Continue the independent-clipping and broader clip-blend candidates. Verify any changes against their saved Photoshop controls.

**Source checkpoint 580.** Screen clips now participate in supported RGB8 and RGB16 merges and stamps. In-place stamps create an Undo step even when the stored pixels stay identical. [Qualification](SOURCE_PUBLICATION_580.md).

Finish qualifying Merge Down and Stamp Down between adjacent Normal clips. Continue measuring independent clipping and non-Normal bases.

**Source checkpoint 579.** Option-Command-E now stamps into an existing raster when one eligible layer is selected. Stamp Down updates the layer beneath it. Stamp Group updates the base of a supported clipping stack. [Qualification](SOURCE_PUBLICATION_579.md).

Continue qualifying Screen clips, then handle Stamp Down and Merge Down between two clips with the adjacent-clip references.

**Source checkpoint 578.** Command-E now merges a supported Normal raster clipping stack into its base. Photato retains the base geometry, alpha, opacity and blend mode and preserves the unrelated layers. [Qualification](SOURCE_PUBLICATION_578.md).

Continue the observed in-place Stamp Down and Stamp Group workflows, then qualify other clipping blend modes.

**Source checkpoint 577.** Prepared 32-bit Normal layer merges and stamps now account for stored raster pixel masks, including zero coverage and the measured Intel rounding. A maximum-size sparse mask example used two render patches. [Qualification](SOURCE_PUBLICATION_577.md).

Finish the contextual Merge Clipping Mask workflow and continue independent clipping, rich stack and physical checks.

**Source checkpoint 576.** Normal 32-bit merges and stamps preserve the measured color and alpha words in their resulting raster layers, including transparent and very-low-alpha samples. [Qualification](SOURCE_PUBLICATION_576.md).

Continue the measured pixel-mask output path, then compare clipped and grouped HDR layers and the direct Core merge.

**Source checkpoint 575.** Stamp Layers and Stamp Visible now process supported sparse raster stacks at 300,000 × 300,000 pixels. The largest tested canvas with two distant layers needed two render patches. [Qualification](SOURCE_PUBLICATION_575.md).

Continue destructive HDR merge and stamp comparisons, including in-bounds zero alpha. Verify live shortcut dispatch and extend sparse coverage to richer sources.

**Source checkpoint 574.** Stamp Layers and Stamp Visible create a new editable pixel layer while retaining the originals. Both commands are available from the native Layer menu, Actions and the Photato API. [Qualification](SOURCE_PUBLICATION_574.md).

Measure maximum-size sparse stamping and verify live shortcut dispatch. Continue the ordinary HDR merge, small-alpha and independent clipping comparisons.

**Source checkpoint 573.** Intel HDR Normal compositing now matches the measured rounding when a color contribution underflows. The renderer also preserves Photoshop's opaque-source copy rules for ordinary and clipped layers. [Qualification](SOURCE_PUBLICATION_573.md).

The owned Merge Visible, Merge Down and Merge Layers captures localize a difference in the prepared HDR transaction. Stamp Visible and Stamp Layers both retain the original layers and place the new layer above the active or top selected layer. Add the native and API stamp workflow using the captured placement and naming. Apply the exact small-alpha rule and continue isolating independent clipping. See [Adobe's documented behavior](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/merge-and-stamp-layers.html).

**Source checkpoint 569.** 32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves. All 661 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_569.md).

Finish the RGB16-to-Gray fixed-point comparison and measure 8-bit conversion dithering. Continue custom linear white-point and transparent Multiply comparisons. Photoshop Actions still need validation for channel switches and percentage coordinates.

**Source checkpoint 568.** RGB and grayscale gamma 0.5 profiles now promote to 32 Bits/Channel using the measured rounding on each architecture. PSD and PSB use native gray samples for supported 32-bit layer stacks. All 657 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_568.md).

Extend the direct power path for lower gamma values after verifying RGB and 8-bit inputs. Compare RGB-to-Gray mode conversion and finish measuring transparent Multiply and other HDR blend modes. Photoshop Actions still need validation for channel switches and percentage coordinates.

**Source checkpoint 567.** Promoting an 8-bit or 16-bit RGB or grayscale document to 32 bits now uses the supported tone curves from its current ICC profile. All 651 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_567.md).

Integrate the independently verified gamma 0.5 conversion, then measure RGB to Gray mode conversion and the output for transparent or masked layers. Photoshop Actions still need validation for channel switches and percentage coordinates.

**Source checkpoint 566.** PSD and PSB exports now preserve all 32-bit grayscale samples when the document contains one visible, opaque Background. All 629 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_566.md).

Collect independent Photoshop RGB32 and Gray32 conversion references. Compare multilayer Gray32 merged output and continue verifying Actions channel switches and percentage-based tool coordinates.

**Source checkpoint 565.** The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures. All 608 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_565.md).

Isolate the RGB32 and Gray32 conversion differences across architectures. Also verify Photoshop’s Action step capture for channel switches and percentage-based tool coordinates.

**Source checkpoint 564.** Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates. All 583 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_564.md).

Check Photoshop’s Allow Tool Recording control and how Actions capture channel changes before extending recorded channel edits.

**Source checkpoint 563.** Photato Actions can enter Quick Mask, record Brush and Pencil strokes, and convert the edited mask back to a selection in one undoable Action. All 558 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_563.md).

Continue with Brush Actions for process color components and independent ink plates. Recheck Photoshop recording controls and live channel playback when desktop access returns.

**Source checkpoint 562.** Photato Actions can record Brush strokes on Smart Filter masks and saved alpha and spot channels. They also retain automatic pixel-layer creation when painting over a shape. All 531 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_562.md).

Continue with Quick Mask entry, painting, and exit in Actions. Recheck Photoshop recording controls and live channel playback when desktop access returns.

**Source checkpoint 561.** Paint Bucket fills can be recorded and replayed in Photato Actions with the saved settings and the playback document’s own pixels and selection. All 527 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_561.md).

Continue with Brush Actions for Smart Filter masks and saved auxiliary channels. Recheck Photoshop Action recording and ruler units when desktop access returns.

**Source checkpoint 560.** Edit Fill and Stroke can erase pixels through the native dialogs, the existing Photato API, and recorded Actions. All 522 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_560.md).

Continue with portable Paint Bucket and nonraster Brush Actions. Collect Photoshop reference samples for Clear and verify the live dialogs when desktop access returns.

**Source checkpoint 559.** Paint Bucket has a Clear mode, a typed Photato API, and bounded writeback for separated sparse and full solid fills. All 486 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_559.md).

Continue with Clear in Edit Fill/Stroke and portable Paint Bucket and nonraster Brush Actions. Dense pattern writeback and exact Photoshop color-region bytes remain open. Live cursor, placement, continuous stroke, keyboard and physical editing checks remain open.

**Source checkpoint 558.** Paint Bucket and Magic Wand page large color matches, including tested sparse selections and fills at 300,000 pixels per side. All 481 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_558.md).

Continue with Paint Bucket Clear and its native API. Extend large partial-opacity, pattern and connected-background fills, and qualify live Photoshop output when the Mac is available. Edit Fill/Stroke and portable nonraster Brush Actions remain queued. Live cursor, placement, continuous stroke, keyboard and physical editing checks remain open.

**Source checkpoint 557.** Shift-plus and Shift-minus cycle the Brush and Pencil Mode picker. Shift-Option letters select documented modes directly. All 454 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_557.md).

Continue with memory-bounded color matching for Paint Bucket and Magic Wand, then Paint Bucket Clear and its shared API, Edit Fill/Stroke, and portable nonraster Brush Actions. Collect exact Photoshop samples when the Mac is available. Live cursor, placement, continuous stroke, keyboard and physical editing checks remain open.

**Source checkpoint 556.** Brush can paint Behind existing pixels or Clear their alpha. Pencil also supports Clear. All 418 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_556.md).

Continue with Adobe's direct Behind and Clear keyboard shortcuts, Clear in Paint Bucket and Edit Fill/Stroke, and portable nonraster Brush Actions. Collect exact Photoshop samples when the Mac is available. Live cursor, placement, continuous stroke, keyboard and physical editing checks remain open.

**Source checkpoint 555.** The focused canvas accepts braces for brush hardness, Left and Right for tip rotation, and Option-digits for smoothing. All 413 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_555.md).

Continue B01 with the documented Clear and Behind paint operations, alongside controlled subpixel and continuous stroke captures. Live shortcut behavior, Brush defaults, cursor preferences, physical editing cadence, ColorSync and Gradient Map differences remain open.

**Source checkpoint 554.** The four factory Round presets now change smoothly from soft feathering to an opaque core with a narrow edge. The aligned nonzero-hardness samples improved from a worst alpha difference of 161 to 12 of 255 levels. All 411 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_554.md).

Continue B01 with controlled subpixel placement, independent intermediate hardness settings and continuous stroke output. Verify live Brush defaults and tablet input. The documented hardness and angle shortcuts can proceed independently. Physical cadence, ColorSync and Gradient Map differences remain open.

**Source checkpoint 553.** Build 553 widens zero-hardness Soft Round coverage. Aligned single-dab alpha differs from saved Photoshop samples by at most 3 of 255 levels across the six tested sizes. All 409 selected tests passed in three configurations. [Qualification](SOURCE_PUBLICATION_553.md).

Continue B01 with controlled subpixel captures and the transition from zero to higher hardness. Validate hard-tip edge coverage, continuous strokes and native-to-Photoshop defaults. Physical display and tablet timing, ColorSync and Gradient Map differences remain open.

**Source checkpoint 552.** Canvas numbers set Brush opacity and flow, including Airbrush. All 404 selected tests passed in three configurations. Saved Photoshop alpha establishes a wider required brush footprint. [Qualification](SOURCE_PUBLICATION_552.md).

Continue B01 with controlled subpixel and repeat captures, a broader brush support model and exact alpha comparison. Q03 physical display cadence and tablet timing, inherited ColorSync and Gradient Map differences remain open.

**Source checkpoint 551.** Wide brush output tiles are prepared in parallel. All 338 checked buffers match build 550 on each architecture. All 401 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_551.md).

Continue Q03 with physical display and tablet input checks. Investigate exact Photoshop brush coverage. Keep the inherited ColorSync and Gradient Map differences open.

**Source checkpoint 550.** Large raster composition and display packing run in independent bands. All 192 checked buffers match build 549 on each architecture. All 400 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_550.md).

Continue Q03 with wide brush preparation and exact Photoshop brush coverage. Qualify physical display and tablet input. Keep the inherited ColorSync and Gradient Map differences open.

**Source checkpoint 549.** Eligible wide dabs sample coverage in parallel. All 146 checked buffers match build 548 and all 398 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_549.md).

Continue Q03 with wide-tile output and canvas publication costs. Qualify physical display and tablet input. Keep Photoshop brush sampling and the inherited ColorSync and Gradient Map differences open.

**Source checkpoint 548.** Prepared Normal brush output speeds up complete and retained raster painting. All 121 checked buffers match build 547 and all 397 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_548.md).

Continue Q03 with exact wide-tip coverage and changed-dab preparation. Apply timing and pixel comparisons to selected, textured and other blend configurations. Keep physical display and tablet input, Photoshop sampling and the inherited ColorSync and Gradient Map gaps open.

**Source checkpoint 547.** Wide raster Brush gestures retain coverage between input batches. All 60 retained outputs match build 546 and all 395 selected methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_547.md).

Continue Q03 with first-dab and changed-dab preparation. Measure changed-input frames independently of repeat draws, and qualify physical display and tablet input. Keep Photoshop Brush sampling, factory presets and the inherited ColorSync and Gradient Map differences open.

**Source checkpoint 546.** Regional canvas updates pack directly into the display buffer. All 80 tested outputs match build 545 on each architecture, and all 392 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_546.md).

Continue Q03 with wide-tip brush preparation. On Apple Silicon the 5,000 px software case spends 384 ms painting, 127 ms compositing and 103 ms on display conversion. Measure repeated strokes and physical display and tablet input. Keep broader layer stacks, Photoshop brush sampling and presets, exact Gradient Maps and the inherited ColorSync difference open.

**Source checkpoint 545.** Eligible flat tone stacks render in one tile pass. All 64 tested outputs match build 544, and all 390 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_545.md).

Continue Q03 with brush preparation, the largest measured software phase at 383 ms in the 5,000 px case. Extend exact composition to broader layer stacks and measure real display and tablet input. Keep independent Photoshop brush sampling, preset parity and exact Gradient Maps open.

**Source checkpoint 544.** Wide Brush previews start from the initial pointer event. All 64 tested buffers match build 543, and all 388 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_544.md).

Continue Q03 with layered regional composition. In the isolated 24 MP first-dab probe at 5,000 px, composition takes 1555 ms for about 17.2 MP of affected display. Repeat the 24 MP hosted case and qualify physical display and tablet input. Keep independent Photoshop brush sampling, preset parity and exact Gradient Maps open.

**Source checkpoint 543.** Large gradients reuse exact samples and write by tile. All 84 tested outputs match build 542 and all 372 selected methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. Physical editing cadence and the remaining Photoshop Gradient Map differences are open. [Qualification](SOURCE_PUBLICATION_543.md).

Continue Q03 with large-tip Brush feedback, dense Float32 editing and physical frame delivery. Keep timed smoothing, subpixel coverage, factory presets and exact Photoshop gradient samples open for independent comparison.

**Source checkpoint 542.** Linear and Perceptual gradient samples agree across the optimized architectures. All 370 selected methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. The saved Photoshop Gradient Map differences remain open. [Qualification](SOURCE_PUBLICATION_542.md).

Continue Q03 with the remaining large-tip preparation cost and physical feedback measurements. Gradient sampling, timed Brush smoothing, subpixel coverage and factory presets still need independent Photoshop qualification.

**Source checkpoint 541.** The hosted 1,800 px Brush first draw improved from 802 ms to 489 ms. The scoped Brush and compositor pixels match build 540. All 266 selected methods pass in Debug and both optimized architectures. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_541.md).

Q03 continues with full-size Brush preparation, dense linear rendering and physical measurements. B01 still needs timed smoothing, independent subpixel samples and factory preset validation.

**Source checkpoint 540.** All 32 tested Brush outputs now match across optimized Apple Silicon and Intel under Rosetta. All 251 selected methods pass in Debug and both optimized architectures. Photoshop Brush pixel comparisons and physical editing cadence remain open. [Qualification](SOURCE_PUBLICATION_540.md).

Q03 continues with the measured large-tip preparation and dense linear Float32 render costs. The 1,800 px retained path and the 2,500–5,000 px complete path both need faster on-canvas feedback. B01 still needs timed smoothing, independent subpixel samples and factory preset validation.

**Source checkpoint 539.** Large Brush coverage and output use tile-local writes. The 5,000 px color-dynamics test used 74% less render time on Apple Silicon. All 205 selected methods pass in Debug and both optimized architectures. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_539.md).

Q03 still needs hosted large-tip input and display timing. B01 continues with independent subpixel samples, timed smoothing, factory presets and live tool limits.

**Source checkpoint 538.** The primary Brush diameter reaches 5,000 px. All 204 selected methods pass in Debug and both optimized architectures. Wide-tip responsiveness and exact Photoshop alpha remain open. [Qualification](SOURCE_PUBLICATION_538.md).

B01 continues with subpixel and independent soft-tip samples, timed smoothing and preset limits. Verify current Photoshop Brush and Pencil controls when the desktop is accessible. Q03 retains wide-tip responsiveness, physical presentation and stylus timing.

**Source checkpoint 537.** Pencil strokes record and replay in Actions, including Auto Erase on the playback target. All 199 selected methods pass in Debug and both optimized architectures. A 24-dab Photoshop reference quantifies the remaining Brush alpha differences. [Qualification](SOURCE_PUBLICATION_537.md).

B01 next needs independent repeat and subpixel reference samples before changing the soft brush falloff, along with timed smoothing and factory preset qualification. Quick Mask Pencil Actions need a visibility-aware playback context. Q03 physical and stylus timing remain open.

**Source checkpoint 536.** Shift-click connects Brush and Pencil strokes. All 178 selected methods pass in Debug and both optimized architectures. Photoshop alpha differs on the test sheet. [Qualification](SOURCE_PUBLICATION_536.md).

B01 continues with independent Brush coverage across diameters and subpixel positions, then timed smoothing and factory presets. Pencil Action playback is open. Q03 retains publication latency, stylus timing and physical display checks.

**Source checkpoint 535.** The ordinary Brush starts at 10% smoothing. The current desktop and API defaults, explicit zero, Actions, tab transfer and protected tool routing pass 167 selected checks in all three configurations. Physical presentation and full Photoshop parity remain open. [Qualification](SOURCE_PUBLICATION_535.md).

B01 still needs independent Photoshop Brush geometry and smoothing comparisons, plus factory preset and stylus validation. Q03 retains the measured first-frame publication delay, continuous input timing and physical presentation checks.

**Source checkpoint 534.** The first ordinary Brush frame submits its worker during input on a ready canvas. All 114 selected methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. Physical presentation and full Photoshop parity remain open. [Qualification](SOURCE_PUBLICATION_534.md).

Q03 remains open for publication latency, steady-stroke scheduling and display measurements. Verify the ordinary Brush factory smoothing default and handle explicit and legacy settings before changing paint defaults.

**Source checkpoint 533.** The ready ordinary Brush canvas starts its first preview with the input event. All 100 selected checks pass in Debug, optimized Apple Silicon and Intel under Rosetta. Physical presentation and full Photoshop parity remain open. [Qualification](SOURCE_PUBLICATION_533.md).

Q03 remains open. Measure when the background renderer starts relative to the first input, then address the remaining delay and verify physical presentation. The next Brush settings check is the ordinary round Brush’s 10% factory smoothing, including explicit, omitted and legacy values in both editing entry points.

**Source checkpoint 532.** Reuse completed Float32 composite tiles and preserve unaligned edge samples. All 99 selected methods pass in Debug, optimized Apple Silicon and translated Intel. The universal package passes static checks. Physical display timing and full Photoshop parity remain open. [Qualification](SOURCE_PUBLICATION_532.md).

Continue Q03 with the delay before preview preparation, layered region compositing, and physical input and display measurements.

**Source checkpoint 531.** Find changed tiles without sorting direct canvas storage. All 90 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The universal package passes its checks. Physical editing cadence and Photoshop byte comparisons remain open. [Qualification](SOURCE_PUBLICATION_531.md).

Continue Q03 with layered regional render work and physical editing measurements.

**Source checkpoint 530.** Ready canvas previews schedule AppKit drawing directly. All 59 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The universal package passes its checks. Physical editing cadence and Photoshop output comparison remain open. [Qualification](SOURCE_PUBLICATION_530.md).

Continue Q03 with the 24 MP layered stroke workload. Its measured input-to-draw tail and the actual monitor presentation remain open.

**Development checkpoint 529.** The regional memory-mapping experiment was withdrawn after the 24 MP timing and memory comparisons. Build 528 remains the published application source. Hosted AppKit timing now separates preview preparation from the delay before drawing. Continue Q03 with the canvas publication path. [Measurements](CANVAS_PREVIEW_EXPERIMENT_529.json).

**Source checkpoint 528.** Faster save-format checks and native JPEG XL still import. All 69 selected methods pass in Debug, optimized Apple Silicon and translated Intel. Universal package checks pass. Photoshop sample comparison and physical 60 fps remain open. [Qualification](SOURCE_PUBLICATION_528.md).

**Source checkpoint 526:** Retained exact selection contours, Space-repositioned marquee creation and active polygon routing. All 86 selected methods and 15 new methods pass in Debug and both optimized architectures; universal package checks pass. Native launch/title verified; live editing/save/reopen remain unqualified after file-chooser automation failed. Q03/S01, physical FPS and all prior failures remain open. [Qualification](SOURCE_PUBLICATION_526.md).

**Source checkpoint 524:** Selection borders drag/nudge with queued keys and immediate replacement feedback; Canvas Size retains zoom/pan. Debug/optimized ARM/translated Intel each 65/65 and all 13 new methods pass. Universal static checks pass; live UI unverified (no approved tool available). All prior scope/failures and Q03 remain open. [Qualification](SOURCE_PUBLICATION_524.md).

**Source checkpoint 523:** Retained layer-mask and Adjustment Brush previews process about 60 model previews/s in the owned 3072-square workload. Debug 52/52 and both optimized architectures 69/69/all 15 new pass. Native painting/history/Properties/save/reopen/Quit and universal package checks pass. Physical 60 fps/live Sky/full Q03 and all prior failures remain open. Continue Q03 major-stillneeded. [Qualification](SOURCE_PUBLICATION_523.md).

**Source checkpoint 522:** Masked adjustment previews improve about 23× in the controlled native-model workload;30/30 selected methods and all 8 since public 520 pass each optimized architecture. Native optimized universal paint/history/Properties/save/reopen/Quit and static checks pass. Masks remain near 27/s; physical 60 fps/live Sky/full Q03 and all prior failures remain. Current Q03 retained mask coverage, major-stillneeded. [Qualification](SOURCE_PUBLICATION_522.md).

**Source checkpoint 520 — 9 November 2026:** Color and vibrance Adjustment Brush, native/API/Actions 61 and modern PSD import distinction. Debug and both optimized architectures pass 46 selected tests, including all 12 new tests. Native save/reopen/Quit and universal static checks pass; universal candidate remains unlaunched. Photoshop output still differs at 44,797/37,102 samples. Full B08/A04 and earlier acceptance remain open. **Next: Q03, major stillneeded**; audit existing responsiveness work first. [Validation](SOURCE_PUBLICATION_520.md).

**Checkpoint 519:** Large Sky working-resolution edits, clipped/tiled previews and native/API navigation. Current focused Debug 15/all 9 new and optimized 63/all 34 new each architecture pass. Native Sky workflow remains unverified; universal static checks pass, unlaunched. Full AI09 and all prior failures remain open. Next B08, major stillneeded. [Qualification](SOURCE_PUBLICATION_519.md).

**Checkpoint 518:** Multi-key selection/clipboard/group editing passes all 46 selected and 12 new tests in Debug and both optimized architectures. Native group controls/history/save/reopen and universal static checks pass. Full SP01, earlier failures and Photoshop parity remain open. Next AI09, major stillneeded. [Qualification](SOURCE_PUBLICATION_518.md).

**Checkpoint 517:** Persistent generated-image variations:54/54 selected,9/9 new methods pass in Debug and both optimized configurations. Native selection/delete/history/save/reopen and universal static checks pass. Synthetic fixtures only; full AI07, earlier failures and Photoshop parity remain open. Next SP01, major stillneeded. [Qualification](SOURCE_PUBLICATION_517.md).

**Checkpoint 516:** Editable PSD/PSB artboards pass all 11 new methods in each configuration. Debug/optimized ARM pass 74/74 selected; Intel passes 73/74 with an older paging failure reproduced on retained515. Exact owned merged samples, native/Photoshop reopen and universal static checks pass. Full I04/L07 and prior failures remain open. Next AI07, major stillneeded. [Qualification](SOURCE_PUBLICATION_516.md).

**Checkpoint 515:** Editable source artboards and cache-preserving canvas fitting/export pass all 46 selected checks in Debug and both optimized architectures, including all 10 new methods. Native Save As/reopen and universal static checks pass. Full I03, earlier failures and Photoshop parity remain open. Continue I04, then AI07, major-stillneeded. [Qualification](SOURCE_PUBLICATION_515.md).

**Checkpoint 514:** The selected editable Auto-Blend path is tested. Continue major-stillneeded with I03 after auditing existing workflows. Full RAW02, original scope and failures remain required. [Plan](WORK_PRIORITIES_514.json) · [Qualification](SOURCE_PUBLICATION_514.md).

**Checkpoint 513:** COL03 legacy Macintosh/native/API/Apple RGB workflow implemented. All seven new tests pass in Debug, optimized ARM and translated Intel. The broader runs pass 54/55, 54/55 and 52/55, retaining reproduced public 512 failures; native UI and universal static checks pass. Full scope and all prior failures remain. [Qualification](SOURCE_PUBLICATION_513.md). Next RAW02 in the [major-stillneeded plan](WORK_PRIORITIES_513.json).

**Source checkpoint 512 — 9 November 2026 UTC:** Native Merge Channels and typed API merge/cancel now share assembly and atomic publication. All 15 new methods pass in Debug and both optimized architectures; broader runs pass 68/69 with the same 192 legacy assertions reproduced on public build 511. Actual RGB16/Multichannel16 save/reopen checks pass. Full COL02, metadata/default/output fidelity and earlier failures remain open. **Next: COL03, major-stillneeded.** [Validation](SOURCE_PUBLICATION_512.md).

**Source checkpoint 511 — 8 November 2026:** Gray32 PSD/PSB HDR metadata repair. All 32 selected methods pass in Debug and each optimized architecture; all eight container/compression variants open in Photoshop. A 24-word merged-preview numerical gap and all earlier failures remain. Merge Channels is still in progress under COL02, then COL03; no scope is closed. [Validation](SOURCE_PUBLICATION_511.md).

**Source checkpoint 510:** The selected COL01 path now keeps RGB gradients and vector paints editable during profile conversion. Full COL01 remains open: working-gray semantics, rich type and other layers, ACE, device-link/dither/CSF/policies, profile catalogue and exact defaults/output. Retain the frozen Intel profile failure and reviewed-plan Float32 differences. Current tests pass 106/106 in Debug and optimized ARM, 105/106 on Intel; the single frozen case reproduces byte for byte on public 506. Continue the original major-stillneeded sweep after auditing actual source. AUT03 plugin-runtime redesign and full AUD02 remain major work. No original scope or acceptance gate is removed. Canonical evidence and standalone website promotion remain pending.

**Source checkpoint 506:** The selected local super-resolution path is implemented and qualified as described in SOURCE_PUBLICATION_506.md. Full AI06 remains open, including Harmonize, other Neural Filters, provider/default/output fidelity and broader platforms/performance. Next is AI08 in the original major-stillneeded queue, then AUD02. Audit the existing five-operation native edit planner, reviewed preview/history and provider readiness before adding functionality. Adobe Assistant and AI Assisted Editor are distinct workflows; do not relabel the limited planner or an interface as their full implementation. Preserve every original package, acceptance target and seven-pass ordering. Canonical evidence/source and standalone website promotion remain pending.

**Source checkpoint 505:** Continue major stillneeded with AI06: Harmonize, generative upscale and Neural Filters. Audit existing deterministic relighting and JPEG cleanup first. Do not label resizing or relighting as learned/generative parity. AI04/AI05 retain all original acceptance, including outpainting, multi-reference/style/composition/markup/selection/variants, actual model and live UI qualification. Preserve every original package and the seven-pass order. Canonical evidence and standalone website promotion remain pending.

**Source checkpoint 503:** Continue the major-stillneeded sweep with AI04 after the selected People-removal path. Audit existing 490/491 image/background/reference functionality first. No full major package is closed by 501–503. Preserve all original package acceptance and seven-pass ordering. Canonical historical-evidence processing remains pending; the current source and working diary are delivered separately.

**Checkpoint 486 — Classic RGB16 gradient boundaries:** Classic RGB16 Gradient Map now uses fused interpolation at linear boundaries. All 61 selected Debug checks pass. Optimized Apple Silicon passes 61/61 and translated Intel 60/61, including all three new methods on both. The remaining Intel Legacy vector170 failure also occurs on retained build485. All 2,359,872 independently read merged-reference bytes match across Debug, ARM and Intel. Native Reverse, Undo/Redo, 100% viewport, cleanup and universal package checks pass. Build486 is a validation candidate; build480 remains the latest fully qualified selected universal. Full A06, Smooth, the curved residual, RGB32 fills and earlier gaps remain open. **Current: AI01, then AI02.** [Guide](CLASSIC_RGB16_BOUNDARIES.md) · [Evidence](CLASSIC_RGB16_BOUNDARIES_486.json).

**Checkpoint 485 — Sampled Hue/Saturation colors:** Photoshop sampled Hue/Saturation swatches now survive PSD/PSB/AHU and native92, appear in native Properties and share API settings/history. All68selected Debug and optimized checks perarchitecture pass,14new. All6528hue2recordbytes across threevariants match fourownedPhotoshopreferences. Nativeimport/orange+grayswatches/boundedit/UndoRedo/cleanup pass. Build485is a validation candidate;480remains latest fully qualified selected universal. FullA02/on-canvassampling and allpriorgaps remain open. **Current: A06, then AI01.** [Guide](SAMPLED_HUE_RANGES.md) · [Evidence](SAMPLED_HUE_RANGES_485.json).

**Checkpoint 484 — Quick Mask:** Quick Mask now preserves explicit full selections, starts Selected Areas without an overlay when no selection exists, and uses Photoshop editing-gray conventions in PSD/PSB. All64focused Debug tests and82selected optimized tests perarchitecture pass,17new. Seven owned Photoshop fixtures and81earlier auxiliary fixtures are checked. Native UI checks are partial: Fill remains in a modal loop inaccessible to the current automation binding. Build484is a validation candidate;480remains latest fully qualified selected universal. FullS05andPhotoshopparity remain open. **Current: A02, then A06.** [Guide](QUICK_MASK_SEMANTICS.md) · [Evidence](QUICK_MASK_SEMANTICS_484.json).

**Checkpoint 483 — Script Events Manager:** Script Events Manager runs native Actions on New Document and Open Document, with persistent disabled-by-default registrations and separately permissioned API configuration. All58focused Debug and optimized checks perarchitecture pass,20new. Broader optimized checks pass128of129on each architecture; the old400vs422API failure also reproduces on480. Native NewDocument/automaticInvert/Undo/manager checks pass. Build483is a validation candidate; latest fully qualified selected universal remains480. FullAUT02andPhotoshopparity stay open. **Current: S05 channels, then A02.** [Guide](SCRIPT_EVENT_ACTIONS.md) · [Evidence](SCRIPT_EVENT_ACTIONS_483.json).

**Checkpoint 482 — Inventory reconciliation:** Menu inventory corrected from802to809 entries using unchanged-source481 ARM/Intel captures. Seven missing paths and88stale selector bindings reconciled; original801factory entries/102primary/8alternate keys retained. All37developer-tool tests pass,21new. Application build480; fullAUD01/Photoshop/workflow qualification remains open. **Current: AUT02 automation, then S05.** [Guide](INVENTORY_RECONCILIATION.md) · [Evidence](INVENTORY_RECONCILIATION_482.json).

**Checkpoint 481 — Archive validation:** Repeatable source-bound archive validation passes locally: 16 new tool tests, 104 editing checks on ARM and translated Intel, 34 archive checks, exact binary/dSYM UUIDs and extracted ZIP. Application build remains 480. Hosted CI, signed distribution, sandbox runtime and full REL01 remain open. **Current: AUD01 inventory reconciliation, then AUT02.** [Guide](ARCHIVE_VALIDATION.md) · [Evidence](ARCHIVE_VALIDATION_481.json).

**Checkpoint 480 — Independent Color Lookup references:** Independent Photoshop Color Lookup references and repaired editable PSD interchange. All 95 selected Debug and optimized tests per architecture pass, including 16 new methods; nine auxiliary regressions also pass. All 1,474,560 independent composite bytes match per path. Photoshop reopens and recomputes fresh RGB8/16/32 files, retaining all 688,128 reference bytes. Full Q04, defaults, Dither, corpus and physical-platform qualification remain open. **Current: REL01 archive, sandbox and release CI, then AUD01.** [Guide](INDEPENDENT_COLOR_LOOKUP.md) · [Evidence](INDEPENDENT_COLOR_LOOKUP_480.json).

**Checkpoint479 — Color Lookup responsiveness:** Layer Properties now prepares edits in the background, with progress/Cancel and source/history protection. All161selected Debug checks and the same161optimized methods on ARM/translatedIntel pass,12new correctness checks;120-edit optimized measurements are recorded separately. FullQ03/physical60fps/document capacity remain open. **Current: Q04 independent references, then REL01.** [Guide](LOOKUP_PROPERTY_RESPONSIVENESS.md) · [Evidence](LOOKUP_PROPERTY_RESPONSIVENESS_479.json).

**Checkpoint478 — Local Color Lookup painting:** Adjustment Brush now supports editable local LUT effects through the native picker/Properties, API, history and portable Actions 59. All 94 selected Debug/optimized checks perarchitecture pass,8 new. Full B08/default/output/live/platform remain open. **Current: Q03 responsiveness, then Q04 independent references.** [Guide](ADJUSTMENT_BRUSH_LOOKUP.md) · [Evidence](ADJUSTMENT_BRUSH_LOOKUP_478.json).

**Checkpoint477 — Sky preset groups:** Native Sky Replacement and the API can create, rename and remove groups, move skies and import multiple images atomically. All 51 selected Debug/optimized checks per architecture pass,9 new. Live UI, Photoshop defaults/output, large sky canvases and full AI09 remain open. **Current: B08, then Q03.** [Guide](SKY_PRESET_GROUPS.md) · [Evidence](SKY_PRESET_GROUPS_477.json).

**Checkpoint476 — Blank video layers:** The native Layer/Timeline menus and API can create transparent drawing footage with sparse frame storage. All 111 selected Debug and optimized checks per architecture pass, including 13 new. Native90 preserves sparse frames and conversion sources. Live controls, Photoshop defaults/output, physical platforms/performance and fullSP01 remain open. **Current: AI09, then B08.** [Guide](BLANK_VIDEO_LAYERS.md) · [Evidence](BLANK_VIDEO_LAYERS_476.json).

**Checkpoint475 — Generated images:** Source-bound image jobs now retain original files before placement and support offline recovery through Generated Results and the optional API. All 67 selected optimized checks pass on Apple Silicon and translated Intel, including 30 new. Universal validation package verified; live/provider/fullAI07 and earlier failures remain open. **Current: SP01, then AI09.** [Guide](AI_GENERATION_LIFECYCLE.md) · [Evidence](AI_GENERATION_LIFECYCLE_475.json).

**Checkpoint 474 — OpenEXR:** Native Open/Save/Copy and API file transfers support selected scanline HDR files with None/ZIPS/ZIP, Half/Float and transparency. All97 selected optimized tests pass on Apple Silicon and translated Intel, including14new. Seven exports retain6168 independently checked sample bytes per architecture;63488finite Half patterns match exact reference words. Universal macOS14/signature/payload/extracted ZIP verified,unlaunched. Debug batch crashes, live controls, widerEXR/fullI04/Photoshop defaults/output and earlier failures remain open. **Current: AI07, then SP01.** [Guide](OPENEXR.md) · [Evidence](OPENEXR_474.json).

**Checkpoint 473 — Embedded originals in source projects:** `.pcraft` imports can recover currently decodable originals referenced by PSD metadata IDs. Exact payloads, source identity, placement, filters and retained appearance stay editable through native/API workflows. All 11 new checks pass; 737,280 cache bytes match exactly. Of 41 planned checks, 39 pass; an older uncached-render comparison and a nested-source crash reproduced on472 remain open. Debug473 verified and unlaunched; optimized473/live/fullI03 remain pending. Fully qualified universal470 and validation candidate472 retained. **Current: I04, then AI07.** [Guide](PCRAFT_LINKED_ORIGINALS.md) · [Evidence](PCRAFT_LINKED_ORIGINALS_473.json).

**Checkpoint 472 — Large image stacks:** Statistics now prepares large and many-frame editable stacks with sparse/file-backed tiles. Native sources follow the document layer target; alignment and HTTP sharing limits remain separate. All 44 selected Debug tests pass, including 13 new tests; 99 captured programs retain all 152,064 sample bytes. The dialog uses a bounded preview after statistics. All 44 selected checks pass on Apple Silicon and translated Intel. The broader batch passes 92 tests on Apple Silicon and 90 on Intel. Two Intel soft-proof reference tests still fail; the old and paged proof paths agree on Intel. Universal build 472 is an unreleased validation candidate. The latest fully qualified universal build remains 470. Live controls, full RAW02, exact Photoshop output/defaults, dense capacity/platform/60fps and earlier failures remain open. **Current: I03, then I04.** [Guide](PAGED_IMAGE_STATISTICS.md) · [Evidence](PAGED_IMAGE_STATISTICS_472.json).

**Checkpoint 471 — Large soft proofs:** Proof Colors, Gamut Warning and Custom Proof Setup can prepare sparse/paged displays beyond the former 8 MP proof limit. Proofing precedes native viewport/API overview reduction; source pixels, history and normal exports stay unchanged. All 64 selected Debug tests pass, including 14 new tests. The 104 prior programs retain all 159,744 bytes, plus the 240-byte reduced preview. Debug package verified, unlaunched; optimized 471 and live/full Photoshop qualification remain open. Latest universal: 470. **Current: RAW02, then I03.** [Guide](LARGE_SOFT_PROOF.md) · [Evidence](LARGE_SOFT_PROOF_471.json).

**Checkpoint 470 — Split Channels:** The Channels panel can separate a flat source into editable grayscale documents, closing the source without saving after all outputs are registered. The API shares the same preparation and publication with cancellation, revision, permission and lease guards. All 74 selected Debug tests and the same 74 optimized tests on ARM and translated Intel pass, including 15 new tests; 416 component-word bytes match exactly. Verified universal 470 is unlaunched. Live UI, full COL02 and exact Photoshop Split output/defaults remain open. **Current: COL03, then RAW02.** [Guide](CHANNEL_SEPARATION.md) · [Evidence](CHANNEL_SEPARATION_470.json).

**Checkpoint 469 — Large channel filters:** Eight basic filters now use sparse/paged preparation for alpha, spot-density and Quick Mask channels. All 72 selected Debug methods, including 12 new methods, pass. The 288 earlier programs retain all 442,368 sample bytes; a real 8.39 MP Noise case and sparse maximum-size channel workflows pass. Live UI, optimized 469, full C02 and exact Photoshop filter output remain open. Latest universal:468. **Current: COL02, then COL03.** [Guide](CHANNEL_FILTER_CAPACITY.md) · [Evidence](CHANNEL_FILTER_CAPACITY_469.json).

**Checkpoint 468 — Mask filters:** Eight common filters now work on layer and Smart Filter masks through the existing native dialogs and shared API. Source color pixels, Smart Objects and mask properties are retained. All 97 selected Debug methods/15 new pass; the planned 98th Debug test also crashes on467. The same 98 optimized methods pass on ARM and translated Intel. The universal package is verified and unlaunched; live UI/full S06/exact Photoshop filter output remain open. **Current: C02, then COL02.** [Guide](MASK_FILTER_TARGETS.md) · [Evidence](MASK_FILTER_TARGETS_468.json).

**Checkpoint 467 — Smart Object refinement:** Select and Mask now keeps Smart Objects editable for selection/mask outputs and creates rendered raster copies for copy outputs. Actual Photoshop neutral references verify source/output identity. All 127 selected Debug methods, including 17 new methods, pass. Native import is verified; interactive refinement remains pending. The discovered PSD Anno import gap is repaired through opaque byte preservation. The embedded PSB’s missing-composite declaration is also handled. Normal 467/fullS04/exact Photoshop refinement remain open. **Current: S06, then C02.** [Guide](SMART_OBJECT_REFINEMENT.md) · [Evidence](SMART_OBJECT_REFINEMENT_467.json).

**Checkpoint 466 — Selection sources and Wand Subject:** Object/People preparation now honors current type, shape and fill sources; Magic Wand Options includes Select Subject using its own sampling setting. All 82 selected Debug methods and the same 83 optimized methods per architecture pass, including the 23 new methods from 465–466. Selected native on-device selection and Undo/Redo/Quit pass. Optimized universal packaging is verified and unlaunched. Full S03 and exact Photoshop behavior remain open. **Current: S04, then S06.** [Guide](SELECTION_SOURCE_POLICY.md) · [Evidence](SELECTION_SOURCE_POLICY_466.json).

**Checkpoint 465 — Magic Wand averages:** The Sample Size picker now offers Point Sample and six square averages through native selection and the shared API. All 11 new tests and 57 selected Debug methods pass; a separate literal mask comparison is exact. Normal 465, the full gesture matrix, exact Photoshop output and full S02 remain open. **Current: S03, then S04.** [Guide](MAGIC_WAND_SAMPLING.md) · [Evidence](MAGIC_WAND_SAMPLING_465.json).

**Checkpoint 464 — Smart Filter stack and mask transfer:** Whole stacks and shared masks can be moved or copied between Smart Objects through native drag and the shared API, with one Undo and portable Actions. All 15 new transfer tests pass. The optimized batch passes 87 methods on Apple Silicon and translated Intel, including the 49 new methods from checkpoints 462–464. One older Debug API crash remains reproducible. Live transfer gestures, exact Photoshop behavior and full L06 remain open. **Current: S02, then S03.** [Guide](SMART_FILTER_TRANSFER.md) · [Evidence](SMART_FILTER_TRANSFER_464.json).

**Checkpoint463 — Smart Object Convert to Layers:** Original editable layers can now be restored through the factory menu, context menu and shared API, with patterns/nested sources and one Undo. All15new methods pass. Of55selected methods,53pass; an old linked-preview byte failure and old API signal10 reproduce on retained462. Full L05, exact Photoshop/live/normal463 acceptance remain open. **Current: L06 Smart Filters, then S02.** [Guide](SMART_OBJECT_CONVERT_TO_LAYERS.md) · [Evidence](SMART_OBJECT_CONVERT_TO_LAYERS_463.json).

**Checkpoint 462 — Saved layer styles:** New Style and Window > Styles now save, organize and reapply native presets with embedded patterns, separate blending options, one Undo and portable Actions. All 76 focused Debug methods pass, including 18 new methods. Shared API, persistence/cancellation/revocation, resource replay and panel migration are tested. ASL, live native, normal 462, exact Photoshop and full L04 remain open. **Current: L05, then L06.** [Guide](LAYER_STYLE_PRESETS.md) · [Evidence](LAYER_STYLE_PRESETS_462.json).

**Checkpoint 461 — Channel blending:** Blending Options now has Red, Green and Blue checkboxes, backed by the same native/API model, Undo, style copy/paste, native format 89, Actions 56 and PSD/PSB channel records. All 58 focused Debug tests and the same 58 optimized methods per architecture pass, including 17 new methods. Channel-only changes retain sparse storage and bounded pixel updates. Live native acceptance and independent Photoshop exclusion output remain pending; full L03 remains open. **Current: L04, then L05.** [Guide](CHANNEL_BLENDING.md) · [Evidence](CHANNEL_BLENDING_461.json).

**Checkpoint 460 — Mask and channel clipboard:** Copy, Cut, Paste and Paste In Place now work on alpha channels, Quick Mask, layer masks and Smart Filter masks through one native/API transaction. All 45 focused Debug and the same 45 optimized tests per architecture pass, including 20 new methods. Selected numeric buffers match the independent literal reference exactly. Sparse 300,000 × 300,000 transfer, Undo/Redo and cancellation/stale safeguards pass. Universal macOS 14/signature/ZIP checks pass. Live native acceptance, full D04 and Photoshop output/default fidelity remain open. **Current: L03, then L04.** [Guide](TARGETED_CLIPBOARD.md) · [Evidence](TARGETED_CLIPBOARD_460.json).

**Checkpoint459 — Eyedropper sampling:** Seven sample sizes, five layer sources, drag feedback, captured Option-background sampling, ring controls and shared persistent settings now use one native/API engine. All45focused Debug and the same45optimized methods per architecture pass, including19new. Selected strict sample comparison is exact across Debug/ARM/translatedIntel. Universal macOS14/signature/ZIP checks pass. Live native checks remain pending the disconnected automation service; full B07, Color Sampler points, tablet input, exact Photoshop output/defaults and earlier failures remain open. **Current: D04, then L03.** [Guide](EYEDROPPER_SAMPLING.md) · [Evidence](EYEDROPPER_SAMPLING_459.json).

**Checkpoint 458 — Content-Aware Fill Apply:** Apply now commits a fill while keeping the workspace open. New/Add/Subtract/Intersect selections, captured cursor modes and the shared API support continued filling. Cancel retains applied work; unchanged OK avoids duplicate output/history. All 38 focused Debug tests pass, including seven new methods. Normal458 is deferred; latest universal457 retains its strict gaps. Native Open/selection/menu checks passed, then automation disconnected before Apply could be observed. The disposable validation app remains open, and live acceptance is pending. Full B06, multi-image sampling, capacity, exact output/defaults, platform and 60 fps requirements remain open. **Current: B07, then D04.** [Guide](CONTENT_AWARE_APPLY.md) · [Evidence](CONTENT_AWARE_APPLY_458.json).

**Checkpoint 457 — Blur, Sharpen and Smudge modes:** The three tools now offer Normal, Darken, Lighten, Hue, Saturation, Color and Luminosity through native controls and the shared API, with captured settings, Undo/Redo and portable Actions. All 57 focused Debug tests pass. Optimized builds pass 57 on Apple Silicon and 56 of the same 57 on translated Intel, including all ten new methods on each. The Intel case reproduces the same 234 assertions on preserved456. All 18 preserved Normal buffers match exactly. Of 126 mode buffers, 120 match across Debug and both optimized architectures; six Float32 buffers differ in 16 Intel color values by 1–4 ULP, with all alpha values exact. Debug and optimized Apple Silicon match all 126. No tolerance was substituted. Selected native workflows and universal macOS 14/signature/ZIP checks pass. Exact Photoshop output, full B04, physical 60 fps and earlier failures remain open. **Current: B06 Content-Aware Fill and Scale, then B07.** [Guide](FOCUS_BLEND_MODES.md) · [Evidence](FOCUS_BLEND_MODES_457.json).

**Checkpoint 456 — Eraser modes:** Ordinary Eraser now has Brush, Pencil and Block, with native controls, captured settings/cursors and shared API execution through the existing stroke/history engines. All44focused Debug and the same44optimized tests per architecture pass, including ten new methods. Six owned Photoshop Block RGB8 references match byte-for-byte on Debug, Apple Silicon and translated Intel. Optimized native Open/Block/Undo/Redo/Close/Quit and universal macOS14/signature/extracted ZIP pass. The Debug native Open/Quit failure is retained; its clean test process required force quit, with no cause or repair claimed. Full B02 and earlier exact-output/platform/performance gates remain open. **Current: B04 focus blend modes, then B06.** [Guide](ERASER_MODES.md) · [Evidence](ERASER_MODES_456.json).

**Checkpoint 455 — Eraser reference:** Independent Photoshop PSD references measure Block footprints at100%,125%,200%,1600% and two6400%positions. The results reject a forced minimum1px at high zoom. Eraser Brush/Pencil/Block modes remain to be implemented. **Current: B02, then B04; no queue rotation.** Software remains454 and optimized universal453. [Evidence](ERASER_MODES_455.json) · [Integration plan](ERASER_MODES.md).

**Checkpoint 454 — Brush pattern textures:** Brush Settings can choose saved patterns from the shared library, with embedded samples retained by presets, supported ABR, captured strokes and Actions. The existing brush.configure API resolves the same pattern IDs atomically. All40focused Debug tests pass, including10new; actual native picker/preview/painting/UndoRedo/Quit pass. Normal optimized universal remains453. Full B01, Photoshop output fidelity and earlier failures stay open. **Current: B02 Painting tools, then B04.** [Guide](BRUSH_PATTERN_TEXTURES.md) · [Evidence](BRUSH_PATTERN_TEXTURES_454.json).

**Checkpoint 453 — Custom Filter Gallery textures:** Rough Pastels, Underpainting, Glass, Conté Crayon and Texturizer can load PSD/PSB height textures. Embedded samples survive Smart Filter editing, native files, Actions and shared API replay. All34focused Debug and the same34optimized methods per architecture pass, including16new tests;10of15selected rawbuffers match exactly;55oneULPFloat32color differences remain. Native Load/local and document history/Save/fresh reopen and universal macOS14/signature/ZIP checks pass. Full F06 and Photoshop numerical/default equivalence remain open. **Current: B01 Brush Settings, then B02.** [Guide](GALLERY_TEXTURES.md) · [Evidence](GALLERY_TEXTURES_453.json).

**Checkpoint 452 — Camera and lens defaults:** Lens Correction saves exact camera/lens/focal-length/aperture defaults and restores them in new drafts. Settings supports Lens Default, Previous Conversion and Default Correction with local history; native/API preference changes retain document pixels/history. A real executable startup defect is fixed for both filter libraries. All 33 focused Debug and the same 33 optimized tests per architecture pass, including 13 new methods and 11 last-mesh regressions. Native restart, Cancel/Undo and universal macOS14/signature/extracted ZIP checks pass. Full F05, Photoshop policy/output and earlier failures remain open. **Current: F06 Filter Gallery, then B01.** [Guide](LENS_DEFAULTS.md) · [Evidence](LENS_DEFAULTS_452.json).

**Checkpoint 450 — Liquify last mesh:** Load Last Mesh now retains the last committed Liquify program independently of other filters, saves it across launches, and supports native local/document history and existing API replay. All33focused Debug methods pass, including11new tests. Core/Imaging math, old fixtures/tests and native87/Actions53/258commands are unchanged. An isolated arm64Debug app verifies signature/min14metadata/entitlements; ready-state live UI and current Photoshop comparison await the existing unlock request. Normal optimized/universal remains448; full F04 and earlier failures stay open. **Next: F05,thenF06.** [Guide](LIQUIFY_LAST_MESH.md) · [Evidence](LIQUIFY_LAST_MESH_450.json).

**Checkpoint 449 — Source and draft build backup:** [Qualified build448 source](https://github.com/ForensicIntelligence/Photato/commit/77b14d5eedf88f5b70dab96b9d8140d1fbc121c3) is on public GitHub. The universal0.3.0/build448 archive and three provenance/checksum files are in an [unpublished draft](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-6240e52f419a928915de); all four downloaded hashes and the extracted app signature/content verify. Ad-hoc signed, not notarized; no production launch, App Store change or software release. All7,349included frozen inputs/34exclusions/1,057originalRustfiles retain their hashes. Credential scans found no exposed real credentials; GitHub scanning/push protection stay enabled,0alerts at recheck. Earlier numerical/full-suite failures and all104package scopes remain open. **Current: F04 Liquify, then F05.** [Receipt](SOURCE_PUBLICATION_449.json).

**Checkpoint 448 — Blur Gallery mask output:** Save Mask to Channels, shared preview/API, atomic history and portable Actions53 are implemented. All31 focused Debug and57 sameordered optimized methods per architecture pass, including all24 new methods across447–448. Universal macOS14 metadata/signature/ZIP and actual native output/Cancel/Undo/Redo/Quit pass. Owned Photoshop references verify uniform Field5 mask bytes and Blur Mask2 naming. Full F03, other spatial/default/output/capacity/platform gates and earlier failures remain open. **Current: F04, then F05**, with the standing authorized source/build backup of448 first. No source push or software release occurred in this checkpoint; public implementation remains443. [Guide](BLUR_GALLERY_MASK.md) · [Evidence](BLUR_GALLERY_MASK_448.json).

**Checkpoint 447 — Custom Filter presets:** Native Load/Save now supports Photoshop ACF and retained JSON, with lossless fractional settings, explicit format selection and shared `filter.custom.preset` API conversion. All 36 selected ARM64 Debug tests pass, including 13 new tests. Actual sandboxed ACF/JSON Save, local/document history and Quit pass; Photoshop loads and re-saves our export byte-identically. Normal optimized/universal qualification remains 446. Full F02 and all earlier exact-output failures remain open. **Current: F03 Blur Gallery, then F04.** The unchanged public repository still passes its credential recheck; no source or software release uploaded. [Guide](CUSTOM_KERNEL_PRESETS.md) · [Evidence](CUSTOM_KERNEL_PRESETS_447.json) · [Credential audit](SECRET_AUDIT.md).

**Checkpoint 446 — Custom Shape Blur:** Native saved-shape snapshots, chooser, preview/local history, Smart re-edit, portable Actions and shared API are implemented. The same 57 optimized methods run on both architectures: 55 pass, with two exact Photoshop comparisons still failing; 9 of 11 new methods pass. Universal macOS 14/signature/ZIP and selected live native checks pass. Full F01 remains open. **Next: F02 ACF preset interchange, then F03**, within major stillneeded. Public source remains 443; no source or software release was uploaded. [Guide](CUSTOM_SHAPE_BLUR.md) · [Evidence](CUSTOM_SHAPE_BLUR_446.json).

**Checkpoint 445 — Credential audit:** No exposed real credentials found in the public repository’s 69 commits and 10,680 historical file versions. All scanner candidates were reviewed; intentional test credentials remain in fixtures. GitHub secret scanning and push protection are now enabled. App source is unchanged. F01’s custom Shape Blur remains in development with its independent pixel comparison still failing; F02 follows the qualified selected workflow. [Audit](SECRET_AUDIT.md) · [Evidence](SECRET_AUDIT_445.json).

**Checkpoint 444 — Public source; filter development:** [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato) is now public at the maintainer’s request; no software release was published. Custom Shape Blur is in development:42of43selected Debug methods pass, with an independent convolution mismatch still open. **F01 stays current; F02 follows.** Latest qualified optimized universal selected workflow remains443. [Visibility](REPOSITORY_VISIBILITY_444.json) · [Development evidence](CUSTOM_SHAPE_BLUR_444.json).

**Checkpoint 443 — Pattern groups:** The native Patterns panel now organizes groups and presets, with multi-selection, moving/reordering, duplication, rename/delete and PAT transport that retains folders. The shared API covers the same library operations and Define Pattern. All 54 focused Debug and the same 71 optimized tests per architecture pass, including seventeen new methods. Universal macOS 14 packaging/signature/ZIP verify. Failed attempts, earlier wider-suite failures and full A07 remain open. **Next: F01, then F02**, within major stillneeded. [Guide](PATTERN_LIBRARY.md) · [Evidence](PATTERN_LIBRARY_443.json). [Private source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/0f4c25b920f135ebb2fc637965e5b0a08fea73b8); no software release.

**Checkpoint 442 — Gradient creation:** Options and toolbar presets now configure future gradients; existing fills use canvas/Properties editing. Shared APIs create live fills, configure defaults and paint Classic gradients; portable Actions record creation and painting. All 69 focused Debug tests pass. Optimized tests pass 99/99 on Apple Silicon and 98/99 under Rosetta, including all eleven new tests on both. The remaining Intel numerical failure reproduces in checkpoint 441. Universal macOS 14 packaging/signature/ZIP verify. Full A05 and prior failures remain open. **Next: A07, then F01**, within major stillneeded. [Guide](GRADIENT_CREATION.md) · [Evidence](GRADIENT_CREATION_442.json). [Private source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/4f7c736d74f1bf276e1fc5674dee2b2ec4f53c7e); no software release.

**Checkpoint437 — Typography development:** Separate Character/Paragraph docked/floating panels, four existing factory menu commands, retained text selections and shared `workspace.panels` API are added. **94of95focused tests pass; a desired point-text alignment/commit test still fails. This is not a qualified stable increment.** T01remains current; correct point-text layout/editor next, thenT04. All original major scope remains open; no minor/cleanup pass. Latest optimized universal/private source436. [Guide](TYPOGRAPHY_PANELS.md) · [Evidence](TYPOGRAPHY_PANELS_437.json).

**Checkpoint436 — Fill Path options:** Native contents/pattern/mode/opacity/preserve/feather/anti-alias controls and optional `path.paint.fill` share the existing paint engine, captured guards, one Undo and portable Actions50. All60focused Debug and354selected optimized cases per architecture pass, including89new426–436methods. Universal macOS14/signature/ZIP checks pass. FullG04/History/capacity/defaults/physical/fullsuite/Photoshop remain open. **Next: T01 typography, thenT04**, within major stillneeded. [Guide](PATH_FILL.md) · [Evidence](PATH_FILL_436.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/76527a7b791685b21fc9248ef6e50cfdb8c21a05) verified; no install/archive/Store/release.

**Checkpoint435 — Precise shape creation:** Clicking Rectangle/Ellipse without dragging now opens dimensions, From Center and rectangle corner controls. Native/API placement shares existing rendering, source guards and one Undo. All30focused Debug tests pass, including eight new methods, the full cursor matrix and imported shape-path editing. New native/API pixel-mode stack faults were preserved and repaired without removing validation or weakening tests. **Next: G04 Pen/Paths, then T01**, within major stillneeded. Full G03 and original acceptance remain open; latest optimized/universal/private-source batch432. [Guide](PRECISE_SHAPE_CREATION.md) · [Evidence](PRECISE_SHAPE_CREATION_435.json).

**Checkpoint434 — Batch file naming:** The native Batch panel now supports ordered name, text, serial, letter, extension and date fields, with the same optional API planner. All25focused Debug tests pass, including eight new methods. Duplicate plans reject before processing; file protection, cancellation and source snapshots are retained. The first panel-height failure was preserved and repaired without changing its test. **Next: G03 live shapes, then G04**, within major stillneeded. Full AUT01 and all original acceptance remain open; latest optimized/universal/private-source batch432. [Guide](BATCH_FILE_NAMING.md) · [Evidence](BATCH_FILE_NAMING_434.json).

**Checkpoint433 — Channels Save/Load:** Footer Save now creates an automatically named alpha; Option-click retains its options dialog. Load uses the selected channel/component/temporary mask directly. Native/API source schemas now include Smart Filter masks, with raw geometry/coverage and prepared history guards. All58focused Debug tests pass, including eight new methods and maximum sparse/all-depth save and source tests. **Next: AUT01 Actions/Batch**, thenG03, within major stillneeded. FullC01/Photoshop/physical/full-suite gates remain open; latest optimized/universal/private-source batch432. [Guide](CHANNEL_FOOTER.md) · [Evidence](CHANNEL_FOOTER_433.json).

**Checkpoint432 — Pattern Patch:** Normal Patch now has a saved-pattern picker and Use Pattern, with shared native/API preparation, cancellation and one Undo. Small repairs work on the maximum sparse canvas without whole-document arrays. All40focused Debug and199selected optimized tests per architecture pass, including55new426–432methods. Universal macOS14/signature/ZIP checks pass. Full B05,4MPsolve/output expansion, other retouch capacity, exact Photoshop and physical/full-suite qualification remain open. **Next: C01 Channels workflows**, thenAUT01, within major stillneeded. [Guide](PATTERN_PATCH.md) · [Evidence](PATTERN_PATCH_432.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/315a12121fd1fc8f323a242316d1a60ef21ade67) · [Receipt](SOURCE_PUBLICATION_432.json).

**Checkpoint431 — Color Lookup formats:** Native RGB export now offers CUBE, 3DL, CSP and device-link ICC, metadata and multiple named files. The optional API shares single/ZIP preparation and cancellation/source guards. All34 focused Debug tests pass, including eight new methods; independent OCIO/LittleCMS/ColorSync checks pass on owned transforms. Full256 grids, LAB/CMYK, live save-panel validation, exact Photoshop output and fullI05 remain open. **Next: B05 painting workflows**, thenC01, within major stillneeded. Latest optimized/universal/private-source batch430. [Guide](COLOR_LOOKUP_FORMATS.md) · [Evidence](COLOR_LOOKUP_FORMATS_431.json).

**Checkpoint 430 — Large-document Equalize:** Equalize now uses paged histograms and editing at the native 300,000-pixel/90-gigapixel limit. Maximum implicit rasters and sparse selections, native/API/Actions/Undo and bounded overview paths are tested. All 30 focused Debug and 127 selected optimized cases per architecture pass, including 38 new methods from 426–430. Universal macOS14/signature/ZIP checks pass. Dense maximum performance, full-resolution dialog viewport, Photoshop pixels and full-suite/physical checks remain open. **Next: I05 color lookup/export.** Brightness/Contrast and the other unfinished A03 functions stay major stillneeded. [Guide](LARGE_EQUALIZE.md) · [Evidence](LARGE_EQUALIZE_430.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/8400eb8e3bddc8bbbfeb9bd8e9e4e644d29daa39) · [Receipt](SOURCE_PUBLICATION_430.json).

**Checkpoint 429 — Transform reference point:** Transform Options now expose Show Reference Point and a shared nine-position locator. Drag the pivot inside or outside the bounds; rotation and scaling use it. Reference-only changes retain pixels, previews and Undo. Native controls and `transform.reference` share validation and a separate workspace revision. All 130 focused Debug tests pass, including seven new methods. Optimized universal/full-suite/physical qualification remains open; the latest optimized/private-source batch is 428. **Next: A03 classic adjustments.** Transform Again and remaining G01 functions stay major stillneeded. [Guide](TRANSFORM_REFERENCE.md) · [Evidence](TRANSFORM_REFERENCE_429.json).

**Checkpoint 428 — Animated selections:** Committed selections and marquee/transform previews now use native Core Animation borders. Existing contours, source pixels, history and output bytes are retained. Lifecycle gates pause hidden/inactive/occluded/detached windows and respect Reduce Motion. All 98 selected optimized cases pass per architecture, including 23 new methods from checkpoints 426–428; universal macOS 14, signature and ZIP checks pass. The older Frame case passes optimized but its Debug crash remains open. **Next: G01 geometry workflows.** Grow/Similar and the rest of S01 remain major stillneeded. Full-suite, physical performance and Photoshop parity remain open. [Guide](SELECTION_BORDERS.md) · [Evidence](SELECTION_BORDERS_428.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/dd9f86229b43d0989a6fa8dfd7e48fd19cb75087) · [Receipt](SOURCE_PUBLICATION_428.json).

**Checkpoint 427 — Adjacent artboards:** The Artboard tool now has four + controls. Click to add an empty neighbouring board; Option-click copies its contents. Native controls and `artboard.edit` share placement, source guards and one prepared Undo. All 41 focused Debug tests pass, including8new methods. The broader run crashed in an existing Frame case that also crashes in retained 426 Debug; it remains open and is excluded from the narrower pass. Current427normal/universal/physical qualification is unclaimed. **Next: S01 basic selection workflows.** The remaining L07/L01/D01 functions stay major stillneeded. [Guide](ARTBOARD_NEIGHBORS.md) · [Evidence](ARTBOARD_NEIGHBORS_427.json).

**Checkpoint 426 — Save dialog formats:** Edit > Customize Save Dialog File Formats now has a native persistent draft shared with the File Handling API. Save As and Save a Copy show selected supported formats; ordinary Save, recovery and explicit API outputs retain their contracts and bytes. Settings archive 4 migrates older settings without rewriting on read. All 101 focused tests and the same 101 optimized tests pass per architecture, including seven new methods. Universal macOS 14, signature and ZIP checks pass. **Next: L07 artboard workflows.** Remaining D01 functions stay major stillneeded. Exact Photoshop defaults/empty-state behavior, physical UI and full format coverage remain open. [Guide](SAVE_DIALOG_FORMATS.md) · [Evidence](SAVE_DIALOG_FORMATS_426.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/4156da9b1791d9a15b85c0ede5d9c5115d4ebf99) · [Receipt](SOURCE_PUBLICATION_426.json).

**Checkpoint 425 — Layer selection:** Select > Deselect Layers, Command-clicking the last selected row, and plain click below the layer rows now clear selection through one native/API path. Selection-only portable Actions 49 add no pixel Undo and recording can stop with no active layer. All 127 focused Debug tests pass. Both optimized architectures pass 393 of the same 395 cases, including all 66 new feature methods; two failures with the same diagnostics as checkpoint 424 remain. Universal macOS14/signature/ZIP checks pass; current physical UI remains pending unlock. **Next: D01 document workflows.** The larger L01 gaps stay major stillneeded for a later sweep. All 104 package records retain their original scope and acceptance criteria. [Guide](LAYER_SELECTION.md) · [Evidence](LAYER_SELECTION_425.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/04a6f66b059366992ca6318a9113fdab73ecf4fb) · [Receipt](SOURCE_PUBLICATION_425.json).

**Checkpoint 424 — Layer content filters:** Empty and Not Empty now scan stored alpha in a cancellable worker shared by native controls and the API. Filtering clears an excluded active layer, matching the owned Photoshop reference. All 91 focused tests pass. Both optimized architectures pass 358 of the same 360 cases, including all 57 newer feature tests; the two remaining errors exactly match build 422. The universal package and actual native filter/paint/Undo/selection/Quit checks pass. Full L01, earlier failures and all 104 package scopes remain open. Major stillneeded work continues before minor or cleanup. [Guide](LAYER_FILTER.md) · [Evidence](LAYER_CONTENT_FILTER_424.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/ce9c535ef80b8ccfb8b8f6ce4bcc82bf8276bb41) · [Receipt](SOURCE_PUBLICATION_424.json).

**Checkpoint 423 — Layer filtering and isolation:** The Layers panel now shares document-local filter state with the API. Nine modes, multiple kind/Smart Object icons, Find Layers, Isolate Layers and filtered selection are implemented; specific adjustments and fill layers now match correctly. All 77 current focused tests pass, including all 13 new regressions and lowercase artboard UUIDs. The earlier 85-test run retains two capacity errors that reproduce in 422 Debug and pass its optimized builds. **Next: asynchronous Empty/NotEmpty and remaining substantive L01 work, before D01 or minor/cleanup.** Full filtering, current optimized/physical Photoshop qualification and all 104 package scopes remain open. [Guide](LAYER_FILTER.md) · [Evidence](LAYER_FILTER_423.json).

**Checkpoint 422 — Arrange selected layers:** All five Layer > Arrange commands now move or reverse selected layers and complete groups through one prepared Undo. Native menus/default shortcuts, Photato API, portable Actions 48 and the supported Adobe MoveLayer job subset share the engine. All 106 focused Debug tests pass; both optimized architectures pass 279 of 281 tests, including all 33 new methods from checkpoints 415–422. Existing failures remain recorded; universal macOS14/signature/ZIP checks pass. **Current: major stillneeded L01, next layer filtering/isolation; D01 follows the remaining substantive L01 work.** All 104 package scopes and physical Photoshop qualification remain open. [Guide](LAYER_STACK_ORDER.md) · [Evidence](LAYER_STACK_ORDER_422.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/9c9723749d107c98cdbe9871879115edc6dcfdfb) · [Receipt](SOURCE_PUBLICATION_422.json).

**Checkpoint 421 — Channel thumbnail options:** Plain double-click now opens existing alpha, spot or Quick Mask Options through a captured native thumbnail control; context Options shares its guards. Existing modifier selection/load behavior, channel planes and layer pixels are retained. All56focused Debug tests pass, including3new regressions;50existing normal baseline tests pass per architecture. Current421normal and physical/full Photoshop acceptance remain open. **The major quick-win sweep is finished. Next: major stillneeded L01 layer workflows, then D01 document workflows.** All104full package scopes remain open. [Guide](CHANNEL_THUMBNAIL_OPTIONS.md) · [Evidence](CHANNEL_THUMBNAIL_OPTIONS_421.json).

**Checkpoint 420 — Rasterization responsiveness:** Native Rasterize now prepares the existing command in a background worker and commits one Undo after source validation. The optimized 24MP sample returns from the main-actor call in 0.023ms on Apple Silicon while preparation takes about 6.94s. Native/API/old-command documents and saved bytes match across RGB8/16/32. Both architectures pass 193 of 195 tests, including all 18 new methods from 415–420; two exact old failures remain open. Universal macOS14/signature/ZIP checks pass. Physical60fps, full Q03 and Photoshop acceptance remain open. **Next: Q04 independent references, then REL01 archive/sandbox.** Six major quick-win candidates remain. [Guide](RASTERIZATION_RESPONSIVENESS.md) · [Evidence](RASTERIZATION_RESPONSIVENESS_420.json).

**Checkpoint 419 — Rename sky presets:** Sky Replacement now offers a native Rename dialog using the existing library/API operation. It preserves IDs, order and image bytes, refreshes preview names, and adds no document history. Cancel, stale context, validation and failed storage retain the library. API state and capability metadata describe native availability. All 57 focused Debug tests pass, including three new methods; 26 existing normal baseline tests pass per architecture on preserved 417. Normal 419 and physical Photoshop/UI acceptance remain open. **Next: Q03 measured responsiveness, then Q04 independent references.** Seven major quick-win candidates remain; full package scopes are unchanged. [Guide](SKY_PRESET_RENAME.md) · [Evidence](SKY_PRESET_RENAME_419.json).

**Checkpoint 418 — Frame Timeline dragging:** Animation thumbnails now drag before or after another frame through the existing reorder command, with insertion feedback and one Undo. Frame IDs, timing, content and selected-frame appearance are retained. Existing animation.view/animation.edit API paths match native documents, saved bytes and history across RGB8/16/32; capability metadata describes dragging. All 50 focused Debug tests pass, including three new methods. The import/encoding/frame baseline passes 49 existing normal tests per architecture on preserved 417. Normal 418 and physical Photoshop/UI acceptance remain open. **Next: AI09 sky-library audit, then B08 Adjustment Brush.** Nine major quick-win candidates remain; full package scopes are unchanged. [Guide](ANIMATION_FRAME_DRAG.md) · [Evidence](ANIMATION_FRAME_DRAG_418.json).

**Checkpoint 417 — Statistical image stacks:** Five existing operators now follow Adobe’s published sample-moment and entropy definitions through the shared native engine, Photato API and supported Adobe action jobs. All 41 focused Debug tests pass. Normal builds pass 157 of 159 tests per architecture, including all eight new tests from 415–417 and 70 independently calculated Float32 results. Two exact pre-existing failures remain open. The universal package passes macOS 14, signature and ZIP checks; physical UI and complete Photoshop output qualification remain open. **Next: I03 migration audit, then I04 export/interchange.** There are 13 major quick-win candidates left; all original package scopes remain. [Guide](STACK_STATISTICS.md) · [Evidence](STACK_STATISTICS_417.json).

**Checkpoint 416 — Selected-mask removal:** Layers trash now removes the selected pixel, vector or Smart Filter mask and retains its layer, including the final layer. Native/API operations share prepared history and exact native bytes. New `mask.manage` brings 246 typed operations; native format 86 and Actions 47 remain unchanged. All 102 focused Debug tests pass, including three new methods; 59 existing normal baseline cases pass per architecture. Normal 416, physical UI and full Photoshop acceptance remain open. Latest normal/private source stays 414 with its linked-alpha residual. **Next: COL02 color modes, then COL03 proofing/print.** There are 16 major quick-win candidates left. [Guide](MASK_REMOVAL.md) · [Evidence](MASK_REMOVAL_416.json).

**Checkpoint 415 — Select Subject options:** Object Selection and Quick Selection now offer Select Subject in the Options bar, capturing the visible Sample All Layers setting. Native/API documents, saved bytes and one-step Undo/Redo match; source pixels and Properties/Menu sampling stay unchanged. All81focused Debug tests pass, including one new regression.60existing normal baseline tests pass per architecture. Normal415/live/full Photoshop qualification remains open; latest normal/private source stays414. **Next: S04 Select and Mask, then S06.**19major quick-win candidates remain. [Guide](SUBJECT_OPTIONS.md) · [Evidence](SUBJECT_OPTIONS_415.json).

**Checkpoint 414 — Smart Filter dragging:** Plain drag reorders within a stack; Option-drop copies a complete filter to another/same Smart Object in the document. Existing source bytes and target masks are preserved with one Undo and shared API. All53focused Debug cases pass. Normal builds pass99/100cases each, including all4new413–414methods; the remaining linked-PSD/PSB alpha mismatch exactly matches the preserved baseline. Universal macOS14/signature/ZIP checks pass; physical/full Photoshop/current-suite acceptance remains open. **Next: S02 Color Range audit, then S03.**21major quick-win candidates remain. [Guide](SMART_FILTER_DRAG.md) · [Evidence](SMART_FILTER_DRAG_414.json).

**Checkpoint 413 — Brush Settings sidebar controls:** Eleven groups now have direct enable checkboxes, independent of preset locks, using the existing brush settings and API. All 62 focused Debug cases pass, including the new native/API regression. Selected Pencil, Clone Source and Content-Aware controls already work; 50 existing normal cases pass per architecture on unchanged412. Full B01/Photoshop/live/normal413 qualification remains open; latest normal/private source stays412. **Next: D04 clipboard interoperability audit, then L03.** There are26major quick-win candidates left. [Guide](BRUSH_SECTION_CONTROLS.md) · [Evidence](BRUSH_SECTION_CONTROLS_413.json).

**Checkpoint 412 — Filter Gallery dragging:** Effect rows now drag to reorder through the same native move/Undo operation as the arrows. All 53 focused Debug tests pass. Normal builds pass 116 main tests plus two separate API metadata tests per architecture, including all 16 new Last Filter/Gallery cases. Universal macOS14/signature/ZIP checks pass. Physical native interaction, full F06/Photoshop/current-suite acceptance remain open. **Next: B01 brush settings audit, then B02.** There are 31 major quick-win candidates left in this sweep; this is not a parity estimate. [Guide](GALLERY_EFFECT_REORDER.md) · [Evidence](GALLERY_EFFECT_REORDER_412.json).

**Checkpoint 411 — Last Filter:** The native Filter menu now recalls successful filter settings through the captured Control-Command-F shortcut and shared `filter.repeat` API. All eight new and 42 focused Debug cases pass. A07 placement/location controls already exist and pass29selected normal cases per architecture on410. Normal optimized/universal411 and actual live UI remain open; latest qualified normal/private source stays410. An existing Adobe-job Debug signal10reproduces on410and411and passes410normal; it remains recorded. **Next: F02 ordinary filter audit, then F03 Blur Gallery.** [Guide](FILTER_RECALL.md) · [Evidence](FILTER_RECALL_411.json).

**Checkpoint 410 — Gradient Fill API and Actions:** Live Gradient Fill settings now have a strict shared `gradient.fill.patch` API and portable Actions recording/playback. All 74 focused Debug tests and 82 normal optimized tests per architecture pass, including eight new cases. The universal package passes macOS 14/signature/ZIP checks. Typed catalog244, native archive86, Actions47. Full A05 and live UI/Photoshop/current-suite qualification remain open. **Next: A07 Pattern fills and pixel fills/strokes, then F01.** Human unlock for live408/410checks is still pending. [Guide](GRADIENT_FILL_API.md) · [Evidence](GRADIENT_FILL_API_410.json).

**Checkpoint 409 — Quick-win audit:** Paths, existing typography controls and shaped-text parameters are already implemented. All 51 selected existing tests pass per architecture across three normal optimized groups. Curves Auto is confirmed missing and moves to stillneeded; separate Character/Paragraph panel menus remain open. Software is unchanged at 408 Source01. **Next: A04 current2026 adjustment layers, then A05.** The 408 live check still awaits human unlock. [Evidence](QUICKWIN_AUDIT_409.json).

**Checkpoint 408 — Shape stroke presets:** Solid, Dashed and Dotted native controls/shared API are implemented. All 156focused normal optimized cases pass per architecture, including24 new across406–408 and eight new preset cases. The universal package passes macOS 14/signature/ZIP checks. **Actual408 native control/history/Quit awaits Mac unlock**; no live pass claimed. Full G03/Photoshop/current-suite qualification remains open. **G04 is next, then T01.** [Guide](SHAPE_STROKE_PRESETS.md) · [Evidence](SHAPE_STROKE_PRESETS_408.json).

**Checkpoint 407 — Duplicate saved actions:** The native Actions panel menu and existing `actions.manage` API now make independent saved-action copies through the shared library transaction. All 34 focused Debug tests pass, including eight new cases. Actual sandbox duplication, saved IDs/payloads, playback/Undo and normal Quit pass; the existing shared library hash is unchanged. Full AUT01/Photoshop/normal universal qualification remains open. **G03 is next, then G04.** [Guide](ACTION_DUPLICATION.md) · [Evidence](ACTION_DUPLICATION_407.json).

**Checkpoint 406 — RGB8 component pairs:** Ordinary RGB8 channel rows and the existing API now select component pairs for the shared editing engine. All eight new focused Debug tests pass. The initial run is 103/104 with an existing maximum-CMYK timeout; a separate clipboard-test signal10 also reproduces on preserved405. These failures remain open. Native singleton shortcuts/Invert/Undo/Redo/Quit pass; physical Shift-click pairs and normal optimized qualification remain unverified. Full C01 remains open. **AUT01 is next, then G03.** [Guide](RGB8_COMPONENT_SELECTION.md) · [Evidence](C01_RGB8_SELECTION_406.json).

**Checkpoint 405 — Color Lookup export:** File > Export > Color Lookup Tables and the optional API now bake eligible global RGB adjustment stacks to CUBE without changing pixels or history. All 80 focused normal Release tests pass on each architecture, including 12 new cases. The final universal app saved the expected file and passed the clean Undo and Quit checks. Full I05 and Photoshop qualification remain open. G01 Transform Again and A03 Brightness/Contrast move to major stillneeded; B05 Red Eye controls already work. **C01 is next, then AUT01.** [Guide](COLOR_LOOKUP_EXPORT.md) · [Evidence](COLOR_LOOKUP_EXPORT_405.json).

**Checkpoint404 update:** D01 closing and L07 artboard duplicate/background candidates are already implemented and pass25/15focused cases per architecture on unchanged403Source02. S01 now has a development-qualified Single Row/Single Column Marquee native/API baseline. Grow/Similar moves to major stillneeded. **G01 Transform Again is next**, then A03. Full package acceptance is unchanged. Focused development builds lead this sweep; normal optimized universal qualification is batched at stable milestones. [Current queue](WORK_PRIORITIES_404.json) · [Evidence](SINGLE_PIXEL_MARQUEE_404.json).

**Checkpoint403 update:** L01/AUT02’s ordinary raster/plain-group native baseline is delivered and tested. Full selector parity remains open. **D01 is selected next**, then L07 and S01. The original per-package table below is retained; current queue and delivery scope are in [WORK_PRIORITIES_403](WORK_PRIORITIES_403.json). Focused development builds now lead breadth work; optimized universal/runtime qualification is batched at stable milestones unless the change needs an immediate architecture check.

# Current work order

Updated 4 November 2026 at the maintainer’s request. This changes scheduling, not the Photoshop 2026 target or the definition of a completed feature.

1. Major quick wins
2. Major still needed
3. Minor quick wins
4. Minor still needed
5. Major cleanup
6. Minor cleanup
7. Final settings and cleanup checks

Quick wins are small, useful changes that fit the current engine. Still needed contains substantial missing behavior. Cleanup contains residual fidelity, uncommon combinations, refinement and broader qualification. All original acceptance criteria stay attached to their packages. The phrase “final 5%” is not a measured feature-completion estimate.

We sweep each package once per pass. A quick win gets one normal implementation checkpoint, including its UI, menu, API, history and focused tests. If it turns into a larger engine project, record the findings under still needed and move on. Fix safety and transaction failures before treating a path as delivered. Do not spend successive checkpoints exhausting one subsystem’s details.

**Current: S02 — Color Range, Focus Area and Magnetic Lasso, major stillneeded(pass2).** Audit remaining tools/controls against source and Photoshop; implement a useful shared native/API path. S03 follows. Full L06 and earlier native/output/default/platform gates remain open. [Priority](WORK_PRIORITIES_464.json) · [Original scope](FUNCTION_PHASES_464.json)

**S05 is parked, still open.** Its seven-file Photoshop reference matrix is complete. The selected-gray/initially-empty/explicit-full and PSD repair will resume during major still needed. A channel-row double-click candidate can be considered once when S05 is reached in the quick-win sweep. C01 no longer waits for S05 closure.

Candidates below require a source audit before implementation unless evidence already confirms the gap. A blank quick-win cell means no honest small implementation was identified; that package skips the quick-win pass. Existing functionality will not be rewritten to create a completion count. Final-detail tracks stay inside pass7, in quick-win/still-needed/cleanup order.

[Machine-readable priority](WORK_PRIORITIES_462.json) · [All scope, acceptance and tracks](FUNCTION_PHASES_462.json) · [S05 restart point](QUICK_MASK_GRAY_401.json)

## Major functions

| Package | Quick-win candidate | Still needed |
|---|---|---|
| L01 — Layer organization and Background semantics | Implement Delete All Empty Layers through one native transaction and the optional API | Complete remaining Background/locks/links/selection/arrangement/filter/isolation operations |
| D01 — Open, save, close and revert workflows | Repair a bounded failing Close All/Others or Save a Copy case before broad lifecycle expansion | Complete remaining open/save/revert/quit, read-only access and persistent permissions |
| L07 — Artboards and frames | Add a missing artboard duplicate/background command on existing geometry | Complete artboard coordinates/guides/export and Frame tool content replacement |
| S01 — Basic selection completeness | Implement confirmed missing Grow/Similar commands with native/API selection history | Complete marquee variants, Reselect, border/move/transform and selection options |
| G01 — Transform and crop completeness | Wire Transform Again to the retained transform operation | Complete multi-target/mask transforms, reference/snapping and nondestructive crop/resize |
| A03 — Remaining classic adjustments | Connect existing Brightness/Contrast to native destructive and adjustment-layer menus | Complete remaining classic adjustments, presets, masks and dialogs |
| I05 — Production export workflows | Add native LUT export for an existing supported color transform | Complete Save for Web/slices/assets, presets/scales and layer/artboard/comp exports |
| B05 — Patch, Content-Aware Move and Red Eye | Complete Red Eye controls using the existing removal engine | Complete Patch adaptation and Content-Aware Move/Extend protected-region workflow |
| C01 — Component visibility and edit targeting | Bring RGB8 component rows to existing high-depth Shift-selection behavior where supported | Complete multi-target editing/visibility, temporary masks, eye gestures and factory shortcuts |
| AUT01 — Actions and batch processing | Expose an existing action reorder/duplicate command in native UI | Complete semantic targets, dialogs/conditions/ATN/droplets/batch/Image Processor |
| G03 — Live shape tools and vector operations | Expose a missing shape property backed by existing live shapes | Complete shapes/arrows/corners/stroke/booleans/presets and pixel/shape/path modes |
| G04 — Pen and Paths completion | Expose a missing Fill/Stroke Path action using the existing path engine | Complete pen variants/modifiers, multi-anchor editing, fitting and clipping-path export |
| T01 — Full native text editing | Add a missing Character/Paragraph control already supported by rich type | Complete on-canvas/rich type editing, point/box conversion and editable PSD text |
| T04 — Path, warped and Dynamic Text | Expose an existing path/warp text parameter in native controls | Complete text-on/inside paths, Dynamic Text, auto-fit/reflow and persistence |
| A01 — Levels, Curves and Auto correction closure | Expose a missing Levels/Curves preset or Auto option backed by existing engine | Complete sampling/clipping/targeted/freehand curves, mask/HDR and presets |
| A04 — Current2026 adjustment layers | Add a missing native control for an existing modern adjustment | Complete 2026 nondestructive adjustments and editable PSD behavior |
| A05 — Gradients and gradient-fill completeness | Expose an existing gradient transform/preset through on-canvas controls | Complete modern editing/interpolation/noise/dither and GRD/preset behavior |
| A07 — Pattern fills and pixel fills/strokes | Add a missing Fill/Stroke placement option backed by current engine | Complete pattern transforms/libraries/interchange and fill/stroke target semantics |
| F01 — Filter framework and ordinary blur/sharpen/noise | Expose a supported filter's missing preset or repeat-last action | Complete ordinary blur/sharpen/noise catalogue and consistent preview/cancel pipeline |
| F02 — Distort, Pixelate, Stylize, Render and Other | Implement one bounded missing ordinary filter with shared native/API path | Complete remaining Distort/Pixelate/Stylize/Render/Other and available legacy filters |
| F03 — Blur Gallery | Add an existing Blur Gallery parameter missing from controls | Complete field/iris/tilt/path/spin handles, bokeh/noise and editable Smart Filters |
| F04 — Liquify | Expose existing freeze/thaw/reconstruct operations in the Liquify workspace | Complete mesh/push/twirl/pucker/bloat/face-aware controls and persistence |
| F05 — Perspective and lens filter workspaces | Expose a missing manual lens-correction parameter backed by existing engine | Complete perspective planes/constraints, Adaptive Wide Angle and lens workspace |
| F06 — Filter Gallery and legacy applicability | Expose existing gallery-stack reorder or preset commands | Complete legacy effect catalogue and applicability across supported document modes |
| B01 — Brush engine and brush settings | Add a missing brush setting control backed by existing deterministic engine | Complete tip families, dynamics/scatter/texture/symmetry/ABR and input curves |
| B02 — Missing paint and eraser tools | Complete one missing option on an already working Pencil/eraser tool | Complete Mixer/Replacement/Pattern/Background/Magic Eraser target and sampling behavior |
| B04 — Clone, heal, blur and toning completeness | Expose a missing clone-source control backed by the current renderer | Complete healing/sample modes/dynamics/overlays and toning/focus behavior |
| B06 — Content-Aware Fill and Scale | Expose an existing output-layer choice in Content-Aware Fill | Complete sampling workspace, adaptation, crop fill and protected content-aware scaling |
| B07 — Tablet, stylus and eyedropper qualification | Add missing persistent Color Sampler point controls using current sampling | Complete real stylus/eraser/button replay, averaging and cursor/latency handling |
| D04 — Clipboard interoperability | Add one missing channel/path clipboard format using existing serializers | Complete external layered/vector/PDF clipboard, depth/profile and Background Cut semantics |
| L03 — Advanced blending | Add a missing native control for an already implemented advanced-blend property | Complete Fill opacity, split Blend If, knockout/channel/clip/mask flags and PSD persistence |
| L04 — Layer styles and effects | Expose missing Copy/Paste/Clear Layer Style actions on the existing style engine | Complete effect options, contours/global light, multiple effects, presets and editable interchange |
| L05 — Embedded and linked Smart Objects | Finish a bounded missing-link or relink action without reopening precision research | Complete nested/shared/independent source editing, replace/update/export/package and transforms |
| L06 — Smart Filters | Add a missing enable/reorder/copy operation on existing Smart Filters | Complete editable stacks, masks/blending and supported metadata/fallback behavior |
| S02 — Color Range, Focus Area and Magnetic Lasso | Add an omitted preset/control to existing Color Range | Complete focus-region detection, edge-following lasso and averaged sampling |
| S03 — Object, Quick, Subject, Sky and People selection | Expose a supported subject/sky/person selection as a context-sensitive action | Complete object finder, all-object/person-part/quick selection and manual correction |
| S04 — Select and Mask workspace | Wire missing output choices to the existing selection/mask transaction | Complete refine workspace, edge/hair/smart radius, decontamination and outputs |
| S06 — Pixel/vector mask workflow closure | Expose a missing apply/delete-mask confirmation using existing mask commands | Complete target transforms/filters/clipboard, compound masks, defringe/decontamination |
| C02 — Alpha and spot channels | Expose a missing duplicate/reorder/rename channel action on existing core | Complete alpha/spot ink/solidity and native/PSD channel persistence |
| COL02 — Document color modes and separations | Expose a supported mode conversion missing from menus with its true restrictions | Complete all mode/depth/palette/dither/ink semantics and editable storage |
| COL03 — Proofing, HDR/EDR and print | Expose an existing proof preset missing from native controls | Complete proof/gamut/HDR/EDR, print/page setup and output profiles/overprint |
| RAW02 — Photo alignment and merging | Expose an existing stack statistic through a native command | Complete align/blend/panorama/HDR/focus stacking, masks/crop and deghosting |
| I03 — Original PhotoCraft .pcraft migration | Add an omitted supported upstream metadata migration with a licensed fixture | Complete all represented pcraft layers/types/metadata and safe original retention |
| I04 — Export and interchange formats | Expose an existing encoder option missing from export UI | Complete layered TIFF/EPS/DCS/PDF/SVG/EXR/HDR formats, profiles/depths/metadata |
| AI07 — AI job/document lifecycle and persistence | Expose already tracked model/seed/provenance in result inspection where available | Complete immutable jobs, stale/cancel/results, editable persistence and offline reopening |
| SP01 — Timeline, frame animation and video | Expose an existing frame-timeline command missing from native controls | Complete timeline/video/keyframes/transitions/audio and import/render/animation export |
| AI09 — Sky Replacement | Expose an existing sky-library import/delete action in native controls | Complete replacement masks/horizon/light/color and nondestructive manual refinement |
| B08 — Adjustment Brush | Expose an existing Adjustment Brush preset or targeting option in native controls | Complete adjustment painting, automatic target/refine and native workflow |
| Q03 — Responsiveness and cancellation | Remove one measured remaining main-thread blocker in an ordinary tool path | Complete progressive preview/cancel/low-memory and sustained interactive responsiveness |
| Q04 — Independent Photoshop oracle and corpus programme | Add focused independent fixtures for each newly implemented quick win | Expand independent modes/depths/profiles/formats/workflow corpus and malformed input coverage |
| REL01 — App Store archive, sandbox and release CI | Repair one confirmed archive/sandbox validation defect using existing project | Complete production identity/entitlements, reproducible archive CI and disclosures |
| AUD01 — Reconcile all inventories and freeze the target | Keep new function/menu/API inventories synchronized as each quick win lands | Reconcile all tools/commands/scenarios and current 2026 platform/service boundaries |
| AUT02 — Scripts, variables and command automation | Implement Delete All Empty Layers jointly with L01; one deliverable, not two completions | Complete scripts/events/variables/data-driven output and extension contracts |
| S05 — Quick Mask and saved selections | Add channel-row double-click to existing Quick Mask options | Repair confirmed selected-gray/initially-empty/explicit-full semantics; complete save/load/combine/shortcuts |
| A02 — Hue/Saturation and Color Balance exactness | — | Complete targeted sampling and Hue/Saturation/Color Balance range semantics |
| A06 — Gradient and RGB32 fill exactness | — | Resolve RGB16/32 gradient transfer and fill semantics |
| AI01 — Model evaluation and native runtime | — | Complete licensed model selection/download/hash/remove and native inference memory/latency |
| AI02 — Apple local text and Private Cloud Compute validation | — | Complete real local/PCC generation, disclosure/cancel and unavailable-device behavior |
| AI03 — Remove, distractions and generative fill | — | Complete offline remove/distractions/prompted edits, protected pixels and reversible variants |
| AI04 — Generative expand and backgrounds | — | Complete reversible expand/background/full-image generation with retained subject/source |
| AI05 — Reference-guided edits, prompts and markup | — | Complete reference-guided/markup/prompt edits, variants and provenance |
| AI06 — Harmonize, generative upscale and Neural Filters | — | Complete harmonize/restoration/upscale and available Neural Filter equivalents |
| AI08 — Assistant and provider capability differences | — | Complete assistant capability audit and user-reviewed native command planning |
| AUD02 — Resolve model, language and ecosystem boundaries | — | Resolve model-quality/locales/services/plugin boundaries and acceptance decisions |
| AUT03 — Third-party plugin compatibility | — | Define and implement supported native plugin/extension compatibility and isolation |
| COL01 — ICC working-space and color management | — | Complete import/profile policies, assign/convert, intents/BPC and calibrated display |
| D02 — Crash recovery and autosave durability | — | Complete crash-safe journal/recovery, fault handling and restoration UX |
| G02 — Warp, Puppet Warp and Perspective Warp | Expose a missing warp preset backed by existing geometry | Complete editable grids, Puppet pins and perspective/nondestructive smart transforms |
| G05 — Vector rasterization fidelity | — | Complete winding/sample/raster coverage behavior and supported PSD path forms |
| I01 — Editable PSD feature coverage | — | Complete missing editable PSD feature records and safe unknown-block editing restrictions |
| I02 — PSB and large/streaming file support | — | Complete bounded PSB streaming, multi-GB editable round trips and malformed-file guards |
| L02 — Layer composition and merge exactness | — | Complete group/clipping/mask blends, multi-layer rasterize and merge/flatten correctness |
| Q01 — Large-document storage and scratch engine | — | Complete scratch/tile paging, bounded undo and large mask/vector/group storage |
| Q02 — Metal and incremental rendering | — | Complete incremental GPU/CPU composition and deterministic rendering fallbacks |
| Q05 — End-to-end professional acceptance and runtime matrix | — | Complete professional scenarios, real runtime/device/input/display matrix and soak testing |
| Q06 — Universal byte-identical Photoshop results | — | Resolve sample/render/file identity boundaries and known cross-architecture/output differences |
| RAW01 — Camera RAW development | — | Complete native RAW development, local masks, lens/highlight/XMP and nondestructive sources |
| RAW03 — RAW restoration and reflection removal | — | Implement/evaluate RAW restoration and reflection-removal equivalents |
| S07 — AI edge enhancement | — | Implement and evaluate editable Enhance Edge refinement for hair/translucency |
| SP03 — Cross-application and asset ecosystem | — | Complete native local/open-service asset and cross-application equivalents |
| T02 — Multilingual and OpenType typography | Expose a supported variable-font axis or ligature option in native controls | Complete bidi/RTL/Indic/East Asian/vertical typography and font fallback/composers |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

## Minor functions

| Package | Quick-win candidate | Still needed |
|---|---|---|
| B03 — History and Art History Brush | Expose a missing history-source selector over current history state | Complete pixel-compatible History Brush and artistic styles/constraints |
| C03 — Channel calculations and interchange | Expose an existing Apply Image/Calculations setting absent from native controls | Complete split/merge/spot merge, cross-document sources and mode/depth interchange |
| C04 — Channel display and thumbnail parity | Finish thumbnail-size preference persistence with existing panel options | Complete channel color display, preview samples and menu/cancel lifecycle |
| D03 — History, snapshots, Fade and purge | Expose Toggle Last State through existing history state | Complete snapshots, nonlinear history, Fade, history source/logs and purge |
| G06 — Rotate Object and pattern preview | — | Implement object-reorientation equivalent and seamless Pattern Preview |
| I06 — Metadata and content provenance | Expose a missing copyright/description field in File Info | Complete EXIF/IPTC/XMP retention, provenance and supported credentials/signatures |
| L08 — Layer comps and local libraries | Expose a missing Layer Comp update/rename action on the existing engine | Complete comp capture/apply/appearance, reusable local assets and cross-document workflow |
| SP02 — Slices, measurement and scientific workflows | Expose a supported Ruler/Count measurement through the native panel | Complete slices/measurement/logs/annotations/DICOM and image-stack analysis |
| T03 — Text styles and utilities | Add Find/Replace for existing editable text runs | Complete styles, spelling, font resolution, type masks and conversion/rasterization |
| U01 — Post-dialog panel command state | Reproduce and repair stale Panel Layout validation after options Cancel | Complete document-switch, Escape and OK command-state coverage |
| U03 — Docking and document-window interaction | Add one missing document-arrangement command using the existing arrangement engine | Complete tab tear-off, floating/docking and synchronized multi-view workflows |
| U04 — Canvas navigation and view modes | Add missing Fit Layers or Fit Artboards command through existing view geometry | Complete scrubby/animated zoom, view modes, print/pixel-aspect and Retina behavior |
| U05 — Rulers, guides, grids and snapping | Expose missing guide locking/clearing commands over existing guides | Complete unit-aware origins, smart guides, layouts and snap targets |
| U06 — Remaining utility panels | Finish one existing utility panel's missing menu action | Complete Navigator, Histogram, Info, Notes, Measurement and Tool Presets |
| U07 — Home, New Document, search and contextual actions | Add a reusable New Document preset using the existing creation path | Complete recent/clipboard presets, search discovery and contextual actions |
| U08 — Menu and shortcut closure/customization | Wire confirmed missing alternate shortcut bindings to implemented commands | Complete custom shortcut/menu/toolbar sets and context validation |
| U09 — Preferences and settings | Expose a working engine preference missing from Settings | Complete preference categories, migration, reset and factory defaults |
| U10 — Numeric input and dialog behavior | Add arithmetic expression entry to an existing unit-aware input | Complete ranges, scrubbing, modifiers, preview and modal keyboard behavior |
| U11 — Color and asset panels | Add search to existing local swatch/pattern groups | Complete grouped assets, import/export and Photoshop color picking |
| U12 — Accessibility and localization | Repair confirmed missing accessible names/focus in a working editor panel | Complete keyboard-only/VoiceOver workflows and localization architecture |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

## Final details and release completion

| Package | Quick-win candidate | Still needed |
|---|---|---|
| REL03 — Open-source fork publication | — | Complete curated upstream-history fork, notices/provenance and public release preparation |
| REL04 — Beta, documentation and release readiness | — | Complete help/migration/known-limits, installation/update and release documentation |
| U02 — Workspace appearance and factory defaults | — | Match workspace geometry, icons, contrast, compact layouts and factory defaults |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

