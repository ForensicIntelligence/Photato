# Source checkpoint 820

Camera Raw Fill Edges works on panoramas above the previous 4 MP limit, including results from HDR Panorama. Large scenes estimate donor patches from a bounded overview and sample the original detail into the gaps. The merge preview clears and disables Auto Crop while Fill Edges is on.

The Camera Raw filmstrip merged two 4,320 × 4,224 exposures. It filled 1,406,976 transparent or partly transparent pixels and preserved 26,910,720 covered pixels at exact Float32 RGB values. The 170,001,420-byte desktop DNG matched the authenticated download byte for byte. Both originals kept their hashes. Six small Fill Edges DNGs matched the previous build.

Adobe Camera Raw 18.1.1 cleared Auto Crop when Fill Edges was enabled and left it unchecked when the control became available again. Adobe merged the same sources at 6,142 × 4,606 and reopened the Photato DNG at 6,144 × 4,609. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

The Photato API commands `raw.mergePanorama` and `raw.mergeHDRPanorama` use the shared fill path. Fill Edges retains the whole canvas when the request also sets Auto Crop. The advertised limit is 96 MP.

Xcode built the app. All 70 focused checks passed, plus the large desktop and HTTP workflow. Both optimized architectures passed all 453 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The full-size comparison covers one pair of owned sources. Adobe geometry, patch placement, color and compressed DNG bytes still differ. The advertised ceiling and physical Intel and macOS 14 operation need further qualification.

The Universal ZIP targets macOS 14 and later. It contains 80,151,753 bytes with SHA-256 `5a31578275813bf59f40d5d8887d291e7a11bc8cc86d1c6d9484377a89b5ba3a`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_820.json) · [Development record](DEVLOG.md#dev-step-820).
