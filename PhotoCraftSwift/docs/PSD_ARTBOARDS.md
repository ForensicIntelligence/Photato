# Editable PSD and PSB artboards

File → Open now imports qualified RGB PSD/PSB artboards as editable top-level native groups. Bounds, negative logical positions, backgrounds, presets, child pixels and board-scoped guides remain editable. File → Save As → PSD or PSB writes active geometry and guide ownership. Save as Photato to retain contexts outside the admitted Photoshop mapping.

White, black, transparent and opaque SDR custom backgrounds are mapped at RGB8, RGB16 and RGB32. The imported document origin stays separate from physical pixel coordinates. Scoped guides retain their board-relative position and are not duplicated as canvas guides. Editing, duplicating, extracting or removing board metadata regenerates active descriptors. Unchanged admitted descriptor bytes, including padding and document switches, are preserved. Empty boards remain editable.

Select the Artboard tool from the Move tool group and use its Properties dialog. Existing native history, cancel and Save As/reopen behavior is unchanged. The regular Properties panel still presents a generic group.

The optional Photato API uses existing permissioned PSD/PSB document import, artboard.edit, history and document.download operations. Both resource-job interfaces use the same codec and native editing engine. No Adobe route or input type was invented. Existing published artboard creation remains separate. Capability metadata describes interchange, guide precision and restrictions. Native format 92, Actions 60 and 271 typed commands are unchanged.

Unsupported descriptor fields, nested or clipped boards, non-RGB boards, fractional board geometry, partial-alpha/HDR backgrounds and shared/missing guide contexts reject explicitly. PSD/PSB guide positions use 1/32 pixel precision. TIFF board interchange remains unqualified. Full I04/L07, broad Photoshop defaults/output, prior numerical failures, physical platforms and 60 fps remain open.

Owned Photoshop 2026 RGB8/16/32 PSD and PSB fixtures have independently extracted merged-plane references. Every reference byte matches in Debug and both optimized configurations. The actual 300,000 × 1 preview and PSB round trip verify maximum width, not a dense 90-gigapixel document. [Build 516 evidence](PSD_ARTBOARDS_516.json).
