# Independent Color Lookup references

Seven controlled Photoshop 2026 outputs now provide exact reference bytes for Color Lookup: owned CUBEs with edges 2 and 3 at RGB8, RGB16 and RGB32, plus an RGB8 holdout with odd-valued samples. Original source images and tables are CC0. We created the references through Photoshop's normal interface and extracted them with a separate Python PSD parser. No Photoshop implementation code or proprietary LUT assets were copied.

The references exposed differences in interpolation, RGB8 working-code rounding, linear RGB32 round trips, merged transparency and editable PSD descriptor framing. Native creation, Reset and Adobe actions now use the evidenced Tetrahedral path. Existing Photato HTTP omissions retain Trilinear for compatibility; set `interpolation: tetrahedral` explicitly for the qualified path. Native archives retain their encoded choice.

All 95 selected Debug tests and the same 95 optimized checks on Apple Silicon and translated Intel pass, including 16 new methods. Native editing code, HTTP create/set/apply/transfers and both action-job routes compare complete composite samples with the original independent files. All 1,474,560 reference RGB bytes match exactly per path. Structure, history and output are checked separately. Nine factory-menu checks, nine cursor checks and seven older independent RGB32 regressions also pass.

A separate batch of nine existing auxiliary-channel and PSD-transfer methods passes in Debug and both optimized architectures. It checks all 81 plane fixtures and the 56-channel boundary after the merged-alpha representation change.

Fresh editable exports contain an ICC float CLUT cache encoded from their original table values with Photato metadata. Actual Photoshop reopened fresh Cube3 exports at RGB8, RGB16 and RGB32, retained editable layers and settings, recomputed the lookup after a Dither toggle, and saved separate copies. All 688,128 RGB bytes match the original references. These derived files verify interchange; they are not replacement oracles.

Editable PSD export currently requires uniform unit-domain tables without shapers and respects the 16 MiB descriptor budget. Unsupported cache transforms and standalone ICC lookups reject. Other profiles, domains, LUTs, alpha, masks, blends, stochastic Dither, the wider Q04 corpus, full-suite tests, physical platforms and 60 fps remain open. The validation universal app is ad-hoc signed, unlaunched and unreleased. No GitHub, production installation or App Store changes were made.

[Evidence](INDEPENDENT_COLOR_LOOKUP_480.json) · [Development log](DEVLOG.md#dev-step-480) · [Work order](CURRENT_WORK_ORDER.md)
