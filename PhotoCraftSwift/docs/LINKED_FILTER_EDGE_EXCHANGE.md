# Relink a projected Smart Object

Keep the linked original beside a client document while working. If the original is moved, the reopened PSD or PSB can display its saved preview. Select the Smart Object and choose Layer → Smart Objects → Relink to File. Select the relocated original. The Photato API offers `smartObject.linked.relink` for a locally authorized asset and its current fingerprint.

When the new location contains the same source bytes, the tested projected Smart Object keeps its appearance while restoring editable source content. The placement, ordered Smart Filters and their mask stay attached to the layer. A subsequent Smart Filter mask stroke can be edited without changing the ordinary layer mask. Undo restores each operation separately.

A projected pixel with its center exactly on a trailing source edge is outside the image. Photato applies this rule consistently in its paged rendering and coordinate mapping to prevent equivalent projected corners in a saved file from changing the sample at that edge.

The test fixture uses one projected linked PSB with Gaussian Blur, High Pass and a painted Smart Filter mask. Photato compares its own reopened renders at RGB8, RGB16 and RGB32. Changing the source contents can change the render. Direct Photoshop rendering remains a separate comparison.

[Photoshop’s linked-source workflow](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/smart-objects/package-linked-smart-objects.html) · [Photoshop’s Smart Filters documentation](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/apply-and-manage-smart-filters.html)
