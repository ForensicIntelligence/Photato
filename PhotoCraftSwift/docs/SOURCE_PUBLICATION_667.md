# Source checkpoint 667

Native Swift 0.3.0, build 667, 20 November 2026.

PSD and PSB now reopen supported Smart Object Warp presets, cubic meshes and nonuniform split grids as editable settings. Relinking a missing original restores its live Warp.

1,537 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

Five new tests covered PSD and PSB presets and split Warp, missing originals, stored masks, native workspace editing and API export. The public Photoshop fixture retained eleven Warp descriptors, four split grids, original bytes and cached appearance across both containers.

The installed Photoshop document query timed out. Unchanged saved samples and Photato-regenerated pixels were checked separately. An independent reader compared the encoded merged image planes in both outputs against Photoshop’s stored preview. In each format, 24 of 1,048,576 component bytes differ by one level, including three alpha bytes. Live Photoshop rerendering, Cylinder, PDF Warp and pre-Warp reconstruction of saved pixel masks remain open.

[Development record](EDITABLE_SMART_OBJECT_WARP_667.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_667.json)
