# Source checkpoint 733

Photato opens supported Photoshop Vanishing Point grids as editable planes. A connected grid stays attached to its parent edge. PSD and PSB retain the original plane record byte for byte when an edit changes only the pixels.

The owned Photoshop 27.2.0 files cover an oblique plane with a thin hinged child and two independent planes. The native tests reopen both relations, preserve the original records and verify that moving the parent updates the joined plane. The authenticated API returns and replays the measured settings, applies a Brush stroke, downloads PSD and PSB, and undoes the edit.

Photoshop displayed both grids in Photato’s new two-plane PSD. Its Vanishing Point filter also opened the matching PSB and displayed the moved parent grid from a second PSD.

835 of 837 selected tests passed on each optimized architecture. Both new tests passed on Apple Silicon and under Rosetta. The two inherited layer-effect and color-profile cases still fail. The color-profile outputs match build 732 byte for byte. Xcode built the Debug app and passed all 19 focused tests. Each of the three generated test files is byte-identical across Debug and both optimized slices. Both slices of the local macOS 14+ preview opened offscreen.

Exact-parallel Photoshop export, grid settings and measurement tools still need work. A diagnostic exact-parallel grid opened with distorted geometry. The original Heal Off crop comparison and full retouch workflow acceptance remain open. Photato keeps unsupported perspective resources as file metadata and reports a conflict before replacing one. [Adobe’s Photoshop file-format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

Build inputs **9,424**. Source digest `0a767ce060280076ef1813becf36d9882440dbc1d0bef0c1043f8b7a9aa4aaf4`. Local universal preview SHA-256 `a3a28712e08f42a70fab9cdd8a33698f8286cb3cb73fd5f28f9fe0273490d0be`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-733) · [Evidence hashes](SOURCE_PUBLICATION_733.json)
