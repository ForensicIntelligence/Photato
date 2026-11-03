# Composite selection luminosity

Checkpoint368 records a tested implementation increment; full S05/profile parity remains open. The source now uses captured working gray settings for RGB-composite selection loading. A standard-profile RGB8 calibration and a general ICC path replace the old fixed0.299/0.587/0.114 weights. All432 affected cases pass on ARM and translatedIntel; universal packaging and Xcode Release are verified; the current-source native resource recheck was blocked by a locked Mac, as recorded in SELECTION_ACCEPTANCE_REFERENCES_368.json. Physical platform and general profile fidelity remain open.

## Reference and independent implementation

The installed Photoshop2026 27.2.0 uses North America General Purpose2: sRGB workingRGB, DotGain20 workingGray, RelativeColorimetric, BPC on. Those settings were read through its ordinary UI and were not changed. Owned numerical RGB images were opened, CommandOption2 was invoked, and the selection was saved as a named alpha channel in owned PSD files. A separate public-format PSD/PackBits parser read the resulting coverage.

The exhaustive4096×4096 input contains each possible RGB8 triplet once, with pixel index `i` encoding R=`i>>16`, G=`i>>8 &255`, B=`i &255`. A second reference reopens the saved embedded-profile image and produces identical16,777,216 coverage bytes. Repeated-color inputs at256 positions confirm that the observed differences are not position-dependent dithering. No Photoshop source, executable internals, private protocol or proprietary runtime is used. No vendor artwork or ICC binary/text tag is bundled.

The precompiled full transform is retained as generated numerical calibration data in `Sources/PhotoCraftImaging/Resources/FactoryRGB8Gray20.zlib` (1,336,408 bytes). Its expanded coverage digest is `4518de76c475009c7875918b6544d3f153e407d7974fde399d0c4cf0f47005b4`. It is dispatched by actual document depth/profile semantics and rendering settings; fixture names, document names and test environments are not used. This is an offline native transform for the entire RGB8 domain of that standard profile pair. Other profiles/settings/depths retain the general ICC path. It is not a claim of all-profile Photoshop CMM equivalence.

Photato independently frames its DotGain20 ICC working profile and text metadata. Its numerical tone-response calibration comes from the public ICC kTRC field of an owned reference conversion. Custom working profiles remain selectable; null8/16 gray now resolves to DotGain20 instead of the previous GrayGamma2.2, while32 gray remains linear. Original reference PSDs and their vendor profiles are local qualification evidence rather than application resources.

## Native, API and packaging paths

Native shortcuts/dialogs and `channel.edit` composite source descriptors use the same selection preparation. They snapshot Color Settings and reject a changed profile before commit. `selectionChannels.workingGrayProfile` exposes the effective gray space; the preference API retains ICC/null choices. Typed command identities239, native archive85 and Actions44 are unchanged. No dedicated Adobe channel route is invented; channel actionJSON descriptors remain unsupported.

SwiftPM declares an Imaging resource bundle. Standalone application packaging copies that bundle, and the loader prefers its packaged Resources directory rather than a developer build fallback. The Xcode application explicitly copies the same resource while excluding it from the static-library resource phase. Compressed and expanded checksums are checked before use, with bounded16MiB inflation; missing/corrupt calibration fails rather than silently using different color arithmetic.

## Retained limitations

Direct matrix/shaper math matches the small colored reference but differs on53,073 exhaustive samples by one level, so it is not presented as exact for the standard pair. Scalar rounding, fixed-precision and white-point candidates and a LittleCMS diagnostic did not resolve that gap and are not adopted as replacements. The general ICC/ColorSync paths for other profile pairs, intents, complex native-mode compositions and nonzero black points still need independent Photoshop fidelity qualification. Other depths retain their existing explicit precision and feature gates. Physical macOS14/Intel/macOS26, full-current-suite and60fps qualification remain broader open requirements. No release or installed-app replacement is implied by this work.
