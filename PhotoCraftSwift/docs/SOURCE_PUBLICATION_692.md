# Source checkpoint 692

Native Swift 0.3.0, build 692, 2026-11-21.

Fit on Screen and the local PNG overview reduce supported wide oblique Pattern Overlays without retaining the full composite.

Fractional edges matched retained rendering at RGB8, RGB16 and RGB32 in the tested composite, channel and proof views. The proof test also preserved a sparse implicit backdrop across the maximum canvas. Authenticated composite, channel and proof PNGs matched their retained native controls. The separate AppKit probe fitted and proofed a fully covered 70,000 × 520 document on both architectures.

458 of 461 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 691's assertions. Both signed macOS 14+ preview slices launched offscreen.

Large nonperiodic fits still evaluate source pixels and can take seconds or longer. End-to-end timing for a fully covered maximum-size oblique Fit remains open. The Photoshop 2026 document-count query timed out, leaving live zoom comparison open.

[Development record](PAGED_PATTERN_REDUCTION_692.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_692.json)
