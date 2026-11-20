# Native separations in layered Multichannel conversion

19 November 2026 · Development preview 632

**Image > Mode > Multichannel** now composites the stored components of eligible layered CMYK and Lab documents. This keeps the independent black ink and other native component values through the flatten operation. The earlier path rendered the layer stack to RGB and then separated that preview back into components. Its reconstructed channels could differ from the source even under an opaque layer.

`InkModeInput.swift` shares the conversion with **Delete Channels**. Both paths use the existing numerical component compositor for eligible ungrouped Normal raster layers with native samples. Hidden artwork is excluded from that compositor, including hidden fills. The wider color compositor handles other stacks. The desktop preview, commit, Actions and authenticated Photato API use the same prepared edit. The explicit consent to merge visible layers and discard hidden layers applies to both workflows.

The Photato capability catalogue reports `inkModes.largeMultichannel.nativeLayeredSeparationModes` with `cmyk` and `lab`. Requests and file schemas retain their existing formats. [Photato API](AUTOMATION_API.md#layered-multichannel-conversion-checkpoint-632)

Adobe documents CMYK conversion as creating the four process separations from a flattened document. The file probe independently computes the expected native words for a synthetic 16-bit, three-pixel CMYK stack with partial, full and zero top-layer coverage. A separate parser confirmed that build 631 matched none of the 12 expected words in either raw export. Build 632 matched all 12 in each PSD and PSB. These are integer-compositing and format fixtures. The Photoshop desktop automation recorded in 631 timed out, leaving an Adobe-authored comparison pending. [Adobe color modes](https://helpx.adobe.com/photoshop/desktop/adjust-color/choose-colors/color-modes-in-photoshop.html)

The Apple Silicon Debug build took 130.36 seconds. All 24 selected XCTest cases passed in 24.33 seconds. The three new tests cover CMYK and Lab at 8 and 16 bits, transparent and opaque layer coverage, hidden artwork and one-step Undo. The sparse test used a 300,000 × 300,000 CMYK canvas and verified untouched and changed words in all four plates, with a native archive under 1 MB. The app test used the desktop preview and the authenticated `document.convertMultichannel` operation on the same layered input. All 1,136 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks. Logs and the bidirectionally verified source patch are under `artifacts/632-layered-ink-conversion/`.

The Apple Silicon macOS 14+ preview ZIP passed strict signature verification after extraction. Its extracted executable produced an offscreen 1,000 × 650 workspace snapshot.
