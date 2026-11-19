# Source checkpoint 602

Native Swift 0.3.0, build 602, 19 November 2026. Dense feathered vector masks skip scratch rasterization for solid interior and exterior pieces and filter their coverage from the existing piece grid.

Ten mask controls matched build 601 across all 10,873,881 Float32 coverage words per architecture. Two additional whole-canvas RGB32 layer stacks matched all 28,706,520 RGBA words per architecture. The controls cover both mask polarities, short and wide Feather through 1,000 px, Boolean holes, partial cells, and near-edge viewports on a 300,000 × 300,000 document.

At 1,000 px Feather, the interior viewport of the maximum-size document needed no scratch transfer, down from 51,595,425 source pixels. The whole 49,155 × 73 wide-Feather control transferred 18,434,046 source pixels, down from 36,890,622.

Whole-mask preparation for the 300,000 × 300,000 control at 110.25 px Feather took 10.39 s on Apple Silicon and 14.14 s under Rosetta. The four checked regions matched all 42,286 coverage words against build 601 viewport output on each architecture. These measurements are single runs on the same Mac.

All 920 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The installed Photoshop app timed out on a read-only document count. Fresh Photoshop outputs, practical full-canvas compositing of maximum-size dense masks, physical Intel and macOS 14 runtime checks, and full Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-602) · [Validation data](DENSE_VECTOR_SUPPORT_602.json).
