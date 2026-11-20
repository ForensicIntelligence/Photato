# Vector masks in Perspective and Distort

Select the layer content and open Free Transform with Command-T. On supported RGB pixel layers, resolved Smart Objects and their groups, Perspective and Distort now work with a vector mask. A linked mask follows the layer. An unlinked mask stays at its original document position. The preview and the committed edit use the same geometry worker. The edit produces one Undo step.

The transform retains the mask's enabled state, linkage, density, feather, contours and path operations. A linked straight edge stays straight. A homography maps a cubic curve to a rational cubic. Photato uses homogeneous subdivision and matches the tangents at segment ends so the result remains editable with the Pen and Direct Selection tools. Each fitted curve is within 1/64 document pixel of the projective curve before file quantization. Curves can gain anchors. A linked path that crosses the projective horizon or exceeds the supported path limits stops the edit before it changes the document.

Native files, PSD and PSB retain the editable mask. Photoshop containers quantize control points to signed 8.24 normalized coordinates. The unchanged `layers.transform` command accepts the same row-major homography used by the desktop. [Photato Automation API](AUTOMATION_API.md) · [Adobe path and mask record specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Adobe mask linkage](https://helpx.adobe.com/sg/photoshop/desktop/create-masks/layer-masks/unlink-layers-and-masks.html)

The original PDF in the interchange fixture was placed by Photoshop. Photato applied the test transforms. Independent Photoshop renders and anchor placement, non-neutral Warp with vector masks, and independent projective editing of a selected mask remain open.

## Validation

All 131 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

All 12 owned PSD, PSB and composite outputs matched across the three configurations. An independent PSD/PSB path reader checked 2,064 samples of the saved curves. The largest measured deviation from the analytic projection was 0.00684 document pixel, including file quantization. Each of the eight Photoshop container round trips preserved all composite bytes.

[Qualification](SOURCE_PUBLICATION_671.md)
