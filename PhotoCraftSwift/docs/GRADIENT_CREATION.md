# Create and paint gradients

Checkpoint 442 separates Gradient tool creation defaults from existing Gradient Fill edits. Options and the toolbar preset picker configure the next gradient. Edit an existing fill through its canvas controls, Properties, or `gradient.fill.patch`. Sidebar preset application retains its explicit apply behavior. The rendering math and existing pixel fixtures are unchanged.

Adobe’s [Apply Gradient Fill guide](https://helpx.adobe.com/photoshop/desktop/adjust-color/color-effects-techniques/apply-gradient-fill.html), updated 28 April 2026, documents that Options affect new gradients. Its [editing guide](https://helpx.adobe.com/photoshop/desktop/adjust-color/color-effects-techniques/edit-a-gradient.html), updated 18 August 2026, describes editing existing gradients on canvas. These document workflow intent; they do not establish numerical or live Photoshop equivalence.

The optional Photato API adds three commands at `POST /v1/documents/{id}/commands`, using the current revision and the usual authentication and sharing controls:

| Command | Parameters and effect |
| --- | --- |
| `gradient.tool.configure` | Nonempty `options` patch, `reset:true`, or both. Configures session defaults without selecting a tool, changing document pixels, or adding Undo. |
| `gradient.fill.create` | Required complete `fill`; optional `name`, `parentID`, `opacity`, `blend`, and `maskFromSelection`. Creates a live Gradient Fill using the native factory and prepared transaction. |
| `gradient.paint` | Required `layerID` and captured `stroke`. Paints ordinary raster pixels or an existing pixel mask with the same Classic Gradient command as the native tool. |

For example, configure the next gradient without editing a selected fill:

```json
{"command":"gradient.tool.configure","revision":"<current revision>","parameters":{"options":{"mode":"Classic Gradient","style":"Radial","reverse":true,"opacity":0.75}}}
```

`gradientTool` state reports resolved creation options and whether configuration, creation, active pixels, and active-mask painting are available. Discovery includes request, result, and state schemas. Refresh the revision after configuration before issuing another command. Partial gradient patches preserve native foreground/background stop references unless their colour array is supplied; reset restores factory references. Explicit create and paint payloads contain captured colours and do not read mutable tool defaults implicitly.

A fill uses the existing full Gradient Fill schema. Omitted `parentID` uses the active group or active layer’s parent; explicit null uses the document root. Selection masks default to the current selection’s presence. Explicit `maskFromSelection:true` without a selection creates Reveal All, as the existing native command does. Names, geometry, parent groups, opacity and gradient definitions are validated before commit.

A stroke supplies `gradient`, `start` and `end`, with points containing `x` and `y`. Optional controls are `style`, `reverse`, `dither`, `transparency`, `opacity`, `mode` and `mask`. Defaults are Linear, false, true, true, 1, Normal and false respectively. Existing Core selection, lock, geometry, channel-storage and admission rules apply. Missing layers return 404; invalid, locked or unsupported targets reject without a partial document edit. The target requires a pixel mask when `mask:true`.

Creation and painting each commit through the existing prepared Undo path. Captured native drag, delayed preset and colour-stop operations reject replaced or changed sources. Portable Actions format 51 records fresh fill recipes and captured Classic strokes without persisting document UUIDs or raster snapshots. Fill templates containing additional unsupported metadata remain explicitly unsupported. Older operation payloads retain their minimum versions; headers 1–50 reject the new operations.

The typed catalogue has 255 commands. Native document archive 86, settings archive 4, workspace state 1 and panel catalogue 3 remain unchanged. This is a Photato API extension. No Adobe route or unqualified `actionJSON` operation was added to the pinned Photoshop v2 contract.

All 69 selected Debug methods pass, including eleven new methods. The same 99 optimized methods run on each architecture: 99 pass on Apple Silicon and 98 under Rosetta. All eleven new methods pass both. The remaining Intel Rust interpolation assertion reproduces exactly on the preserved checkpoint 441 binary; it is retained, not repaired or waived. Universal macOS 14 packaging, signature and extracted ZIP verify. [Evidence](GRADIENT_CREATION_442.json). Tests include native/API document and archive equality across RGB8/16/32, all five Classic shapes and pixel/mask targets, source guards, history, configuration, portable recording and older Actions workflows.

The complete A05 package remains open. Outstanding work includes canvas opacity controls, complete preset/noise/GRD behavior, remaining interpolation/dither/default and fill-transform behavior, larger-document performance, independent Photoshop output comparisons and physical-platform qualification. Existing wider-suite failures remain recorded separately.
