# Editable photo blending

Select aligned pixel layers and choose Edit → Auto-Blend Layers. Panorama blends overlapping photographs; Stack Images selects sharp regions. Seamless Tones and Colors applies the existing multiband correction to contributing source pixels. The photographs keep their names, placement, alpha and editable masks. Pixels outside the processed canvas stay unchanged.

With transparent-area fill off, no merged layer is added. This also works at the existing 8,000-layer document limit. Enabling fill adds a layer named after the active source with “(merged)” appended. Opaque masked sources remain visible. Partial coverage still uses the previous hidden-source fallback to prevent doubled alpha; Photoshop's translucent behavior remains unqualified.

Photomerge uses the same result assembly and keeps the source photograph names. Original input documents are unchanged. Preview, Cancel, commit, Undo/Redo and existing native/PSD persistence use the shared prepared transaction.

`photo.autoBlend` retains its existing `layerIDs` and `settings` schema. `document.photomerge` retains its source/revision grants and new-document response. Both report the changed behavior in capability metadata. The existing panorama `mergeAlignedLayers` descriptor uses the same engine through both Adobe-compatible action-job interfaces. No new Adobe route or Stack Images descriptor is claimed.

The independently owned RGB8 Photoshop reference confirms the opaque layer structure, not algorithmic pixel equality. The 24 frozen native programs are regression evidence. Exact proprietary masks/colors, large blend capacity, translucent fill and broader platform/performance qualification remain open. [Build514 evidence](EDITABLE_PHOTO_BLEND_514.json).
