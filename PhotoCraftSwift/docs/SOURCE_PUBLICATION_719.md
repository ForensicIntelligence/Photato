# Source checkpoint 719

The Remove processing menu can find shadows and reflections around a marked object using two optional models on Apple Silicon with macOS 26 or later. The canvas shows the reviewed object and each enabled effect. Use the checkboxes or the Add and Subtract brush to refine coverage. Apply creates a correction layer with one Undo. The Photato API shares the same review and edit.

Two licensed photos checked a waste-bin shadow and a vehicle reflection. The first masks left a dark silhouette in each photo. Testing wider masks showed how much overlap was needed and where the review started to touch an unrelated effect. The smaller final margins removed the silhouettes and left the designated neighboring areas and all pixels outside the edit exact. The editor and authenticated API returned equal review masks and rendered RGBA8 bytes on both photos in each Apple Silicon configuration. One Undo restored each original document exactly. The repaired PNGs also match byte for byte across those two configurations.

586 of 587 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The new native/API regression passed in each configuration. The existing PSD layer-effect test repeated the same 118 differences. The checked-in Xcode project built successfully. Both signed preview slices target macOS 14.0 and opened offscreen. The optimized Intel build rejected the optional local models and completed a traditional Remove edit under Rosetta.

The vehicle photo also suggested a shadow. The test deselected it before applying. Some grass texture remains soft and the repaired water shows slight color artifacts. Footprints, smoke, steam, water wakes, Adobe’s separate Enhance action and live Photoshop output comparisons remain open. Adobe documents a cloud provider for this feature. The optional Photato models run locally. The installed Photoshop 27.2.0 returned its version and exposed zero accessible windows and menu bars.

Build inputs **9,418**. Source digest `25df12649f76fb3e0c6f7210b3ecaa38a63c52da5ea98f330bc9dd1d9b2b970a`. Local universal preview SHA-256 `1fa437c763d4f3cf8c0ae881047b58fd0b9ac09210f0532b6ef7aa29beca88c8`.

[Related Elements guide](REMOVE_RELATED_ELEMENTS.md) · [Development log](DEVLOG.md#dev-step-719) · [Evidence hashes](SOURCE_PUBLICATION_719.json)
