# Source checkpoint 738

Vanishing Point adds a perspective Marquee for creating, moving, copying and filling selections. A selection can float as a sampled patch and be repositioned, scaled or rotated. The Marquee stays separate from the document selection. Undo, protected pixels and app/API parity were tested on the same prepared edit. The native tool picker now fits the sheet without overlapping the inspector.

The Xcode Debug build passed 23 Core tests and 12 focused App and HTTP tests. The light and dark workspace renders show the selection outline and sampled patch.

On an owned 1,200 × 900 grid, Photoshop floated the full plane, moved it 20 pixels right and 10 down, and saved a PSD. Photato replayed the same movement. The untouched top and left strips matched. Within the translated area, Photoshop still differs in eight-bit rounding and in its feathered edge. The comparison counted 846,342 differing RGB pixel positions. A selection that wraps across a hinge and a live comparison of Source-mode dragging remain open.

Both Photato replays produced byte-identical PNGs in Debug, optimized Apple Silicon and optimized Intel under Rosetta. The signed preview opened offscreen on macOS 27.2.1. Both slices target macOS 14.0.

Both optimized architectures passed 850 of 852 selected tests, including all three new cases. The inherited color-profile and layer-effect tests produced the same diagnostics as build 737.

Build inputs **9,429**. Source digest `0df9d86db3db4a83ee1bef30a59f896565c4650d45f4ed63190c100cfb040038`. Local universal preview SHA-256 `51f9766720c15fd2a32e6f1b73ea73806c682d0ba99928b5b3e9f15c599664ba`.

[Development record](DEVLOG.md#dev-step-738) · [Evidence hashes](SOURCE_PUBLICATION_738.json) · [Vanishing Point reference observations](VANISHING_POINT_REFERENCES.json).
