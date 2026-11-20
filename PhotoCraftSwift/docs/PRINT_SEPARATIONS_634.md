# Print layered CMYK and spot separations

19 November 2026 · Development preview 634

**File > Print > Separations** now creates one grayscale page for each process plate and saved spot ink in eligible documents. Flat CMYK and ungrouped Normal CMYK layers with retained components use their numerical ink values. Duotone prints its calculated inks and any saved spots. Multichannel follows the relative order of its ink rows in the Channels panel. Ordinary saved masks stay out of the print job. Spot pages use the numerical ink density alone.

`PrintOutput.swift` shares the printing surface with the native workspace and `GET /v1/documents/{id}/print.pdf`. It uses the component compositor in `InkModeInput.swift` for eligible layered CMYK input. Settings, selection bounds, source pixels and editing history retain their existing behavior. Labels identify the ink on each page. Complex stacks still require a flattened copy. The authenticated catalogue advertises the spot, order and layered support under `printing.separations`. [Photato API](AUTOMATION_API.md#print-separation-pages-checkpoint-634)

Adobe documents a separate print page for each CMYK process and spot channel and states that Solidity does not change the printed separation. This checkpoint follows that data model. The app's existing Separations control and current 8,388,608-pixel print layout budget remain in place. Physical press output, PostScript screens, rich layer stacks and the Photoshop control placement remain open. [Adobe print separations](https://helpx.adobe.com/photoshop/desktop/print/print-color-separations.html) · [Adobe spot colors](https://helpx.adobe.com/photoshop/desktop/adjust-color/color-effects-techniques/work-with-spot-color-channels.html)

The Apple Silicon Debug build completed in 136.76 seconds. All 42 selected XCTest cases passed in 26.67 seconds. The new cases check two layer coverage states, hidden artwork, selected-area cropping, ink ordering in Multichannel, Duotone plus spot, and matching native preview and authenticated PDF labels without a document edit. The existing AppKit pagination test saves to a PDF file, and its printer-submission tests use an injected callback.

The independent fixture generated an owned 24 × 16, 16-bit layered CMYK job with a saved mask and a spot. A separate calculator matched every prepared word. Poppler found five pages with the expected labels and five embedded one-component 16-bit images. The five Flate image streams matched all 1,920 expected words after decompression. Visual inspection of all rendered pages checked labels, image placement and marks. The raw planes, PDF, renders and validation logs are under `artifacts/634-print-separations/`. The 1,163-case regression is running.

The ad hoc-signed Apple Silicon preview verified after ZIP extraction. The extracted macOS 14-targeted executable produced a 1,000 × 650 workspace snapshot.

All 1,163 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.
