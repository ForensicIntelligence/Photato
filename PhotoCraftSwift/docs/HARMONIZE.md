# Harmonize

Place a subject on a regular pixel layer above the background. Remove Background or add a mask when needed. With the subject selected, choose **Harmonize** in the contextual bar, the Layer menu, or Properties.

Photato creates a group containing a copy of the subject, editable Curves, and contact shadows. The original subject layer is retained and hidden. Choose **Subtle**, **Balanced**, or **Ambient** in Properties. The group and the variation switch each have their own Undo step. Adjust the curve or shadow layer directly to refine the fit.

The local calculation samples the visible subject and nearby background in document coordinates. It estimates colour and contrast changes from the sampled pixels and projects a soft shadow from the subject’s lower edge. The result includes the original cutout geometry. The calculation runs on macOS 14 or later without a downloaded model.

Use an ordinary, visible RGB subject layer at the document root. If the subject came from Place Embedded, rasterize a duplicate first. Clipping stacks, layer effects on the selected subject, and video layers are outside the current workflow. Photato’s local results have not been matched to Firefly. [Adobe Harmonize workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/blend-subjects-with-harmonize.html) · [Photato automation](AUTOMATION_API.md#harmonize)
