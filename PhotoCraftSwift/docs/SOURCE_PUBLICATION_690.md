# Source checkpoint 690

Native Swift 0.3.0, build 690, 2026-11-21.

Rotated and nonperiodic Pattern Overlay renders in bounded document viewports on canvases up to 300,000 × 300,000.

At actual size, overlapping panned views matched at 8-, 16-, and 32-bit depth. A 31° pattern at 56% matched the ordinary renderer at actual size, at fractional zoom and above the direct in-memory patch limit. The native canvas and all three local PNG viewport routes produced identical PNGs in the tested RGB8 composite, channel and proof views. Eighteen samples from the saved Adobe Photoshop PSD also matched.

453 of 456 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The same three failures reproduced the build 689 assertions. Both signed macOS 14+ preview slices launched offscreen.

Fit-to-window on very large nonperiodic canvases still uses full rendering. The bounded route has a source budget of 16,777,216 pixels and an output budget of 4,194,304 pixels. Photoshop’s document-count query timed out, so direct comparison of live zoom presentation remains open.

[Development record](PATTERN_VIEWPORT_690.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_690.json)
