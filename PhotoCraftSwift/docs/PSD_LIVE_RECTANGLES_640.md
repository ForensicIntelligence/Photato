# Save live rectangles as editable Photoshop layers

19 November 2026 · Development preview 640

Photato now opens and saves supported RGB live rectangles as editable shape layers in PSD and PSB. The shape keeps its geometry and solid fill or stroke. On opening a supported Photoshop file, the native renderer displays the original cached pixels and exposes the original path and live controls. A subsequent edit renders the changed shape with the native renderer. Native Save, Save As and authenticated PSD or PSB downloads use the same writer. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

The implementation uses Adobe's published tagged-block and descriptor format with Photoshop-authored test documents as references. It keeps the live origin metadata, vector path, stroke style and original channel cache when the imported rectangle is unchanged. A shape edit regenerates the supported records and cache. The accepted cases have one axis-aligned rectangle with square corners in an 8- or 16-bit RGB document and supported solid paint. Rounded, rotated, compound, dashed, gradient and pattern variants remain outside this qualification.

The two editable rectangle tests that failed in builds 638 and 639 now pass. All 98 selected tests passed in 82.77 seconds, including an AppKit Save, a real loopback PSB download, native shape edits and the print regressions. The initial compilation stopped because a fixture was edited during the build. The final compilation and tests used the updated snapshot.

An independent parser read both original Photoshop fixtures and four re-exports. Their visible shape-layer bounds, all 46,112 decoded RGBA channel bytes across the re-exports and all 8,048 shape descriptor bytes matched. New 8-bit PSD and PSB files retained their measured 64 × 40 live geometry. Editing an imported stroke to four pixels survived both file round trips. A separate native 16-bit probe reopened both formats with the same complete raster cache and editable rectangle.

The installed Photoshop app timed out on the AppleEvent request to reopen and re-save the generated test rectangle. These checks establish Photato decoding, file records and cached samples. Live Adobe acceptance of generated files and broader shape parity remain open.

The signed macOS 14-targeted Apple Silicon ZIP verified after extraction and produced a 1,000 × 650 offscreen workspace snapshot. The 1,219-case cumulative run is in progress on Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. See the source patch (local evidence), focused log (local evidence), and independent PSD and PSB comparison (local evidence).
