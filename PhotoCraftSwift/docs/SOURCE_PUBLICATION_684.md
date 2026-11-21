# Source checkpoint 684

Native Swift 0.3.0, build 684, 2026-11-20.

Supported RGB8 and RGB16 PSD and PSB shape layers keep their embedded pattern fills and strokes editable. Arrowless straight lines retain their endpoints and weight.

All 302 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The original Photoshop fixture opens with all five shape layers editable. Both resaves preserve the six layer caches, live shape descriptors and both embedded pattern records byte for byte. An independent reader verified an edited polygon phase, a rounded rectangle’s 85% stroke scale and a diagonal line’s 4.5 px weight. The line kept its endpoints. Both edited files matched byte for byte across all three builds.

The regenerated merged preview differs in 331 color-channel bytes across 224 antialiased pixels, with a maximum difference of 1 in RGB and exact alpha. The 56% polygon pattern sample supports a document-origin phase. Its scaled sampling still differs. The 60° gradient diagnostic did not establish a universal half-pixel placement correction. Arrowheads and live Photoshop 2026 reopen and repaint checks remain open.

[Development record](EDITABLE_SHAPE_PATTERNS_684.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_684.json)
