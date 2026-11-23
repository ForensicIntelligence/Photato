# Retouch on an empty correction layer

1. Add a pixel layer above the image and select it as your correction layer.
2. Select Healing Brush or Clone Stamp and set Sample to **Current & Below**.
3. Option-click a suitable source and paint over the repair area. For Healing Brush, choose nearby texture with a similar direction and fine detail. For Clone Stamp, also match color and lighting.
4. Release the brush to commit one Undo. The original pixels remain in the sampled layer. Keep the correction layer in the native archive for later edits.

Photato can reuse the raw canvas render when it matches the exact sampled document, including the layer cutoff and any adjustment exclusions. The editor and the authenticated `retouch.stroke` operation share the same sampling checks.

The portrait benchmark applies both tools to the same three defects. Healing reduced the local pixel error at all three sites. Two of the tested Clone Stamp sources were a poor match. The preview and committed pixels matched in the tested operations. Source preparation timings measure software work and physical display cadence remains a separate test.

[Photato automation guide](AUTOMATION_API.md) · [Adobe Healing Brush workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/clean-restore-images/healing-brush-tool.html)

## Sample depth conversion

When a bounded sRGB source needs an 8-bit or 16-bit sample, Photato converts just the stored tiles. The editor and authenticated API use the same conversion and preserve the existing sample values. [Build 725 measurements](SOURCE_PUBLICATION_725.md).
