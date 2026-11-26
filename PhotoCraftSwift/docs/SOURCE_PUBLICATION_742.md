# Source checkpoint 742

Vanishing Point floating selections use bicubic sampling through the desktop editor and the authenticated Photato API. On separate Photoshop captures with synthetic stripes and dots, the donor shows the overshoot and undershoot expected from cubic interpolation. Photato uses its existing native sampler.

On the owned left-to-right two-wall capture, mean absolute RGB channel error across the changed region fell from 3.32 to 2.16 levels. In the donor interior it fell from 2.14 to 0.81. All five tested patches had lower mean error over their full changed region. The small receiving region on the left-to-right impulse capture rose from 7.20 to 7.48 levels. Exact channel values, hinge placement and boundary coverage remain open.

The checked-in Xcode project built and passed all 27 focused Core tests and 17 App and HTTP tests. A new test checks the four cubic taps for a half-pixel move. The authenticated API and native workspace produce the same subpixel edit with one document Undo.

Both optimized architectures passed 858 of 860 selected tests. The inherited color-profile and layer-effect tests repeated the same diagnostics as build 741. All five native replay PNGs match byte for byte across Xcode Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed preview target macOS 14 and opened offscreen on macOS 27.2.1.

Build inputs **9,429**. Source digest `be73aa96e808b5d7709946f26f184e94cb416cbbad31991ad7d13670b5936e5e`. Local preview SHA-256 `9fcb9cbd5a5935ac6c830f456bdc21e8fe181fab87698c9bd1ad496d226a3213`.

[Development record](DEVLOG.md#dev-step-742) · [Evidence hashes](SOURCE_PUBLICATION_742.json) · [Photoshop reference observations](VANISHING_POINT_REFERENCES.json).
