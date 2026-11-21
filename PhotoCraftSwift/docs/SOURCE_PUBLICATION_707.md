# Source checkpoint 707

Native Swift 0.3.0, build 707, 2026-11-21.

Prompted Generative Expand now keeps one isolated worker and loaded model for all windows and alternatives in an edit. Cancel still aborts the edit and removes its temporary files. The desktop and Photato HTTP commands use the same worker.

A paired four-request Core ML benchmark used 89.9 seconds with fresh workers and 80.9 seconds with one reusable worker. All four Float32 RGBA buffers matched exactly. A signed App Sandbox harness reproduced all four buffers. A separate 4,104-pixel-wide two-alternative run took 547.8 seconds and reproduced both build 706 alternatives and the editable mask byte for byte after reopening. A cancellation test forced a non-cooperative test child to exit and verified scratch cleanup.

496 of 497 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 706. Xcode built the app in arm64 Debug. Both signed preview slices opened offscreen.

Generation still takes time for large borders. Prompt quality across distant windows, saved tiled context for Generate More and Generate Similar, and Adobe Firefly output equivalence remain open.

[Model setup](LOCAL_GENERATIVE_FILL.md#extend-the-canvas) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_707.json)
