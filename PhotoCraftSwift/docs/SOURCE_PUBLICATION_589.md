# Source checkpoint 589

Native Swift 0.3.0, build 589, 19 November 2026. Merge Clipping Mask, Stamp Group, and eligible Merge Down and Stamp Down commands now use Feather on contributing raster clips. [Adobe merge and stamp behavior](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/merge-and-stamp-layers.html).

Five RGB32 references at 250 or 1,000 px match exactly in the editable raster channels on both reference architectures. The source PSDs were authored by Photato. Photoshop 27.2.0 on the development Mac saved the input and result of each command. Its bundle has an ad-hoc signature. An independent stored-channel comparison examined 20,085 samples per configuration across eleven cases including partial opacity. Apple Silicon matched all samples. Intel differed at 230 samples, by at most two Float32 steps.

All 856 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal slices passed offscreen checks, and the archive declares macOS 14 as its minimum. The two maximum-size sparse cases include distant mask tiles and a small raster clip with 1,000 px Feather. The HTTP tests exercise the shared merge and job paths as well as Undo.

Lower depths, fractional and affine masks, adjacent masked clips, dense wide-mask performance and physical Intel and macOS 14 validation remain open.

[Developer record](DEVLOG.md#dev-step-589) · [Validation data and source fingerprints](FEATHERED_CLIPPING_589.json).
