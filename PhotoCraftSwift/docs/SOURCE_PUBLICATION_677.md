# Source checkpoint 677

Native Swift 0.3.0, build 677, 20 November 2026.

Double-click a selected shape path or vector mask with either path selection tool to isolate its layer in the Layers and Paths panels. Double-click away from the path, turn off layer filtering, or choose another filter to exit.

All 225 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

In the owned fixtures, isolation left the composite, PSD and PSB bytes, and Undo history unchanged. Restoring focus to the owner also leaves an active Actions recording untouched. All 12 earlier whole-layer vector-mask outputs also matched byte for byte. A saved path belongs to the document and remains available in the Paths panel outside isolation.

The first Debug run surfaced a discovery test that still expected exactly 267 commands. It also failed on public build 676, whose registry had 280. The test now verifies that the server advertises exactly the typed registry.

Live Photoshop comparison and physical Intel and macOS 14 testing remain open.

[Development record](PATH_ISOLATION_677.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_677.json)
