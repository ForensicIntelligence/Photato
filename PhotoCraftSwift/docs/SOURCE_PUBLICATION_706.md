# Source checkpoint 706

Native Swift 0.3.0, build 706, 2026-11-21.

Generative Expand now processes wider and deeper borders in overlapping model windows. The Crop tool and Photato API use the same engine and apply the expansion as one Undo step. Multiple prompted results share an editable mask and appear as layer comps in one embedded PSB.

LaMa preserved all 720,896 original pixels on a 5,632 × 128 source and added 225,280 pixels. The mean step at the model-window joins was 0.47 RGB8 levels. A real 30,144-pixel-wide outpaint preserved 482,304 original pixels and reopened with identical composite bytes in the native format and PSB. A separate 300,000 × 16 outpaint added eight rows at Photoshop’s published maximum canvas width, preserving all 4,800,000 originals through native and PSB reopening. The native Crop action and HTTP produced identical pixels on a separate 4,160-pixel-wide run. Both prompted alternatives on the real 4,104-pixel-wide input stayed distinct and editable after native and PSB reopening. A deterministic deep four-sided test covered editable PSD/PSB alternatives, joined pixels and interior transparency. A separate PSB test retained exact RGB16 and RGB32 sample words.

495 of 496 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The existing PhotoCraft layer-effect test repeated its 118 assertions from build 705 in each configuration. The Xcode project built in arm64 Debug. Both signed preview slices opened offscreen.

Tiled alternatives retain their results and mask for editing. Generate More and Generate Similar after reopening still require the single-patch saved context. The two-alternative prompt proof took 572 seconds with other qualification jobs running. Reusing the prompted worker between windows remains a performance task. Dense maximum-area generation, prompted quality across distant windows and Firefly output equivalence remain open.

[Model setup](LOCAL_GENERATIVE_FILL.md#extend-the-canvas) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_706.json)
