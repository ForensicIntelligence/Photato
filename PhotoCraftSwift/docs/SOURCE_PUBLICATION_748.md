# Source checkpoint 748

Vanishing Point selects Marquee after clipboard paste. Press T to show scale and rotation handles and the Flip and Flop controls. Shift constrains scale or movement and snaps rotation. Option centers the resize or duplicates a moved paste. Finishing a gesture adds one workspace Undo.

The authenticated Photato API exposes the same rotation and Flip and Flop. Set `pasteHeight` to size a pasted image independently of its width. Omitting height preserves the source aspect ratio and older request behavior.

All 60 focused Debug tests passed. Each optimized build passed 874 of 876 selected tests, including the three new cases. Intel ran under Rosetta. The same two inherited failures repeated their diagnostics. Four replay PNGs matched byte for byte across Debug and both optimized builds.

The comparison used a 96 × 48 Photoshop Flip and a Photato replay aligned to the same pixel origin and size on a synthetic front-facing plane. Of 4,608 pixels in the patch, 1,789 matched and 2,819 differed. Photato preserved every pixel outside the patch. The Photoshop capture stayed at its upper-left paste origin. A second Flip reproduced the same Adobe RGB raster. Opening Transform with both reflection controls off kept the ordinary Adobe paste unchanged. Free canvas placement, side handles, and Photoshop’s on-plane raster and rotation behavior need separate checks. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/uk/photoshop/using/vanishing-point.html).

The extracted Universal app passed signature verification and offscreen launches on both architectures. The macOS 14+ ZIP is 77,781,956 bytes with SHA-256 `254a4e5c16a058ce0bce65094a2555fe96b05568ec749760a2e3c4d4935f71f0`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_748.json) · [Development record](DEVLOG.md#dev-step-748) · [API](AUTOMATION_API.md#vanishing-point-paste-transforms).
