<a id="dev-step-543"></a>

## 2026-11-17 — Reuse exact gradient samples and publish tiles

The build 542 benchmark exposed repeated nonlinear ramp evaluations at the same Float32 coordinates and per-pixel canvas storage writes. A standalone probe against the optimized engine compared scalar writes, tile writes and tile writes with sample reuse. All nine scenarios produced identical bytes. The axis-aligned cases reused more than 99% of the evaluated coordinates. Tile writes improved the rotated case even though it had few repeated coordinates.

Gradient.swift adds a render-local sampler keyed by the complete Float32 parameter word. Each sampler owns one ramp. GradientRasterizer.swift, GradientFillRenderer.swift, Renderer.swift and GradientPaint.swift reuse these samples in bulk paths. Dither still runs after lookup in document coordinates. Rasterization and ordinary Gradient Fill composition publish one tile at a time through the existing Surface writer. GradientMap.swift prepares an immutable table of the existing 4,097 coordinates for bulk RGB8 and RGB16 maps and keeps the Classic RGB16 transfer and continuous Float32 behavior. Renderer.swift and PixelCommandEngine.swift supply a sample-count estimate when preparing the shared spatial evaluator.

GradientRasterizerTests.swift compares the large and offset path with the independent scalar write loop. GradientMapTests.swift checks table output against scalar output through every grid position, every interpolation method and both Reverse settings. The native and API entry points keep their existing options, schemas, masks, history and depth rules.

The optimized builds reproduced all 84 outputs from 542, byte for byte on both architectures. The separate tone-grid proof found zero differences across 196,656 samples per architecture. All 372 selected tests passed in Debug and both optimized configurations. The universal archive passed static checks and offscreen workspace rendering on both architectures.

On Apple Silicon at 2,048 × 2,048, Linear rasterization went from 314 to 48 ms and Perceptual from 351 to 49 ms. The rotated Perceptual case went from 361 to 273 ms, and Perceptual Gradient Fill composition from 586 to 261 ms. Perceptual Gradient Map composition went from 522 to 245 ms and its direct command from 472 to 183 ms. The three saved Photoshop Gradient Map differences and physical editing cadence remain open. [Qualification](SOURCE_PUBLICATION_543.md).
