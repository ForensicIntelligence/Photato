# Linked perspective Smart Objects

1. Audit the PSD linked-file record, the native saved preview, and the desktop and API paths that relink or refresh artwork. Adobe documents external-source placement, perspective editing and recovery through Relink to File. Use owned artwork for test files. [Smart Objects](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/smart-objects/smart-objects-overview-and-benefits.html) · [Update and relink](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/smart-objects/update-linked-smart-objects.html)
2. Retain the original source-to-preview perspective mapping alongside the baked layer pixels. Older linked previews still use their affine placement. Read PSD and PSB source locators as metadata. Reuse both saved corner arrays when the imported frame has not moved.
3. Use the existing Free Transform frame and native source authorization. A missing original can be moved, rotated, scaled or skewed as a preview. The Skew gesture applies an affine shear around the opposite edge midpoint. Relinking restores Distort access, keeps the source mapping and leaves existing mask placement and shared instances intact. The Photato document API and Adobe manifest report original artwork corners.
4. Exercise source absence, PSD and PSB reopen, exact corner words on untouched re-export, visible pixel comparisons, native archive, multi-instance relink, desktop history and API state.

Live Photoshop output, PDF perspective, editable Warp descriptors and Photoshop's sampling across the full range of source sizes remain separate checks.

## Validation

1,511 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

Four new tests covered the native Free Transform and Relink workflows, shared instances, masks, Smart Filters, Undo, exact saved corner words and the Photato and Adobe-compatible API views. An independent reader checked eight PSD and PSB outputs and verified that each external-link record omits original image bytes.

[Qualification](SOURCE_PUBLICATION_666.md)
