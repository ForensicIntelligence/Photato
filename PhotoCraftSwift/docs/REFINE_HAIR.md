# Refine hair in Select and Mask

1. Start with a rough selection or an existing layer mask. You can also use Select Subject in the workspace.
2. Click **Refine Hair**. Photato estimates soft coverage near the subject boundary and removes new isolated patches.
3. Inspect the result on black and white. Use the Refine Edge Brush, the subtracting brush, or the edge sliders for local corrections. **Undo** restores the earlier selection within the sheet.
4. Choose **Layer Mask** to keep the result editable. **Decontaminate Colors** can reduce remaining color spill and creates a new layer with a mask when the original output would replace the selection or mask.

For automation, set `settings.refineHair` to `true` in the Photato `selection.refine` command. The starting selection or layer mask is refined before any requested strokes and global edge settings. The same single document Undo restores the input. [Automation API](AUTOMATION_API.md)

Refine Hair runs locally on the selection and its color guide. It helps recover nearby strands. A very busy background can leave visible fringes, and strands far from the rough selection or obscured by similar colors may need manual correction.

[Adobe’s Refine Hair workflow](https://helpx.adobe.com/photoshop/desktop/make-selections/automatic-color-based-selections/make-improved-hair-selections.html)
