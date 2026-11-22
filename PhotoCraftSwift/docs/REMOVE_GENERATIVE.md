# Generative Remove

Choose the **Remove** brush from the J tool group. In the options bar, open the processing menu beside **Mode** and choose the compiled LaMa512 model. The same local model is used by Generative Fill. The device route requires Apple Silicon with macOS 26 or later. [Model setup](LOCAL_GENERATIVE_FILL.md)

- **Auto (May use generative AI)** uses the local model for eligible still RGB documents when one is configured. Other eligible Remove edits use the traditional repair.
- **Generative AI on** uses the local model. If the model or document cannot run it, the edit stops with an error and leaves the source intact.
- **Generative AI off** uses the traditional repair.

Brush over an area or draw a loop to cover its interior. When the stroke runs between adjacent edges of the canvas, the overlay includes the corner it encloses. Use Add or Subtract to refine it. Hold Option for the other brush mode. Turn off **Remove after each stroke** to mark several areas before applying. Press Return or use Apply to commit, or press Escape to clear the marks. Reviewed People and General distractions also use the chosen mode when applied.

**Sample All Layers** uses the visible image as the fill source. With it off, Remove samples the selected raster. **Create New Layer** keeps the original layer and writes a transparent correction. The current selection limits which pixels can change. A successful multi-region batch takes one Undo.

Distant small marks are prepared independently. Large connected marks use overlapping regions, and the correction combines the predictions where they overlap. The local path supports sparse documents within the 300,000-pixel canvas dimensions. A batch can contain up to 64 local repair regions. Traditional Remove retains its 16-megapixel canvas limit. A tightly marked image with little surrounding material can give a soft result or require a smaller batch. Wires and cables uses its separate traditional workflow from Auto or Off.

Photoshop also offers a cloud provider. Photato’s device option uses LaMa512. Exact comparison with Adobe’s model output remains open. [Adobe Remove modes and workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/remove-unwanted-objects-and-distractions.html)

## Photato API

Send `retouch.remove` to the authenticated shared document command route with a current revision. For a complete set of brush marks, pass these parameters.

```json
{"operation":"execute","settings":{"mode":"generativeOn","size":10},"strokes":[{"points":[[40,50],[45,55]]}]}
```

`retouch.remove` also accepts `configure`, `stroke`, `preview`, and `apply` for staged work. `generativeAvailable` indicates whether a local model can run on the active document. `resolvedProcessing` can report `traditional`, `localFillWhenEligible`, `localFill`, or `unavailable`. Choose the local model in the editor. An explicit On request without the model receives HTTP 422. The raw mark preview remains bounded to 16 megapixels and requires transfer permission. Large-document editing uses the standard shared document limits.

The published Firefly Photoshop v2 schema has no dedicated equivalent route. The Execute Actions descriptor remains unqualified. [Automation API](AUTOMATION_API.md) · [Adobe API reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/)
