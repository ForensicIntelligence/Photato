# Restore CMYK process plates and spot inks

19 November 2026 · Development preview 633

**Image > Mode > CMYK Color** can restore process components from a Multichannel document with the standard ordered Cyan, Magenta, Yellow and Black plates followed by spot inks. The four process plates must use Photato's default swatches and zero Solidity. The swatch comparison uses the 16-bit precision of PSD and PSB display records. Eligible files can return to the same CMYK depth with their original numerical process samples. Additional plates become editable spot channels. They retain their relative order with saved masks, their densities and swatches, and any retained Photoshop identifiers.

`InkModeDocument.swift` recognizes the four process components and uses the shared integer and paged conversion path. `InkModeRaster.swift`, `InkModeInput.swift` and `PSDInkChannels.swift` share the swatch definitions and metadata keys. This uses the existing native archive and Photoshop file representations. Custom or reordered process swatches continue to use the existing composite conversion. A live comparison of those Photoshop workflows remains open.

The native command and authenticated `document.convertMode` use the same prepared edit and the same Undo. This capability is discoverable through `documentModes.multichannelCMYKReturn`. [Photato API](AUTOMATION_API.md#return-to-cmyk-with-spot-inks-checkpoint-633)

Adobe documents separate CMYK process and spot inks and a distinct Merge Spot Channel action. The exact reverse mapping of arbitrary Multichannel files has no confirmed live Photoshop capture here. The independent fixture uses a published-format CMYK input containing a saved mask and a spot ink. Build 632's CMYK return lost the spot channel and changed all 24 process sample bytes in both formats. [Adobe color modes](https://helpx.adobe.com/photoshop/desktop/adjust-color/choose-colors/color-modes-in-photoshop.html) · [Adobe spot channels](https://helpx.adobe.com/photoshop/desktop/adjust-color/color-effects-techniques/work-with-spot-color-channels.html)

The first test build rejected a fixture initializer label. The corrected source snapshot uses the existing unlabeled `DocumentModeRequest` initializer and retains the same production files and assertions.

All 31 selected tests passed in the corrected snapshot. The independent parser then found that the PSD and PSB merged preview still differed across all four process channels, while the editable layer and both auxiliary planes were exact. Separating the two file representations located the remaining issue in `PSDCodec.swift`. An aligned opaque CMYK layer supplies its native words directly to the merged channel writer. Large eligible rows use the existing sparse row support. This changes the preview of eligible CMYK files and leaves spot channels as independent planes.

The second independent probe verified all 24 merged process bytes and all 12 stored mask and spot bytes in each finished file. The auxiliary names, swatches, Solidity, and identifiers match the source. The earlier failing files and their parser output were retained. Verification fixtures and build logs are under `artifacts/633-cmyk-ink-return/`.

The final Apple Silicon Debug build completed in 149.67 seconds. All 40 selected cases passed in 35.36 seconds. The new tests check raw 16-bit merged data, PSD and PSB reopening, a 300,000 × 300,000 sparse native return, and the first and final rows of a 300,000 × 29 PSB merged preview. The desktop preview and authenticated conversion agree, and Undo restores the reopened Multichannel document. The source patch was checked in both directions against 632. The 1,139-case regression is running.

The signed preview ZIP verified after extraction. The extracted Apple Silicon executable targets macOS 14 and produced a 1,000 × 650 offscreen workspace snapshot.
