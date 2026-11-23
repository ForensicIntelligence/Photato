# Recover transparency in Select and Mask

Make a rough selection around the subject. Keep a little background outside the selection, then open **Select and Mask** with Option-Command-R. In **Transparency**, enable **Recover Transparency**.

- **Estimate Smooth Background** uses visible samples around the selection. It works with solid colors and gentle gradients.
- For a textured backdrop, add an aligned photo of the empty background as a separate pixel layer and choose that layer in **Background**. Keep the camera, backdrop and exposure consistent between photos. You can hide the reference layer when isolating the subject.

Check the result in **On Black** and **On White**. Use **Erase Refinement** where a subject detail needs its original opacity. Enable **Decontaminate Colors** to remove the estimated background contribution from the output colors. Choose **New Layer with Layer Mask** to keep editing the mask in this document or **New Document with Layer Mask** to isolate the result before exporting a transparent PNG.

The transparency option runs in native Swift. It works with RGB8, RGB16 and RGB32 documents within the current Select and Mask canvas and layer limits. It uses the active image layer, including rendered Smart Object content where the existing refinement workflow supports that content. The solver skips source pixels with partial opacity. The output mask combines with the layer’s existing transparency. Keep any visible document background hidden for transparent export.

For a simple background, the solver fits an affine surface to unselected pixels and estimates opacity from the color difference between the capture and the backing. With a reference layer, it can also estimate local transmission from changes in the reference texture. It favors the original color solution when the subject texture makes those changes ambiguous. Decontaminate Colors uses the recovered coverage to remove the backing color. Neither approach resolves arbitrary refraction. Complex single-image backgrounds, missing foreground detail and the exact Adobe Color Aware and Object Aware behavior remain open. [Adobe Select and Mask](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/refine-your-selection-and-mask.html) · [Adobe fringe removal](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/fringe-pixels-around-a-selection.html)

## Local API

Use the existing authenticated `selection.refine` operation, the image layer ID and the current shared-document revision. Send `settings.transparency: {}` for a smooth background, or supply the UUID of the aligned pixel layer as `settings.transparency.backgroundLayerID`. Use `settings.decontaminate: true` to remove the backing color. This mode uses the selected layer and requires `sampleAllLayers` to be false. The published Photoshop v2 contract has no dedicated route for this workspace. [Photato API](AUTOMATION_API.md) · [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/getting-started/v2-ga/)
