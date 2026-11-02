# Original adjustment layers

**Checkpoint323, Source05:**11/12 new cases pass; the remaining case retains strict whole-document failures. All129 direct source vectors match107,844 original words. Stored output matches86/129 references (RGB8 43/43, RGB16 40/43, RGB32 3/43); unrounded composites match83/129. The affected run passes350/355 with five strict failed cases/111 assertions, zero unexpected errors/crashes. Native controls/API/history/native74/Actions29/source retention are functionally tested within the limits below. No complete current inventory or native/Photoshop visual/output/platform qualification is claimed. See [checkpoint](WORKING_CHECKPOINT_323.json) and [evidence](SOURCE_ADJUSTMENT_REFERENCES.json).

Original PhotoCraft projects contain sixteen evaluated adjustment types plus an opaque Unsupported record. Exposure retains its previously supported classic native representation. The new source representation retains the other controls as Float32 instead of rounding them into the existing integer Photoshop control scales. It stores brightness/contrast and legacy mode, normalized Levels channels and curve coordinates, hue/range controls, color weights and matrices, lookup cubes and names, gradient stops and dither, and unsupported raw PSD bytes.

Select an imported adjustment layer to edit its native Properties controls. Layer identity, masks, opacity, clipping and source originals remain intact; edits use document Undo/Redo. The native preview updates through the same renderer used by the API. Lookup profiles without a cube and unknown PSD adjustments remain visibly inactive. A chosen normalized3D cube can replace a missing lookup; retained names grant no file access. This is a source-oriented editor; complete Photoshop UI/controls/default fidelity remains a separate requirement.

The existing Photato `adjustment.create`, `adjustment.set` and `adjustment.apply` commands accept a separately identified source payload:

```json
{
  "kind": "source",
  "settings": {
    "kind": "vibrance",
    "parameters": { "vibrance": 38.125, "saturation": 21.375 },
    "records": {},
    "options": {},
    "space": "rgb"
  }
}
```

Commands accept this object as the `adjustment` parameter. Set additionally requires `layerID` and retains the existing adjustment kind. Apply requires an ordinary pixel layer and an evaluated adjustment. Create uses current selection coverage as a mask. Existing busy, stale-revision, sharing and transfer opt-ins remain in force. State exposes `sourceAdjustment`; capabilities expose `sourceAdjustments` with schema and executable/opaque kinds. These are Photato source controls; existing Adobe operations keep their own schemas and supported subset. No Adobe route or proprietary descriptor is invented.

Parameters/records/options are validated by adjustment kind. Tone channel records are Master/Red/Green/Blue/Black rows of Input Black/Input White/Gamma/Output Black/Output White. Curves retain Input/Output pairs; hue ranges retain Hue/Saturation/Lightness plus four bounds. Mixer records use three output rows of RGB coefficients and Constant. Selective Color rows are Reds/Yellows/Greens/Cyans/Blues/Magentas/Whites/Neutrals/Blacks with CMYK percentage columns. Gradient stops contain Location/Red/Green/Blue. A cube stores red-fastest RGB triplets. No field implies file or session access.

Native74 and Actions29 retain the source representation; older features keep their prior minimum versions. HTTP native downloads containing it require `X-Photato-Archive-Version: 74`. Unqualified editable PSD export rejects these records rather than flattening them silently. Normal installed preview283 and the last entirely passing full/private source298 remain separate from current source development.

Current admission limits include RGB document/tone evaluation,256 curve points per channel,4096 gradient stops,129-cube lookup dimensions and1MiB opaque raw data, plus existing document/source/manifest budgets. CMYK/Lab tone evaluation, all source contexts, exact original and Photoshop outputs, complete native visual/menu/default/shortcut/preferences behavior, passing full-current tests, large-operation capacity, physical60fps and universal/Intel/macOS14+ runtime remain open until independently verified.

The owned oracle contains43 programs/129 depth rows. Original licensed Rust generates separate raw adjustment buffers, unrounded compositor buffers and depth-encoded merged outputs; production remains Swift. The original words and their representation scopes are preserved. Native round trips, source transfer tests and full-document comparisons provide different evidence and are not interchangeable.
