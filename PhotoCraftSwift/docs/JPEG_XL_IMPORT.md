# JPEG XL import

Choose File > Open and open a .jxl file. Automatic detects the raw JPEG XL bitstream or its box container from file contents. The JPEG XL option is available when the system ImageIO reader advertises the format.

A JPEG XL still opens as an editable raster document. Save As lets you choose Photato or another eligible output format. Open leaves the original file in place and keeps it separate from the document's save destination.

Photato checks the animation flag before decoding. This protects files whose animation is exposed as a single frame by ImageIO. JPEG XL animation and JPEG XL export require further implementation.

The Photato API advertises availability in the document-opening capabilities. Use POST /v1/documents/import with Content-Type image/jxl, or with application/octet-stream and X-Photato-Open-Format: jxl. Use an enabled document-transfer session. The decoder validates the container before creating a document. JPEG XL is an import format and does not appear in the file download formats.

The desktop uses a 1 GiB estimated decoded raster budget for this format. The API applies a 128 MiB estimated decoded raster budget before full decoding, along with its ordinary upload and document sharing limits. These estimates describe raster admission. Peak ImageIO or conversion memory depends on the file and host.

Two owned lossless fixtures cover exact RGB8 and RGBA16 samples, including opaque and transparent pixels. A separate two-frame fixture covers animation in raw, single-box and fragmented forms. The fixtures and expected values are recorded with the tests. Broader profiles, fractional alpha, hidden color, HDR and physical macOS 14/Intel coverage remain open. The installed Photoshop Open dialog was reached, but the fixture folder did not open through automation. A Photoshop pixel comparison is pending.

[Apple ImageIO format discovery](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_basics/ikpg_basics.html) · [Adobe file format overview](https://helpx.adobe.com/photoshop/desktop/save-and-export/save-files/photoshop-file-formats-overview.html) · [Developer diary](DEVLOG.md#dev-step-528)
