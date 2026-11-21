# Isolate a path’s layer while editing

Double-click a selected shape path or vector mask with either path selection tool to isolate its layer in the Layers and Paths panels. Double-click away from the path, turn off layer filtering, or choose another filter to exit.

Select a shape path or vector mask in the Paths panel, then use Path Selection or Direct Selection on the canvas.
In isolation, the Layers panel shows the owner and the Paths panel shows that layer’s shape and mask paths, where available.
Select > Isolate Layers also exits the mode. Removing the focused path or explicitly selecting a path on another layer ends isolation.

In the owned fixtures, isolation left the composite, PSD and PSB bytes, and Undo history unchanged. Restoring focus to the owner also leaves an active Actions recording untouched. All 12 earlier whole-layer vector-mask outputs also matched byte for byte. A saved path belongs to the document and remains available in the Paths panel outside isolation.

The Photato API command `paths.isolate` accepts a boolean `enabled` and reports `available`, `active` and `layerID`
under `pathIsolation` in the document state. The command uses the editor’s current path focus.

All 225 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison and physical Intel and macOS 14 testing remain open. [Adobe path selection reference](https://helpx.adobe.com/photoshop/desktop/draw-shapes-paths/create-shapes/select-paths-and-path-segments.html) · [Qualification](SOURCE_PUBLICATION_677.md).
