# OpenEXR HDR files

Photato can open and save the supported single-part scanline OpenEXR images through native Swift code. The codec uses the system zlib library for ZIP compression. It does not bundle a C++ OpenEXR runtime or use Python in the application.

Open a supported `.exr` through File > Open. Content detection also identifies EXR bytes under a misleading filename. The document uses 32-bit scene-linear RGB working samples and file-backed tiles. RGB or luminance Y, with optional alpha, can use Half or Float samples and None, one-scanline ZIP (ZIPS), or 16-scanline ZIP compression. Data and display windows determine canvas size and layer placement. Density is retained. The original header is retained as source metadata; this does not promise that export will reproduce every original attribute.

Use File > Save As or Save a Copy and choose OpenEXR. The native controls select compression, Half/Float precision and Save Transparency. Current defaults are ZIP16, Float and transparency. These are Photato defaults, not qualified Photoshop defaults. A 32-bit RGB source is required; output is flattened into scene-linear sRGB without SDR tone mapping. File color channels are premultiplied by alpha. Zero-alpha color is retained rather than discarded.

Float retains the selected rendering's 32-bit samples. Half explicitly reduces precision and rejects rounding that overflows its finite range. Ordinary Save requires one representable flat 32-bit layer and guards against profile conversion, precision reduction, omitted non-opaque alpha and loss of editable content. Save a Copy allows these explicit export choices while preserving the source document, ownership, history and remembered save settings. Native saves use the existing atomic replacement and revision/cancellation guards.

The EXR encoder does not use the older 36-megapixel dense-raster Save restriction. This does not prove full maximum-size Photoshop capacity: the implementation still limits encoded files to 512 MiB and individual scanline workspaces to 128 MiB. Native import has a separate maximum 1 GiB workspace, and the API has smaller transfer/heap budgets. Dense maximum-size documents and every tool at that capacity remain unqualified.

## API

The existing Photato interfaces use the same codec and save options:

- `POST /v1/documents/import`, `Content-Type: image/x-exr`, optional `X-Photato-Open-Format: exr`.
- `GET /v1/documents/{id}/file.exr`, optional current `X-Photato-Revision` and `X-Photato-Export-Options` JSON header.
- `document.saveAs` with a filename, `format: "exr"` and mandatory boolean `replace`, followed by ordinary `document.save`.
- The strict options are `exrCompression: "none" | "zips" | "zip"`, `exrSample: "half" | "float"`, and `exrTransparency: true | false`.

Discovery exposes these formats, options, routes and restrictions under `documentTransfers.encodingOptions.openEXR`. A download is a snapshot and does not change document ownership, history or save settings. Permissions, current revisions, cancellation and busy state follow the existing document transfer/save contracts. Wrong-format, malformed and unknown options reject.

EXR is not added to Adobe's pinned v2 output media types or the existing action-job output contract. File transfer and native-save support do not imply desktop plug-in, general UXP or additional Adobe API compatibility.

## Remaining work

Tiled/deep/multipart data, additional passes/channels, UINT and subsampling, other compression methods, non-square pixels, other chromaticity sets, non-finite colors and alpha outside 0...1 currently reject. Wider profile/metadata/layout transport, large streamed files and full format-specific workflows remain under the original I04 scope. Live controls, physical supported Macs/macOS versions, exact Photoshop defaults and independent Photoshop output equivalence require further qualification. Batch Debug crashes remain recorded separately from optimized results.

References: [ASWF file layout](https://openexr.com/en/latest/OpenEXRFileLayout.html), [ASWF technical introduction](https://openexr.com/en/latest/TechnicalIntroduction.html), [Adobe supported formats](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/image-file-formats-supported-in-photoshop.html), checkpoint evidence and DEVLOG step474. Owned fixtures use independent Python struct/zlib encoding; they are not Photoshop-generated references.

Validation: all97 selected optimized tests pass on Apple Silicon and translated Intel, including all14 new tests. The two architectures write the same seven captured EXR files; independent Python decoding checks6168 sample bytes each. All63488 finite binary16 patterns decode/encode exactly against independent reference words. These are owned synthetic/format references, not Photoshop-generated EXR output. See [checkpoint evidence](OPENEXR_474.json).
