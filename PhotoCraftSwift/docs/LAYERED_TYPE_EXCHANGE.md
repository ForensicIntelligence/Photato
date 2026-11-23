# Layered PSD and PSB with editable type

Open a layered RGB document in Photato, edit the text or mask, then use File → Save As to write Photoshop (.psd) or Large Document Format (.psb). Reopen the saved file to continue editing the layers. The test fixture exercises 8-, 16- and 32-bit RGB documents.

Layered PSD and PSB exports place the editable text record and its padding before the following protection record. Photato can still open older files written with the uncounted pad. Whole-pixel translations of editable text now render the same way before and after reopening an RGB32 file.

The same codec runs for `document.saveAs` and authenticated `GET /v1/documents/{id}/file.psd` or `file.psb` requests. Enable explicit document transfers before downloading a shared document. [Photato API](AUTOMATION_API.md)

The mixed document keeps editable type and its protection settings, group and pixel masks, an Exposure adjustment, and a projected embedded Smart Object with an editable Gaussian Blur and filter mask. Initial and edited reopens match every rendered RGBA byte at 8, 16 and 32 bits per channel in PSD and PSB. An independent reader recovered the tagged structure in all twelve files per configuration. An independent comparison matched 294,912 stored merged channel words per configuration, including the transparency plane. Authenticated Photato downloads matched the native files byte for byte.

The test uses exact file-representable group opacity. Photoshop files store the group opacity in one byte, so a literal 84% differs from the saved 214/255. These tests use owned input and compare round-trip output with Photato’s own pre-save render. Direct Photoshop reopening, Adobe pixel equivalence, linked asset rebind and broader Smart Filter ordering remain open.

[Qualification](SOURCE_PUBLICATION_721.md) · [Adobe’s layer record specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
