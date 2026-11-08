# Mask and channel clipboard

Select an alpha channel, Quick Mask, layer mask or Smart Filter mask, then use the existing Edit > Copy, Cut, Paste or Paste In Place commands. Copy Merged and Paste Into/Outside are unavailable for these targets. An unlocked visible Quick Mask is required for writing; Copy can read a hidden channel or a locked layer mask. Image pixels and unrelated channels stay unchanged.

Copy carries raw grayscale values and separate selection opacity, preserving document depth and copied coordinates in the existing native clipboard format. Cut publishes the clipboard before changing the document. Cut and Paste each use one undoable transaction. Failed, cancelled or stale work does not publish a prepared edit. Paste clips through the current selection, then selects the covered destination area. Mask storage expands using its existing coordinate transform and outside value; density and feather remain editable.

A grayscale plane pasted into another plane uses its numeric values directly. Colour input goes through the existing native grayscale conversion using the captured working Gray profile. This is implemented behavior, not a claim of exact Photoshop conversion or floating-selection equivalence. Mask-thumbnail versus mask-only display admission still needs a live Photoshop reference.

Large sparse transfers retain their full native extent. When full TIFF/PNG generation would exceed the existing dense-image budget, those standard representations are omitted. The private native payload is not replaced by a small preview. Other applications therefore cannot consume every large native transfer. Existing native/API payload limits remain separate capacity gaps.

## Optional API

The existing `clipboard.copy`, `clipboard.cut` and `clipboard.paste` commands accept an explicit `target`:

- `{"kind":"alpha","channelID":"<existing UUID>"}`
- `{"kind":"quickMask"}`
- `{"kind":"layerMask","layerID":"<existing UUID>"}`
- `{"kind":"smartFilterMask","layerID":"<existing UUID>"}`

Copy returns the existing native `payloadBase64` reply. Targeted Cut also accepts `backgroundValue` from 0 through 1 and returns the updated document state. Paste accepts the payload and `placement` (`centered` or `inPlace`), with optional document-space `center`. Targeted calls reject layerIDs/merged/backgroundColor/colorDecision overrides. They operate on the explicit plane without changing the desktop editing target or touching the Mac clipboard. New Document accepts a grayscale payload with the existing document-transfer permission.

`clipboard.targetedPlane` reports the current desktop target, copy/write availability and operation identity. Capability discovery provides target/state schemas and current limits. Clipboard and Actions format versions remain unchanged. Recording a targeted clipboard command produces an explicit unsupported step; portable replay remains unfinished. No Firefly endpoint or plug-in runtime was added.

## Validation and remaining work

Checkpoint 460 passes all 45 selected Debug tests and the same 45 optimized methods on Apple Silicon and translated Intel, including 20 new methods. The tests exercise all three pixel depths and four targets, native/API agreement, undo/redo, irregular selection opacity, spot samples, translated mask expansion, failed/cancelled/stale native edits, API errors and a 300,000 × 300,000 sparse transfer. The captured 984-byte numeric buffers and independent literal calculations are compared without tolerances. [Evidence](TARGETED_CLIPBOARD_460.json) records the exact outcomes and retained failures.

The first build failed at an existing benchmark's optional-buffer consumers. The second ran all tests but rejected an invalid media type in new Smart Object fixtures. The fixture repair leaves the application executable byte-identical. Both failed attempts and their source/products remain recorded.

Live controls, focus, physical input, normal Close/Quit and installed Photoshop scalar output are unqualified while the existing UI automation issue remains unresolved. RGB component-set/path clipboard, external vector/PDF/layered formats, Background Cut, scalar Into/Outside, portable Actions, full profile/rounding/selection fidelity and broad performance/platform checks remain open under D04. All previous failures and the original package scope remain. The next package is L03, followed by L04.

[Adobe mask workflow](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/edit-and-refine-layer-masks.html) · [Adobe layer clipboard guide](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/create-layer-compositions/copy-and-paste-layers.html)
