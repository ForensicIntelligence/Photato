# Source checkpoint 721

Layered PSD and PSB exports place the editable text record and its padding before the following protection record. Photato can still open older files written with the uncounted pad. Whole-pixel translations of editable text now render the same way before and after reopening an RGB32 file.

The mixed document keeps editable type and its protection settings, group and pixel masks, an Exposure adjustment, and a projected embedded Smart Object with an editable Gaussian Blur and filter mask. Initial and edited reopens match every rendered RGBA byte at 8, 16 and 32 bits per channel in PSD and PSB. An independent reader recovered the tagged structure in all twelve files per configuration. An independent comparison matched 294,912 stored merged channel words per configuration, including the transparency plane. Authenticated Photato downloads matched the native files byte for byte.

656 of 657 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The two new tests passed in each configuration. The one existing PSD layer-effect method repeated the same 118 differences as build 720. The checked-in Xcode project built, and both signed preview slices target macOS 14.0 and opened offscreen.

The test uses exact file-representable group opacity. Photoshop files store the group opacity in one byte, so a literal 84% differs from the saved 214/255. These tests use owned input and compare round-trip output with Photato’s own pre-save render. Direct Photoshop reopening, Adobe pixel equivalence, linked asset rebind and broader Smart Filter ordering remain open.

Photoshop 27.2.0 returned its version and exposed zero accessible windows and menu bars.

Build inputs **9,421**. Source digest `43be7f442d4e9ec3d99696b0a3d3c7a906585923b1d36dc089664bd3a3afb781`. Local universal preview SHA-256 `80a2bcef3b5cd7bcaa0d7ba1a23e1bceff3dfbff2c0099a141b4186ad50c64c2`.

[Layered file guide](LAYERED_TYPE_EXCHANGE.md) · [Development log](DEVLOG.md#dev-step-721) · [Evidence hashes](SOURCE_PUBLICATION_721.json)
