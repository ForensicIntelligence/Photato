# Source checkpoint 662

Native Swift 0.3.0, build 662, 20 November 2026.

Fit or fill replacement artwork inside an existing embedded Smart Object frame. The new ingredient remains editable as a nested Smart Object, including artwork outside the visible frame. Both the Photato and Adobe-compatible APIs expose content placement.

All 1,493 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

Both authenticated local HTTP routes exercised frame-contained replacement. The native, PSD and PSB round trips kept the nested asset and the rotation of the enclosing frame. The tests retained exact source asset bytes and verified local composite bytes, transparent clipping, editable masks and one Undo for the Photato command.

The installed Photoshop did not respond to read-only AppleEvent or Accessibility window checks. Independent Adobe output and the hosted service remain unverified. Intel ran under Rosetta and the signed binaries declare macOS 14.0.

[Development record](SMART_OBJECT_CONTENT_PLACEMENT_662.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_662.json)
