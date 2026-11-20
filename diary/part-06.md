[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-07.md) · [Next page](part-05.md)

## 2026-10-20 — Step152: protection reaches editing and both APIs

The previous isolated protection model now governs actual native edits and file persistence. Painting preserves the existing alpha stencil; Photoshop’s explicit selected Clear removes pixels. Image and position locks block their respective operations, while full-lock Rename and grouping follow the observed reference. The native dialog, layer buttons, shortcut and both API paths share those transactions. Version12 prevents older readers from silently losing partial protection; compatible existing files retain their prior version.

The first two compilations exposed test inference and initialization errors. Full01 later found94 failed assertions, mostly90 repetitions of the old TIFF partial-to-full collapse. An independent byte inventory proved all30 TIFF fixtures contain transparency-only protection. Focused06 also exposed a known unsupported little-endian opaque metadata block; the test now distinguishes that limitation from protection-only output. Later review also corrected API-only flag transitions and a reproduced protected-Fill integer quantization defect; both interrupted validations and the failing regression are preserved. Live testing then exposed initial checkbox enablement overridden during SwiftUI installation; a hosted-control regression reproduced five failures before the environment-state fix. Final59 focused,1,442 Debug,1,442 Release and20 Rosetta tests pass, with universal packaging and an owned native UI probe. This is bounded integration, not complete Photoshop parity; all major gates remain open.

[Runtime development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-152), [checkpoint152](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_152.json)

Step153 completes the first editable original-project migration subset. Source-generated RGB 8/16/32 fixtures retain raster/group/mask/path/selection/protection data through native Open, API editing and Photato persistence. Empty-selection and file-registration regressions were reproduced and repaired; all 1,455 Debug/Release tests,13 Rosetta cases,universal packaging and an owned live workflow pass. Rich source features and all major gates remain open. See [the detailed step153 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-153).

Step154 adds independent source/Photoshop rendering comparisons and repairs off-canvas raster-mask edge handling. The first broad cropped-mask hypothesis was disproved by controls; the final change follows the measured layer-boundary distinction. All 1,460 Debug/Release tests, 14 Rosetta cases and native/UI/API/package checks pass. Gaussian/vector/full byte parity remains open. See [step154](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-154).

## 26 October 2026

Step155 resumes the feather experiment begun on20October. Controlled identical-byte tests identify a filesystem visibility defect behind misleading Photoshop import errors. The first core repair passes while end-to-end tests expose AppKit staging as a second boundary; the final change carries destination visibility through both. All1,471 Debug/Release,33 focused and22 Rosetta tests pass, and direct Photoshop Open accepts native UI and generated outputs without byte changes. The atlas independently records16 radii, with exploratory exact fits at4/5/10; general feather parity remains unfinished. Historical pauses, failed tests/harnesses and both current-source builds are preserved. See [step155](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-155).

### 26 October: major features before numerical refinement

Step156 captures 48 independent transparent feather controls, but fractional radii invalidate the first simple kernel hypothesis. The maintainer asks to prioritize missing major functionality. Research and reference files are preserved; no feather algorithm is changed. [Deferred research](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-156)

Step157 adds a shared Swift raster-filter workflow: Gaussian/Box/Motion Blur, Unsharp Mask, High Pass, Add Noise, Mosaic and Average. Native preview sheets, Cancel/OK, selection and locks, one undoable edit, existing file persistence, the Photato command and both resource-job interfaces are integrated together. All59 focused Debug and1,483 full Release tests pass, along with24 functional cases on arm64 and x86_64 under Rosetta. The universal macOS 14+ candidate and live UI checks verify; installed117 remains unchanged. Failed fixture/old synchronous-test assumptions and outdated API-count assertions are retained with their repairs. Exact Photoshop filter pixels and Smart Filters remain open. [Filter workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-157)

## Complete chronological index

Every numbered milestone in the source diary at this reconstruction appears below. The link opens the full account of its changes, failures, tests and remaining work. An index entry is a record of activity; research and pause entries are not completed features.

| Date | Milestone | Recorded development |
|---|---:|---|
| 2026-10-07 | 001 | [native Swift migration milestone 1](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-001) |
| 2026-10-07 | 002 | [ordered parity and professional workflow gates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-002) |
| 2026-10-07 | 003 | [Photoshop 2026 workspace replication](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-003) |
| 2026-10-07 | 004 | [Private Cloud Compute re-enabled](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-004) |
| 2026-10-07 | 005 | [native geometry module](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-005) |
| 2026-10-07 | 006 | [coverage selections and direct mask editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-006) |
| 2026-10-07 | 007 | [independent layer masks and PSD interoperability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-007) |
| 2026-10-07 | 008 | [open-source fork and optional support](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-008) |
| 2026-10-07 | 009 | [compressed and high-depth PSD interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-009) |
| 2026-10-07 | 010 | [native layer groups and clipping masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-010) |
| 2026-10-07 | 011 | [native paths and vector masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-011) |
| 2026-10-07 | 012 | [editable PSD solid fills and exactness measurements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-012) |
| 2026-10-07 | 013 | [native App Store tips](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-013) |
| 2026-10-07 | 014 | [Photato branding](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-014) |
| 2026-10-07 | 015 | [feathered pixel masks at canvas boundaries](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-015) |
| 2026-10-07 | 016 | [native mask commands and isolated vector-alpha diagnostics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-016) |
| 2026-10-07 | 017 | [native image and layer clipboard](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-017) |
| 2026-10-07 | 018 | [compact raster archives and faster pixel packing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-018) |
| 2026-10-07 | 019 | [manual RGB Levels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-019) |
| 2026-10-07 | 020 | [Levels histograms, presets and automatic correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-020) |
| 2026-10-07 | 021 | [RGB Curves editing and interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-021) |
| 2026-10-07 | 022 | [Hue/Saturation, color ranges and Desaturate](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-022) |
| 2026-10-07 | 023 | [Color Balance workflow and PSD storage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-023) |
| 2026-10-07 | 024 | [real Hue/Saturation PSD references and Colorize correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-024) |
| 2026-10-08 | 025 | [Hue/Saturation range transfer correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-025) |
| 2026-10-08 | 026 | [Threshold and Posterize](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-026) |
| 2026-10-08 | 027 | [native Clone Stamp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-027) |
| 2026-10-08 | 028 | [regional composition and immutable preview cache](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-028) |
| 2026-10-08 | 029 | [expandable Clone Stamp targets and mask sources](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-029) |
| 2026-10-08 | 030 | [sampled Healing Brush in native Swift](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-030) |
| 2026-10-08 | 031 | [automatic Spot Healing and native patch completion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-031) |
| 2026-10-08 | 032 | [Dodge, Burn and Sponge](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-032) |
| 2026-10-08 | 033 | [Blur, Sharpen and Smudge](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-033) |
| 2026-10-08 | 034 | [Magic Wand and foreground Paint Bucket](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-034) |
| 2026-10-08 | 035 | [native patterns and PAT interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-035) |
| 2026-10-08 | 036 | [editable Pattern Fill layers and embedded PSD patterns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-036) |
| 2026-10-08 | 037 | [exact CPU rendering and Pattern Fill picking optimizations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-037) |
| 2026-10-08 | 038 | [Gradient engine and preset foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-038) |
| 2026-10-08 | 039 | [Editable Gradient Fill and PSD merged transparency](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-039) |
| 2026-10-08 | 040 | [native live and Classic Gradient tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-040) |
| 2026-10-08 | 041 | [persistent native gradient preset library](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-041) |
| 2026-10-08 | 042 | [native Gradient Map and Photoshop 2026 reference acquisition](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-042) |
| 2026-10-08 | 043 | [Stripes gradients and Photoshop depth/import compatibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-043) |
| 2026-10-08 | 044 | [development record audit and documentation discipline](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-044) |
| 2026-10-08 | 045 | [RGB16 merged transparency correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-045) |
| 2026-10-08 | 046 | [Smooth gradient reference acquisition and analysis](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-046) |
| 2026-10-08 | 047 | [Smooth neighboring-stop investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-047) |
| 2026-10-08 | 048 | [Gradient Map stop preservation and Smooth color probes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-048) |
| 2026-10-08 | 049 | [Bounded Smooth color-conversion references](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-049) |
| 2026-10-08 | 050 | [Native RGB16 Gradient Map tone coordinates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-050) |
| 2026-10-08 | 051 | [Classic gradient lookup investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-051) |
| 2026-10-08 | 052 | [Classic native arithmetic candidate](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-052) |
| 2026-10-08 | 053 | [Layer alignment and distribution reference qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-053) |
| 2026-10-08 | 054 | [Native layer layout commands and controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-054) |
| 2026-10-08 | 055 | [Photoshop 2026 menu structure alignment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-055) |
| 2026-10-08 | 056 | [Photoshop factory menu and shortcut defaults](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-056) |
| 2026-10-08 | 057 | [Layer via Copy and Cut](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-057) |
| 2026-10-08 | 058 | [Layer merging and flattening](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-058) |
| 2026-10-08 | 059 | [Minor version 0.2.0 and requested pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-059) |
| 2026-10-08 | 060 | [Workspace visibility and resumed UI priority](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-060) |
| 2026-10-08 | 061 | [Native document windows and Window menu](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-061) |
| 2026-10-08 | 062 | [Native tab drag and drop](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-062) |
| 2026-10-08 | 063 | [Shared application frame and floating canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-063) |
| 2026-10-08 | 064 | [Native viewport zoom and percentage entry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-064) |
| 2026-10-08 | 065 | [Compact workspace layout](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-065) |
| 2026-10-08 | 066 | [Shared saved workspaces](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-066) |
| 2026-10-08 | 067 | [Editable panel dock groups](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-067) |
| 2026-10-09 | 068 | [Native floating panel hosts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-068) |
| 2026-10-09 | 069 | [Native panel tear-off](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-069) |
| 2026-10-09 | 070 | [Native floating panel stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-070) |
| 2026-10-09 | 071 | [Native dock columns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-071) |
| 2026-10-09 | 072 | [Retained History and Clone Source panels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-072) |
| 2026-10-09 | 073 | [Native New Layer dialog](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-073) |
| 2026-10-09 | 074 | [Native New Group workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-074) |
| 2026-10-09 | 075 | [Native Duplicate Layer and Group workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-075) |
| 2026-10-09 | 076 | [Layers panel commands and inline renaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-076) |
| 2026-10-09 | 077 | [Layer text editing and delete confirmation UX](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-077) |
| 2026-10-09 | 078 | [Layer color labels and visibility workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-078) |
| 2026-10-09 | 079 | [Native Layers eye-column dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-079) |
| 2026-10-09 | 080 | [Group disclosure and collapse-all view state](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-080) |
| 2026-10-09 | 081 | [Active-layer reveal and minimal scrolling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-081) |
| 2026-10-09 | 082 | [Native Layers Panel Options and thumbnails](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-082) |
| 2026-10-09 | 083 | [Thumbnail coverage and mask preview geometry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-083) |
| 2026-10-09 | 084 | [Mask-thumbnail gestures and mask canvas views](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-084) |
| 2026-10-09 | 085 | [Workspace layout lifecycle investigation and reveal repair](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-085) |
| 2026-10-09 | 086 | [Compact field layout and absolute position editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-086) |
| 2026-10-09 | 087 | [Native numeric editing lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-087) |
| 2026-10-09 | 088 | [Native Xcode application project](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-088) |
| 2026-10-09 | 089 | [Channels panel and component previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-089) |
| 2026-10-09 | 090 | [User-requested pause, comprehensive parity inventory and estimates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-090) |
| 2026-10-09 | 091 | [Optional native automation API and browser client](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-091) |
| 2026-10-09 | 092 | [Sheet lifecycle and panel organization validation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-092) |
| 2026-10-09 | 093 | [User-requested pause after verified current increment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-093) |
| 2026-10-09 | 094 | [Require API coverage with every new capability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-094) |
| 2026-10-09 | 095 | [Published Adobe Photoshop API v2 compatibility requirement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-095) |
| 2026-10-09 | 096 | [Maintain Photato and Adobe-compatible APIs together](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-096) |
| 2026-10-09 | 097 | [Photato product webpage and public provenance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-097) |
| 2026-10-13 | 098 | [Resumed native panel menu accessibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-098) |
| 2026-10-13 | 099 | [Floating panel input qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-099) |
| 2026-10-13 | 100 | [Channel interaction reference qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-100) |
| 2026-10-13 | 101 | [RGB channel visibility and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-101) |
| 2026-10-13 | 102 | [Component editing reference and transaction design](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-102) |
| 2026-10-13 | 103 | [Recorded Photoshop actions and component integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-103) |
| 2026-10-13 | 104 | [Verified pause after latest debugging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-104) |
| 2026-10-19 | 105 | [Component integration investigation and verified pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-105) |
| 2026-10-19 | 106 | [Native component editing and public API integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-106) |
| 2026-10-19 | 107 | [Verified pause after component and API debugging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-107) |
| 2026-10-19 | 108 | [Major-function-first completion order](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-108) |
| 2026-10-19 | 109 | [Major-function backlog and native document workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-109) |
| 2026-10-19 | 110 | [Document persistence workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-110) |
| 2026-10-19 | 111 | [Native .photato file extension](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-111) |
| 2026-10-19 | 112 | [Source-format preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-112) |
| 2026-10-19 | 113 | [Source-format Save workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-113) |
| 2026-10-19 | 114 | [Exact RGB32 sample preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-114) |
| 2026-10-19 | 115 | [Direct linear HDR editing and composite qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-115) |
| 2026-10-19 | 116 | [Retained working colour profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-116) |
| 2026-10-19 | 117 | [RGB32 Normal rendering and PSD merged output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-117) |
| 2026-10-19 | 118 | [RGB32 grouped and clipped document qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-118) |
| 2026-10-19 | 119 | [PSB document-format integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-119) |
| 2026-10-19 | 120 | [bounded PSD/PSB row decoding](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-120) |
| 2026-10-19 | 121 | [bounded PSD/PSB file input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-121) |
| 2026-10-19 | 122 | [streamed PSD/PSB output and safe saving](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-122) |
| 2026-10-19 | 123 | [scratch-backed undo history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-123) |
| 2026-10-19 | 124 | [native archive streaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-124) |
| 2026-10-19 | 125 | [shared tile storage during history restoration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-125) |
| 2026-10-19 | 126 | [cancellable asynchronous history navigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-126) |
| 2026-10-19 | 127 | [crash recovery lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-127) |
| 2026-10-19 | 128 | [background recovery writing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-128) |
| 2026-10-19 | 129 | [recovery preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-129) |
| 2026-10-19 | 130 | [atomic persistence and interruption handling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-130) |
| 2026-10-19 | 131 | [recovery source identity](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-131) |
| 2026-10-20 | 132 | [independent recovery discovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-132) |
| 2026-10-20 | 133 | [coordinated document closing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-133) |
| 2026-10-20 | 134 | [format-aware background document opening](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-134) |
| 2026-10-20 | 135 | [persistent recent files and queued document opens](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-135) |
| 2026-10-20 | 136 | [recovery backup review and maintenance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-136) |
| 2026-10-20 | 137 | [explicit recovery salvage and index reset](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-137) |
| 2026-10-20 | 138 | [background startup recovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-138) |
| 2026-10-20 | 139 | [recovery memory admission](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-139) |
| 2026-10-20 | 140 | [shared format-specific save and export options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-140) |
| 2026-10-20 | 141 | [PSD and PSB compression](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-141) |
| 2026-10-20 | 142 | [Photoshop file compression preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-142) |
| 2026-10-20 | 143 | [TIFF floating-point preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-143) |
| 2026-10-20 | 144 | [TIFF storage options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-144) |
| 2026-10-20 | 145 | [Layered TIFF interoperability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-145) |
| 2026-10-20 | 146 | [Editable layered TIFF output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-146) |
| 2026-10-20 | 147 | [TIFF rich records and global mask metadata](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-147) |
| 2026-10-20 | 148 | [JPEG native and API save controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-148) |
| 2026-10-20 | 149 | [Original PhotoCraft container foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-149) |
| 2026-10-20 | 150 | [Original PhotoCraft project graph and payload reader](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-150) |
| 2026-10-20 | 151 | [Layer protection references and model](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-151) |
| 2026-10-20 | 152 | [Layer protection runtime integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-152) |
| 2026-10-20 | 153 | [Editable original PhotoCraft project adapter](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-153) |
| 2026-10-20 | 154 | [Source comparison and off-canvas mask correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-154) |
| 2026-10-26 | 155 | [File visibility repair and feather reference measurements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-155) |
| 2026-10-26 | 156 | [Feather research deferred for major functions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-156) |
| 2026-10-26 | 157 | [Native raster-filter workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-157) |
| 2026-10-26 | 158 | [Editable layer styles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-158) |
| 2026-10-26 | 159 | [Automatic subject selection and background removal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-159) |
| 2026-10-26 | 160 | [Embedded Smart Object workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-160) |
| 2026-10-26 | 161 | [Editable Smart Filter stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-161) |
| 2026-10-26 | 162 | [Native text editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-162) |
| 2026-10-26 | 163 | [Classic adjustment workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-163) |
| 2026-10-26 | 164 | [Color Lookup workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-164) |
| 2026-10-26 | 165 | [Native Liquify workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-165) |
| 2026-10-26 | 166 | [Native Select and Mask workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-166) |
| 2026-10-26 | 167 | [Alpha channels and Quick Mask](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-167) |
| 2026-10-26 | 168 | [Content-Aware Fill workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-168) |
| 2026-10-26 | 169 | [Content-Aware Scale](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-169) |
| 2026-10-26 | 170 | [Crop and content-aware edges](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-170) |
| 2026-10-26 | 171 | [Native retouching tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-171) |
| 2026-10-26 | 172 | [Camera Raw Filter](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-172) |
| 2026-10-26 | 173 | [Sensor RAW development](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-173) |
| 2026-10-26 | 174 | [Photo blending and focus stacking](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-174) |
| 2026-10-26 | 175 | [Native Auto-Align Layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-175) |
| 2026-10-26 | 176 | [Native Photomerge workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-176) |
| 2026-10-26 | 177 | [Native HDR merge workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-177) |
| 2026-10-26 | 178 | [Native editable Smart Object image stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-178) |
| 2026-10-26 | 179 | [Native Warp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-179) |
| 2026-10-27 | 180 | [Native Puppet Warp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-180) |
| 2026-10-27 | 181 | [Native Perspective Warp workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-181) |
| 2026-10-27 | 182 | [Native Actions and Batch workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-182) |
| 2026-10-27 | 183 | [Native Artboards workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-183) |
| 2026-10-27 | 184 | [Native Frames workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-184) |
| 2026-10-27 | 185 | [Native Blur Gallery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-185) |
| 2026-10-27 | 186 | [Native Lens Correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-186) |
| 2026-10-27 | 187 | [Native Adaptive Wide Angle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-187) |
| 2026-10-27 | 188 | [Native Vanishing Point](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-188) |
| 2026-10-27 | 189 | [Native Brush Settings and presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-189) |
| 2026-10-27 | 190 | [Native painting and eraser tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-190) |
| 2026-10-27 | 191 | [Native Adjustment Brush](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-191) |
| 2026-10-27 | 192 | [Native selection tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-192) |
| 2026-10-27 | 193 | [Native Sky Selection and Sky Replacement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-193) |
| 2026-10-27 | 194 | [Native Focus Area](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-194) |
| 2026-10-27 | 195 | [Native Mask All Objects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-195) |
| 2026-10-27 | 196 | [Native Object Finder](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-196) |
| 2026-10-27 | 197 | [Native Select People](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-197) |
| 2026-10-27 | 198 | [People feature segmentation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-198) |
| 2026-10-27 | 199 | [Native live shapes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-199) |
| 2026-10-27 | 200 | [Native Pen and Paths](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-200) |
| 2026-10-27 | 201 | [Native advanced typography](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-201) |
| 2026-10-27 | 202 | [Editable shaped text](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-202) |
| 2026-10-27 | 203 | [Native Filter Gallery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-203) |
| 2026-10-27 | 204 | [Pause and current progress dashboard](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-204) |
| 2026-10-27 | 205 | [Photo detail investigation and requested pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-205) |
| 2026-10-27 | 206 | [Native photo detail workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-206) |
| 2026-10-27 | 207 | [Native Lens Blur](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-207) |
| 2026-10-27 | 208 | [Document title and canvas containment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-208) |
| 2026-10-27 | 209 | [Photato identity cleanup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-209) |
| 2026-10-27 | 210 | [Website developer diary and source link](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-210) |
| 2026-10-27 | 211 | [Private GitHub development build](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-211) |
| 2026-10-27 | 212 | [Native distortion workflows and window-build handoff](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-212) |
| 2026-10-27 | 213 | [Native Pixelate workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-213) |
| 2026-10-27 | 214 | [Native Stylize workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-214) |
| 2026-10-27 | 215 | [Native procedural Render filters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-215) |
| 2026-10-27 | 216 | [Native Flame, Tree and Picture Frame](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-216) |
| 2026-10-27 | 217 | [Native Other and Video filter workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-217) |
| 2026-10-27 | 218 | [Native Blur, Noise and Sharpen workflows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-218) |
| 2026-10-27 | 219 | [Classic tone and color adjustments](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-219) |
| 2026-10-27 | 220 | [Document color modes — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-220) |
| 2026-10-28 | 221 | [Native Indexed Color and Bitmap — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-221) |
| 2026-10-28 | 222 | [Duotone and Multichannel — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-222) |
| 2026-10-28 | 223 | [Native proofing and print workflows — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-223) |
| 2026-10-28 | 224 | [Native printing and hard proofs — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-224) |
| 2026-10-28 | 225 | [Native color profile workflows — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-225) |
| 2026-10-28 | 226 | [Persistent working color settings — in progress](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-226) |
| 2026-10-28 | 227 | [Opening and paste color policies, working proof](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-227) |
| 2026-10-28 | 228 | [A portable, single-file developer diary](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-228) |
| 2026-10-28 | 229 | [Editable frame animation and Timeline](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-229) |
| 2026-10-28 | 230 | [Native animated GIF interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-230) |
| 2026-10-28 | 231 | [Native video layers and PNG sequences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-231) |
| 2026-10-28 | 232 | [Native image-sequence export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-232) |
| 2026-10-28 | 233 | [Native movie import and video-layer placement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-233) |
| 2026-10-28 | 234 | [Editable video Timeline keyframes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-234) |
| 2026-10-28 | 235 | [Video editing investigation — implementation pending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-235) |
| 2026-10-28 | 236 | [A master homepage for Forensic Intelligence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-236) |
| 2026-10-28 | 237 | [A pure FOSS release, without purchases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-237) |
| 2026-10-28 | 238 | [Video arrangement and precise splitting](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-238) |
| 2026-10-28 | 239 | [Graphical Timeline and editable transitions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-239) |
| 2026-10-28 | 240 | [Native Timeline audio](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-240) |
| 2026-10-28 | 241 | [Native Render Video](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-241) |
| 2026-10-28 | 242 | [Timeline work areas and onion-skin previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-242) |
| 2026-10-28 | 243 | [Universal Timeline preview qualification](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-243) |
| 2026-10-29 | 244 | [Timeline work-area trimming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-244) |
| 2026-10-29 | 245 | [Frame-to-video Timeline conversion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-245) |
| 2026-10-29 | 246 | [Video-to-frame conversion and original recovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-246) |
| 2026-10-29 | 247 | [Variables and data-driven graphics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-247) |
| 2026-10-29 | 248 | [Contact Sheet II](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-248) |
| 2026-10-29 | 249 | [Crop and Straighten Photos](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-249) |
| 2026-10-29 | 250 | [Image Processor](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-250) |
| 2026-10-29 | 251 | [Video Frames to Layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-251) |
| 2026-10-29 | 252 | [Native PDF page import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-252) |
| 2026-10-29 | 253 | [Embedded PDF images](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-253) |
| 2026-10-29 | 254 | [Stable source publication](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-254) |
| 2026-10-29 | 255 | [Native PDF Smart Object placement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-255) |
| 2026-10-29 | 256 | [Publish qualified PDF Smart Object source](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-256) |
| 2026-10-29 | 257 | [General embedded placement workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-257) |
| 2026-10-29 | 258 | [Publish qualified embedded placement source](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-258) |
| 2026-10-29 | 259 | [PDF source editing and completion dashboard repair](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-259) |
| 2026-10-29 | 260 | [Retained PDF page PSD/PSB interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-260) |
| 2026-10-29 | 261 | [Linked-source work, preserved and parked](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-261) |
| 2026-10-29 | 262 | [Interactive painting responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-262) |
| 2026-10-29 | 263 | [Interactive retouching responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-263) |
| 2026-10-29 | 264 | [Large-image toning responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-264) |
| 2026-10-29 | 265 | [Retained Focus-tool feedback](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-265) |
| 2026-10-29 | 266 | [Faster stroke startup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-266) |
| 2026-10-29 | 267 | [Prepare the canvas at the right zoom](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-267) |
| 2026-10-29 | 268 | [Redraw only changing feedback](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-268) |
| 2026-10-29 | 269 | [Measure native editing feedback](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-269) |
| 2026-10-30 | 270 | [Present accepted editing previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-270) |
| 2026-10-30 | 271 | [Use the current preview and restore tool focus](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-271) |
| 2026-10-30 | 272 | [Layer opacity slider](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-272) |
| 2026-10-30 | 273 | [Held-pointer brush smoothing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-273) |
| 2026-10-30 | 274 | [Brush release responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-274) |
| 2026-10-30 | 275 | [Retouch release responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-275) |
| 2026-10-30 | 276 | [Stable preview pause and retouch automation handoff](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-276) |
| 2026-10-30 | 277 | [Semantic retouch Actions and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-277) |
| 2026-10-30 | 278 | [Large-document architecture](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-278) |
| 2026-10-30 | 279 | [Disk-backed dense raster input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-279) |
| 2026-10-30 | 280 | [Paged native persistence and large file IO](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-280) |
| 2026-10-30 | 281 | [Publish qualified native source280](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-281) |
| 2026-10-30 | 282 | [Indexed native archives](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-282) |
| 2026-10-30 | 283 | [Modifier-aware tool cursors](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-283) |
| 2026-10-30 | 284 | [Paged runtime tile index (under test)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-284) |
| 2026-10-30 | 285 | [Persistent native tile ordinal reuse (software qualified; UI pending)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-285) |
| 2026-10-30 | 286 | [Large PSD/PSB file workflows (software qualified; UI pending)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-286) |
| 2026-10-30 | 287 | [Paged document geometry (software qualified; native acceptance pending)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-287) |
| 2026-10-31 | 288 | [Paged selections and bounded channel views (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-288) |
| 2026-10-31 | 289 | [Publish qualified source288](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-289) |
| 2026-10-31 | 290 | [Paged layer-stack composition (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-290) |
| 2026-10-31 | 291 | [Paged vector-mask preparation (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-291) |
| 2026-10-31 | 292 | [Paged basic raster filters (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-292) |
| 2026-10-31 | 293 | [Paged Smart Filter workflows (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-293) |
| 2026-10-31 | 294 | [Private qualified-source backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-294) |
| 2026-10-31 | 295 | [Streamed Smart Filter cache interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-295) |
| 2026-10-31 | 296 | [Large isolated resource jobs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-296) |
| 2026-10-31 | 297 | [Modern adjustment layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-297) |
| 2026-10-31 | 298 | [Apply Image and Calculations (software qualified)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-298) |
| 2026-10-31 | 299 | [Linked Smart Objects (in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-299) |
| 2026-10-31 | 300 | [Rich PhotoCraft migration (in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-300) |
| 2026-10-31 | 301 | [Diary refreshed against current evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-301) |
| 2026-10-31 | 302 | [Exposure workflow prerequisite (in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-302) |
| 2026-10-31 | 303 | [Editable source vector shapes (unbuilt, in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-303) |
| 2026-10-31 | 304 | [Diary synchronized with actual source and test evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-304) |
| 2026-10-31 | 305 | [Editable source shapes: native/API workflows tested, strict gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-305) |
| 2026-10-31 | 306 | [Rich source text migration (unbuilt, in progress)](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-306) |
| 2026-10-31 | 307 | [Diary synchronized with current work and verified evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-307) |
| 2026-10-31 | 308 | [Rich source text native/API workflows tested; exact gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-308) |
| 2026-10-31 | 309 | [Source Smart Object prerequisites; workflow crash remains open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-309) |
| 2026-10-31 | 310 | [Diary synchronized with current work, tests and failures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-310) |
| 2026-10-31 | 311 | [Command-worker crash repaired; full inventory and strict gates recorded](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-311) |
| 2026-10-31 | 312 | [Editable source Smart import: cached workflows tested; nesting failure open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-312) |
| 2026-10-31 | 313 | [Diary synchronized with current import and retained failures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-313) |
| 2026-10-31 | 314 | [Nested source worker repaired; native/API workflows pass, strict gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-314) |
| 2026-11-01 | 315 | [Editable source filter mappings expand to107; functional tests pass, strict gates open](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-315) |
| 2026-11-01 | 316 | [Native Relight engine and integration draft; testing pending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-316) |
| 2026-11-01 | 317 | [Diary synchronized with working316 and tested315](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-317) |
| 2026-11-01 | 318 | [Native Relight workflows and exact original-engine reference subset qualified](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-318) |
| 2026-11-01 | 319 | [Multi-light Lighting Effects; partial tests and failed repair](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-319) |
| 2026-11-01 | 320 | [Diary synchronized with current319 evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-320) |
| 2026-11-01 | 321 | [Lighting Effects functional qualification and complete test inventory](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-321) |
| 2026-11-01 | 322 | [Source Displace functional qualification and diary synchronization](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-322) |
| 2026-11-01 | 323 | [Original adjustment-layer functional breadth and source composition](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-323) |
| 2026-11-01 | 324 | [Original layer effects: staged native controls and rendering helpers, unfinished](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-324) |
| 2026-11-01 | 325 | [Diary synchronized with tested323 and unfinished324](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-325) |
| 2026-11-01 | 326 | [Original layer-effects functional qualification and shared Global Light menu](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-326) |
| 2026-11-01 | 327 | [Diary reconciled with tested source, installed preview and remaining major work](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-327) |
| 2026-11-01 | 328 | [Original channels and auxiliary spot workflows functionally qualified](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-328) |
| 2026-11-01 | 329 | [PSD/PSB auxiliary channel interchange functionally qualified](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-329) |
| 2026-11-01 | 330 | [Document guides and source layout import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-330) |
| 2026-11-01 | 331 | [Xcode archive and alpha store preparation; validation and media pending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-331) |
| 2026-11-01 | 332 | [Window lifecycle, recovery and updated Xcode archive](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-332) |
| 2026-11-01 | 333 | [App Store validation after Xcode sign-in](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-333) |
| 2026-11-01 | 334 | [Native File Info and source document metadata](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-334) |
| 2026-11-01 | 335 | [Photoshop 2026 as the reference](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-335) |
| 2026-11-01 | 336 | [Layer Comps and production export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-336) |
| 2026-11-01 | 337 | [Smart Object comp selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-337) |
| 2026-11-01 | 338 | [Parent Layer Comp Smart Object choices](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-338) |
| 2026-11-01 | 339 | [Editable PSD/PSB Layer Comps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-339) |
| 2026-11-02 | 340 | [Editable PSD/PSB Global Light](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-340) |
| 2026-11-02 | 341 | [Production Export As workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-341) |
| 2026-11-02 | 342 | [Layers to Files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-342) |
| 2026-11-02 | 343 | [Color Range selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-343) |
| 2026-11-02 | 344 | [Magnetic Lasso tool](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-344) |
| 2026-11-02 | 345 | [Selection Modify and Reselect](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-345) |
| 2026-11-02 | 346 | [Transform Selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-346) |
| 2026-11-02 | 347 | [Selected-pixel Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-347) |
| 2026-11-02 | 348 | [Background layer semantics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-348) |
| 2026-11-02 | 349 | [Background selected-pixel Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-349) |
| 2026-11-02 | 350 | [Move and copy selected pixels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-350) |
| 2026-11-02 | 351 | [Pixel-mask Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-351) |
| 2026-11-02 | 352 | [Auxiliary-channel Free Transform](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-352) |
| 2026-11-02 | 353 | [Multi-layer and group transforms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-353) |
| 2026-11-02 | 354 | [Projective layer transforms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-354) |
| 2026-11-02 | 355 | [Layer links and whole-layer Move](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-355) |
| 2026-11-02 | 356 | [Color Fill and Stroke](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-356) |
| 2026-11-02 | 357 | [Pattern Fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-357) |
| 2026-11-02 | 358 | [Large-document Crop](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-358) |
| 2026-11-02 | 359 | [Layer capacity](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-359) |
| 2026-11-02 | 360 | [Flatten Image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-360) |
| 2026-11-02 | 361 | [Duplicate Image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-361) |
| 2026-11-02 | 362 | [Trim and Reveal All](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-362) |
| 2026-11-02 | 363 | [Private full-source backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-363) |
| 2026-11-02 | 364 | [Rich layer merging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-364) |
| 2026-11-02 | 365 | [Linked preview sampling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-365) |
| 2026-11-02 | 366 | [Quick Mask and saved selections](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-366) |
| 2026-11-02 | 367 | [Saved-selection documents; next major function selected](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-367) |
| 2026-11-02 | 368 | [Quick Mask workflow checks; C01 next](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-368) |
| 2026-11-03 | 369 | [Quick Mask visibility and hidden brush target](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-369) |
| 2026-11-03 | 370 | [Private source backup and next major function](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-370) |
| 2026-11-03 | 371 | [Hidden Quick Mask commands and pixel Invert](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-371) |
| 2026-11-03 | 372 | [Quick Mask target transitions; C01 queued](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-372) |
| 2026-11-03 | 373 | [Mask paint colors and S05 audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-373) |
| 2026-11-03 | 374 | [Large saved-selection files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-374) |
| 2026-11-03 | 375 | [PSB file compatibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-375) |
| 2026-11-03 | 376 | [Shared paint colours](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-376) |
| 2026-11-03 | 377 | [App Store listing and media](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-377) |
| 2026-11-04 | 378 | [App Store familiarity wording](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-378) |
| 2026-11-04 | 379 | [Multichannel Quick Mask files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-379) |
| 2026-11-04 | 380 | [Mask paint-colour contexts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-380) |
| 2026-11-04 | 381 | [Mask target lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-381) |
| 2026-11-04 | 382 | [Current full test inventory](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-382) |
| 2026-11-04 | 383 | [Document lifecycle regression repairs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-383) |
| 2026-11-04 | 384 | [Animated layer-style transactions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-384) |
| 2026-11-04 | 385 | [Fit Image and reusable batch constraints](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-385) |
| 2026-11-04 | 386 | [Find and Replace Text](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-386) |
| 2026-11-04 | 387 | [Numeric component-plane storage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-387) |
| 2026-11-04 | 388 | [Native component blocks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-388) |
| 2026-11-04 | 389 | [Private source backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-389) |
| 2026-11-04 | 390 | [Component archive streaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-390) |
| 2026-11-04 | 391 | [Large native component documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-391) |
| 2026-11-04 | 392 | [Large component geometry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-392) |
| 2026-11-04 | 393 | [Large component tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-393) |
| 2026-11-04 | 394 | [RGB8 component routing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-394) |
| 2026-11-04 | 395 | [Private source backup and listing wording](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-395) |
| 2026-11-04 | 396 | [Large native channel arithmetic](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-396) |
| 2026-11-04 | 397 | [Independent channel eyes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-397) |
| 2026-11-04 | 398 | [Temporary mask channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-398) |
| 2026-11-04 | 399 | [Consolidated S05 validation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-399) |
| 2026-11-04 | 400 | [Quick Mask options and gestures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-400) |
| 2026-11-04 | 401 | [Quick Mask reference matrix; repair parked](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-401) |
| 2026-11-04 | 402 | [Seven-pass work order](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-402) |
| 2026-11-04 | 403 | [Delete All Empty Layers native baseline](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-403) |
| 2026-11-04 | 404 | [Single-pixel marquee and quick-win audits](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-404) |
| 2026-11-04 | 405 | [Color Lookup export and quick-win audits](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-405) |
| 2026-11-04 | 406 | [RGB8 component selection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-406) |
| 2026-11-04 | 407 | [Duplicate saved actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-407) |
| 2026-11-04 | 408 | [Shape stroke presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-408) |
| 2026-11-04 | 409 | [Quick-win source audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-409) |
| 2026-11-05 | 410 | [Gradient Fill API and Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-410) |
| 2026-11-05 | 411 | [Last Filter and Pattern Fill audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-411) |
| 2026-11-05 | 412 | [Filter Gallery dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-412) |
| 2026-11-05 | 413 | [Brush Settings sidebar controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-413) |
| 2026-11-05 | 414 | [Smart Filter dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-414) |
| 2026-11-05 | 415 | [Select Subject options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-415) |
| 2026-11-05 | 416 | [Selected-mask removal and API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-416) |
| 2026-11-05 | 417 | [Statistical image stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-417) |
| 2026-11-05 | 418 | [Frame Timeline dragging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-418) |
| 2026-11-05 | 419 | [Rename sky presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-419) |
| 2026-11-05 | 420 | [Rasterization responsiveness](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-420) |
| 2026-11-05 | 421 | [Channel thumbnail options and major quick-win sweep](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-421) |
| 2026-11-05 | 422 | [Arrange selected layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-422) |
| 2026-11-05 | 423 | [Layer filtering and isolation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-423) |
| 2026-11-05 | 424 | [Asynchronous layer content filters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-424) |
| 2026-11-05 | 425 | [Layer selection and deselection](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-425) |
| 2026-11-05 | 426 | [Customize Save Dialog File Formats](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-426) |
| 2026-11-05 | 427 | [Adjacent artboard controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-427) |
| 2026-11-05 | 428 | [Animated selection borders](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-428) |
| 2026-11-05 | 429 | [Transform reference point](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-429) |
| 2026-11-05 | 430 | [Large-document Equalize](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-430) |
| 2026-11-05 | 431 | [Color Lookup output formats](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-431) |
| 2026-11-05 | 432 | [Pattern Patch](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-432) |
| 2026-11-05 | 433 | [Channels footer Save/Load](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-433) |
| 2026-11-05 | 434 | [Batch file naming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-434) |
| 2026-11-05 | 435 | [Precise shape creation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-435) |
| 2026-11-05 | 436 | [Extended Fill Path](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-436) |
| 2026-11-06 | 437 | [Character and Paragraph panels — development](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-437) |
| 2026-11-06 | 438 | [Point-text layout and native editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-438) |
| 2026-11-06 | 439 | [Direct native path typing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-439) |
| 2026-11-06 | 440 | [Paged Curves and Levels histograms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-440) |
| 2026-11-06 | 441 | [Light painting and retouch previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-441) |
| 2026-11-06 | 442 | [Gradient creation and portable Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-442) |
| 2026-11-06 | 443 | [Pattern groups and PAT hierarchy](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-443) |
| 2026-11-06 | 444 | [Public repository and Shape Blur development](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-444) |
| 2026-11-06 | 445 | [Public Git history credential audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-445) |
| 2026-11-06 | 446 | [Custom Shape Blur numerical investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-446) |
| 2026-11-06 | 447 | [Custom Kernel ACF preset interchange](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-447) |
| 2026-11-06 | 448 | [Blur Gallery mask output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-448) |
| 2026-11-06 | 449 | [Public source and unpublished build backup](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-449) |
| 2026-11-06 | 450 | [Liquify last mesh reuse](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-450) |
| 2026-11-06 | 451 | [Local build cleanup; lens-default audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-451) |
| 2026-11-06 | 452 | [Camera and lens defaults](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-452) |
| 2026-11-06 | 453 | [Custom Filter Gallery textures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-453) |
| 2026-11-06 | 454 | [Brush pattern textures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-454) |
| 2026-11-06 | 455 | [Eraser mode reference](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-455) |
| 2026-11-06 | 456 | [Eraser modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-456) |
| 2026-11-06 | 457 | [Blur, Sharpen and Smudge blend modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-457) |
| 2026-11-06 | 458 | [Content-Aware Fill without leaving the workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-458) |
| 2026-11-06 | 459 | [Eyedropper averaging and source controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-459) |
| 2026-11-06 | 460 | [Mask and channel clipboard](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-460) |
| 2026-11-06 | 461 | [Advanced blending channel controls](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-461) |
| 2026-11-06 | 462 | [Saved layer style presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-462) |
| 2026-11-06 | 463 | [Smart Object Convert to Layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-463) |
| 2026-11-06 | 464 | [Smart Filter stack and mask transfer](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-464) |
| 2026-11-06 | 465 | [Magic Wand averaged sampling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-465) |
| 2026-11-07 | 466 | [Selection source policy and Magic Wand Subject](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-466) |
| 2026-11-07 | 467 | [Select and Mask source workflow](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-467) |
| 2026-11-07 | 468 | [Layer and Smart Filter mask filtering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-468) |
| 2026-11-07 | 469 | [Large auxiliary-channel filtering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-469) |
| 2026-11-07 | 470 | [Split Channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-470) |
| 2026-11-07 | 471 | [Large-document soft proofing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-471) |
| 2026-11-07 | 472 | [Large image stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-472) |
| 2026-11-07 | 473 | [Embedded originals in source projects](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-473) |
| 2026-11-07 | 474 | [OpenEXR HDR files](part-01.md#dev-step-474) |
| 2026-11-07 | 475 | [Generated image jobs and originals](part-01.md#dev-step-475) |
| 2026-11-07 | 476 | [Blank video drawing layers](part-01.md#dev-step-476) |
| 2026-11-07 | 477 | [Sky preset groups and batch import](part-01.md#dev-step-477) |
| 2026-11-07 | 478 | [Local Color Lookup painting](part-01.md#dev-step-478) |
| 2026-11-07 | 479 | [Color Lookup property responsiveness](part-01.md#dev-step-479) |
| 2026-11-07 | 480 | [Independent Color Lookup references](part-01.md#dev-step-480) |
| 2026-11-07 | 481 | [Repeatable archive validation](part-01.md#dev-step-481) |
| 2026-11-07 | 482 | [Menu inventory reconciliation](part-01.md#dev-step-482) |
| 2026-11-07 | 483 | [Script Events Manager](part-01.md#dev-step-483) |
| 2026-11-07 | 484 | [Quick Mask selection semantics](part-01.md#dev-step-484) |
| 2026-11-07 | 485 | [Sampled Hue/Saturation ranges](part-01.md#dev-step-485) |
| 2026-11-07 | 486 | [Classic RGB16 gradient boundaries](part-01.md#dev-step-486) |
| 2026-11-08 | 487 | [Share the person-selection model](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-487) |
| 2026-11-08 | 488 | [Image styles and canvas size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-488) |
| 2026-11-08 | 489 | [Native Remove tool](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-489) |
| 2026-11-08 | 490 | [Generated backgrounds](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-490) |
| 2026-11-08 | 491 | [Reference images for generation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-491) |
| 2026-11-08 | 492 | [Reviewed edit plans](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-492) |
| 2026-11-08 | 493 | [Profile changes on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-493) |
| 2026-11-08 | 494 | [Directory durability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-494) |
| 2026-11-08 | 495 | [Paged Warp](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-495) |
| 2026-11-08 | 496 | [PSD vector path semantics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-496) |
| 2026-11-08 | 497 | [Untagged files and sandboxed copies](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-497) |
| 2026-11-08 | 498 | [Large colour-mode files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-498) |
| 2026-11-08 | 499 | [Paths to Illustrator](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-499) |
| 2026-11-08 | 500 | [Repair native asset export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-500) |
| 2026-11-08 | 501 | [Select People on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-501) |
| 2026-11-08 | 502 | [Report Apple text-service availability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-502) |
| 2026-11-08 | 503 | [Review people before removal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-503) |
| 2026-11-08 | 504 | [Background generation on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-504) |
| 2026-11-08 | 505 | [Edit a reference image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-505) |
| 2026-11-08 | 506 | [Local learned upscaling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-506) |
| 2026-11-08 | 507 | [Reviewed adjustment values](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-507) |
| 2026-11-08 | 508 | [AI, language and plugin acceptance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-508) |
| 2026-11-08 | 509 | [Plugin host requirements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-509) |
| 2026-11-08 | 510 | [Editable gradient profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-510) |
| 2026-11-08 | 511 | [Gray32 Photoshop file export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-511) |
| 2026-11-09 UTC | 512 | [Merge Channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-512) |
| 2026-11-09 UTC | 513 | [Legacy Macintosh proof](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-513) |
| 2026-11-09 UTC | 514 | [Editable photo blending](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-514) |
| 2026-11-09 UTC | 515 | [Editable artboard project import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-515) |
| 2026-11-09 | 516 | [Editable PSD/PSB artboards](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-516) |
| 2026-11-09 | 517 | [Saved generated-image variations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-517) |
| 2026-11-09 | 518 | [Editing video keyframes as a group](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-518) |
| 2026-11-09 | 519 | [Large Sky documents and full-detail previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-519) |
| 2026-11-09 | 520 | [Color and vibrance with Adjustment Brush](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-520) |
| 2026-11-09 | 521 | [Sky preview containment and brush measurements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-521) |
| 2026-11-09 | 522 | [Masked adjustment preview performance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-522) |
| 2026-11-09 | 523 | [Retained layer-mask and Adjustment Brush previews](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-523) |
| 2026-11-09 | 524 | [Selection borders and Canvas Size zoom](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-524) |
| 2026-11-16 | 525 | [Selection-preview responsiveness; 22 Debug checks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-525) |
| 2026-11-16 | 526 | [Marquee creation and polygon routing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-526) |
| 2026-11-17 | 527 | [Save format checks on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-527) |
| 2026-11-17 | 528 | [Open JPEG XL still images](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-528) |
| 2026-11-17 | 529 | [Share unchanged canvas preview pages](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-529) |
| 2026-11-17 | 530 | [Send ready previews directly to the AppKit canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-530) |
| 2026-11-17 | 531 | [Find changed tiles without sorting the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-531) |
| 2026-11-17 | 532 | [Reuse recomposited tiles in the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-532) |
| 2026-11-17 | 533 | [Start the first Brush frame sooner](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-533) |
| 2026-11-17 | 534 | [Start the background worker with Brush input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-534) |
| 2026-11-17 | 535 | [Match the ordinary Brush smoothing default](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-535) |
| 2026-11-17 | 536 | [Connect Brush and Pencil strokes with Shift-click](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-536) |
| 2026-11-17 | 537 | [Record Pencil strokes in Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-537) |
| 2026-11-17 | 538 | [Support 5,000 px primary brush diameters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-538) |
| 2026-11-17 | 539 | [Process Brush coverage and output by tile](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-539) |
| 2026-11-17 | 540 | [Align linear Float32 brush output across architectures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-540) |
| 2026-11-17 | 541 | [Publish retained Brush and flat compositor output by tile](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-541) |
| 2026-11-17 | 542 | [Round Linear and Perceptual gradient transfers consistently](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-542) |
| 2026-11-17 | 543 | [Reuse exact gradient samples and publish tiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-543) |
| 2026-11-17 | 544 | [Prepare wide brush dabs once and start the first preview sooner](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-544) |
| 2026-11-17 | 545 | [Compose flat tone stacks in one tile pass](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-545) |
| 2026-11-17 | 546 | [Write changed canvas bytes directly](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-546) |
| 2026-11-18 | 547 | [Retain coverage for wide raster brushes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-547) |
| 2026-11-18 | 548 | [Speed up Normal brush tile output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-548) |
| 2026-11-18 | 549 | [Sample wide brush coverage in parallel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-549) |
| 2026-11-18 | 550 | [Parallelize large raster composition and display packing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-550) |
| 2026-11-18 | 551 | [Parallelize brush tile output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-551) |
| 2026-11-18 | 552 | [Add brush opacity and flow number keys](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-552) |
| 2026-11-18 | 553 | [Widen the zero-hardness Soft Round tip](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-553) |
| 2026-11-18 | 554 | [Calibrate the round brush hardness range](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-554) |
| 2026-11-18 | 555 | [Add brush hardness, rotation and smoothing keys](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-555) |
| 2026-11-18 | 556 | [Add Behind and Clear painting modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-556) |
| 2026-11-18 | 557 | [Add Brush and Pencil blend-mode shortcuts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-557) |
| 2026-11-18 | 558 | [Page large Paint Bucket and Magic Wand regions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-558) |
| 2026-11-18 | 559 | [Add Paint Bucket Clear and automation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-559) |
| 2026-11-18 | 560 | [Add Clear to Edit Fill and Stroke](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-560) |
| 2026-11-18 | 561 | [Record Paint Bucket Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-561) |
| 2026-11-18 | 562 | [Record Brush Actions for masks and channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-562) |
| 2026-11-18 | 563 | [Record and replay Quick Mask Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-563) |
| 2026-11-18 | 564 | [Record Brush Actions for color channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-564) |
| 2026-11-18 | 565 | [Add Allow Tool Recording to Actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-565) |
| 2026-11-18 | 566 | [Preserve opaque Gray32 merged samples in PSD and PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-566) |
| 2026-11-18 | 567 | [Use the source tone curves for 32-bit RGB and Gray](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-567) |
| 2026-11-18 | 568 | [Match half-gamma promotion and Gray32 PSD layer stacks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-568) |
| 2026-11-18 | 569 | [Match HDR grayscale conversion and ICC gamma boundaries](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-569) |
| 2026-11-18 | 570 | [Preserve the working profile when merging before conversion](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-570) |
| 2026-11-18 | 571 | [Fix HDR PSD and PSB compression for Photoshop](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-571) |
| 2026-11-18 | 572 | [Match Intel HDR Normal layer and group compositing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-572) |
| 2026-11-18 | 573 | [Match HDR Normal rounding at the Float32 underflow boundary](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-573) |
| 2026-11-18 | 574 | [Add Stamp Layers and Stamp Visible](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-574) |
| 2026-11-18 | 575 | [Render sparse stamps at maximum canvas size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-575) |
| 2026-11-18 | 576 | [Match stored RGB32 Normal merge and stamp samples](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-576) |
| 2026-11-18 | 577 | [Preserve stored RGB32 pixel masks when merging and stamping](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-577) |
| 2026-11-18 | 578 | [Add contextual Merge Clipping Mask](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-578) |
| 2026-11-18 | 579 | [Add in-place Stamp Down and Stamp Group](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-579) |
| 2026-11-18 | 580 | [Match Screen clipping and unchanged stamp history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-580) |
| 2026-11-18 | 581 | [Merge and stamp adjacent clipped layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-581) |
| 2026-11-18 | 582 | [Preserve independent clipping in merges and stamps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-582) |
| 2026-11-18 | 583 | [Add four clipped blend modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-583) |
| 2026-11-19 | 584 | [Preserve pixel masks in clipping merges and stamps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-584) |
| 2026-11-19 | 585 | [Add three arithmetic clipping blend modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-585) |
| 2026-11-19 | 586 | [Bound pixel-mask Feather rendering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-586) |
| 2026-11-19 | 587 | [Match staged RGB32 pixel-mask Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-587) |
| 2026-11-19 | 588 | [Support layer-mask Feather through 1,000 px](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-588) |
| 2026-11-19 | 589 | [Apply Feather in raster clipping merges and stamps](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-589) |
| 2026-11-19 | 590 | [Match integer raster-mask Feather stages](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-590) |
| 2026-11-19 | 591 | [Match measured fractional RGB32 Feather schedules](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-591) |
| 2026-11-19 | 592 | [Bound Smart Filter mask Feather on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-592) |
| 2026-11-19 | 593 | [Bound vector mask Feather on large canvases](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-593) |
| 2026-11-19 | 594 | [Match measured short vector-mask Feather responses](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-594) |
| 2026-11-19 | 595 | [Prepare vector-mask Feather around the viewport](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-595) |
| 2026-11-19 | 596 | [Reuse source bands during wide mask Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-596) |
| 2026-11-19 | 597 | [Reuse window sums during wide mask Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-597) |
| 2026-11-19 | 598 | [Render whole-canvas rectangular vector masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-598) |
| 2026-11-19 | 599 | [Reuse wide vector-mask Feather windows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-599) |
| 2026-11-19 | 600 | [Prove RGB32 raster-base opacity with rectangular Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-600) |
| 2026-11-19 | 601 | [Render sparse curved Feather from stored coverage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-601) |
| 2026-11-19 | 602 | [Skip solid pieces of dense feathered vector masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-602) |
| 2026-11-19 | 603 | [Reuse exact composited tiles under solid vector Feather](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-603) |
| 2026-11-19 | 604 | [Reuse wide vector Feather profiles at canvas edges](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-604) |
| 2026-11-19 | 605 | [Stream repeated rows in sparse PSB files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-605) |
| 2026-11-19 | 606 | [Reopen sparse editable PSB raster layers](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-606) |
| 2026-11-19 | 607 | [Choose sparse Photoshop layer samples across the canvas](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-607) |
| 2026-11-19 | 608 | [Save full-width sparse raster edits to PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-608) |
| 2026-11-19 | 609 | [Set PSD and PSB file compatibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-609) |
| 2026-11-19 | 610 | [Read saved Photoshop channels without a merged preview](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-610) |
| 2026-11-19 | 611 | [Import large PSD and PSB saved channels into sparse tiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-611) |
| 2026-11-19 | 612 | [Save large PSD and PSB channels with repeated rows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-612) |
| 2026-11-19 | 613 | [Import large flattened RGB PSD and PSB without staging all process planes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-613) |
| 2026-11-19 | 614 | [Read large ZIP-compressed Photoshop layers and masks as sparse rasters](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-614) |
| 2026-11-19 | 615 | [Keep large Grayscale, CMYK and Lab Photoshop planes sparse](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-615) |
| 2026-11-19 | 616 | [Write native Photoshop separations and Gray32 previews from stored blocks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-616) |
| 2026-11-19 | 617 | [Add the optional Workflow Guide](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-617) |
| 2026-11-19 | 618 | [Save deep RGB Photoshop files without a merged preview](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-618) |
| 2026-11-19 | 619 | [Rank Workflow Guide suggestions and highlight each step](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-619) |
| 2026-11-19 | 620 | [Keep maximum-size Multichannel printing plates editable](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-620) |
| 2026-11-19 | 621 | [Follow native menus and dialogs in the Workflow Guide](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-621) |
| 2026-11-19 | 622 | [Resize and crop editable Multichannel plates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-622) |
| 2026-11-19 | 623 | [Convert layerless ink documents back to editable image modes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-623) |
| 2026-11-19 | 624 | [Duplicate channels into the current image or another document](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-624) |
| 2026-11-19 | 625 | [Merge spot ink into the supported process channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-625) |
| 2026-11-19 | 626 | [Delete process channels through the Channels panel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-626) |
| 2026-11-19 | 627 | [Integrate Workflow Guide cues with the expanded Channels panel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-627) |
| 2026-11-19 | 628 | [Drag channel rows and keep menu cues aligned](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-628) |
| 2026-11-19 | 629 | [Keep saved masks and printing plates in one Multichannel order](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-629) |
| 2026-11-19 | 630 | [Keep Workflow Guide highlights visible across controls and dialogs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-630) |
| 2026-11-19 | 631 | [Preserve spot inks in Multichannel Photoshop files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-631) |
| 2026-11-19 | 632 | [Keep native CMYK and Lab components when flattening to Multichannel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-632) |
| 2026-11-19 | 633 | [Return standard Multichannel plates to editable CMYK](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-633) |
| 2026-11-19 | 634 | [Print native CMYK and saved spot separations](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-634) |
| 2026-11-19 | 635 | [Print a selection from a large document](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-635) |
| 2026-11-19 | 636 | [Fit and clip large prints at their original sample resolution](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-636) |


## 2026-10-26 — Step158: editable layer effects

Major-feature breadth continues with ten native effect kinds, a style editor, copy/paste/clear, native persistence and both APIs. Six effect kinds have bounded PSD interchange. Live numeric editing exposed an exclusivity crash that model-only tests missed; the setter was repaired and a regression added. A command-matrix writing error was recovered from preserved evidence; eight filter evidence sentences are explicitly reconstructed. All55 focused Debug and1,498 full Release tests pass, plus30 cases each on arm64/Rosetta and universal package verification. The repaired native workflow passes. Fine contour matching, advanced variants and full Photoshop parity remain open. See [the complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-158).

## 2026-10-26 — Step159: automatic subjects and backgrounds

The next broad workflow uses Apple's local Vision model to select foreground subjects or create an editable layer mask. Original pixels stay editable; native history and both API interfaces use the same engine.56 focused checks pass, including cancellation and revoked sharing. The real model removes the icon background and native Select Subject/Undo works. A mask-focus callback guard found by testing was repaired. The Mac locked before the remaining live mask check; all1,510 full Release tests and the universal macOS 14+ package verify. Final parser/default repair passes26 focused tests, with platform model results preserved separately. Intricate edges and the rest of object/sky/people selection remain open. See [the development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-159).

## 2026-10-26 — Step160: embedded Smart Objects

The next major workflow preserves the original source behind a rendered layer. Resize/rotate retains source samples; ordinary copies share content, while New Smart Object via Copy stays independent. Native Edit Contents opens a child document and Save updates its parent through Undo. Placement, replacement, source export, native14 persistence and an affine PSD/PSB subset share the Photato/Adobe API engine.57 integration tests and14 final focused tests pass. All1,524 full Release tests,36 checks per architecture and the universal macOS 14+ package verify. The Mac remains locked for live checks; no independent Photoshop Smart Object fidelity claim is made. Linked sources, warp, richer source formats and Smart Filters remain open. [Complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-160).

## 2026-10-26 — Step161: editable Smart Filters

Eight native filters now remain editable over original Smart Object sources. Layers expose filter settings, per-filter blending/visibility/order and a shared paintable mask; ordinary layers retain baked filters. Native15, history, Photato automation and published Adobe execute-actions share the same engine. Seven filter types have bounded PSD/PSB descriptor/cache mappings; unsupported exports fail explicitly.67 integration checks pass. All1,536 final Release tests,87 checks per architecture and the universal macOS 14+ package verify. The first Release run exposed one outdated archive-version test; its two expectations were corrected before the passing full rerun. All failed compile attempts remain recorded; no independent Photoshop or live UI claim while the Mac is locked. The next major workflow is native text editing; numerical refinements remain deferred. [Complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-161).

## 2026-10-26 — Step162: native text editing

The basic text stamp is now a native point/paragraph editor with caret selection, mixed character formatting, paragraph controls, local typing Undo and a single committed document edit. Native16, two Photato commands and a published Adobe create-composite subset preserve editable content. A bounded Swift port of upstream TySh/EngineData supports native-generated PSD/PSB round trips. Compilation and runtime failures are preserved, including a missing NSTextView text system initially mistaken for a Redo failure; an explicitly owned TextKit stack repaired it. All54 integration tests pass. All1,548 final Release tests and48 checks per architecture pass, and the universal macOS 14+ package verifies. The first full Release run exposed one obsolete PSD type-rejection test, corrected before the passing rerun. Independent Photoshop/live UI and advanced typography remain open; major-feature breadth continues with classic adjustments. [Complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-162).

## 2026-10-26 — Step163: Classic adjustment workflows

Five missing classic adjustments now share native Properties/dialog controls, selection masks, history, native17 saving and three typed Photato commands. The source approximations were translated from Rust with explicit validation. Nine factory menu commands are newly bound; the newer Color and vibrance layer remains open because its white-balance controls are additional functionality. PSD/PSB carries editable supported records; Adobe action jobs and the published /v2/edit color subset use the same Swift engine. Test failures exposed an omitted archive-header version discriminator and stale catalogue/fixture expectations; each attempt is retained. All46 integration tests pass. All1,559 final Release tests and90 checks per architecture pass; universal macOS 14+ packaging verifies. The first full run found11 stale catalogue/version expectations. Those were corrected, and a review also added a missing prepared API creation-limit check with an atomicity test;36 final focused checks pass. Exact Photoshop output, richer Photo Filter transport and live UI remain open. [Complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-163).

## 2026-10-26 — Step164: Color Lookup workflow

Color Lookup now has a usable native grading workflow: import Cube/3DL/LOOK, choose generated Photato looks, preview or create editable layers, and retain masks/settings/history in native18. Source-domain and nonuniform shaper information survive import and save. Photato APIs upload bounded LUTs, create/set/apply adjustments and download original LUT files; Adobe execute-actions uses the shared native engine for a bounded inline descriptor subset. PSD/PSB supports loaded Trilinear LUTs. No Adobe preset files are redistributed. Two compile failures and an incorrect Adobe test-request envelope were repaired with their logs retained. All34 focused tests pass; 1,569 full Release tests passed, followed by a PSD name/format metadata correction,35 final focused Release checks and27 cases per architecture. The final universal macOS 14+ package verifies. Both source snapshots and packages are retained. Live UI, exact Photoshop grading, ICC/CSP and richer interchange remain open. [Complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-164).

## 2026-10-26 — Step165: Native Liquify workspace

The major-feature queue moves to Liquify. PhotoCraft’s inverse displacement grid now has native Swift brushes, freeze masks, reconstruction and mesh-program persistence, alongside a dedicated macOS workspace. Local Vision landmarks feed independent face controls. Pixel-layer editing and editable Smart Filters use shared history, native19 saving and the typed API; face detection is a read-only API command. Compilation/test fixture failures and their repairs are preserved in DEVLOG. All53 Debug focused,1,583 full Release tests before identity repair,71 final Release checks and29 public checks per architecture pass; the universal macOS 14+ package verifies. Real local Vision requests on a nonface image complete on both architectures; portrait quality remains unqualified. Photoshop mesh files/PSD descriptors, Adobe Liquify actions, exact numerical behavior and live checks stay open. [Liquify development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-165)

## 2026-10-26 — Step170: Crop and content-aware edges

The Crop tool now has an expandable boundary, rotation/straighten line, common aspect ratios, retained/deleted raster pixels and transparent/background/content-aware extension. Preview, cancellation, one-step undo and API use the same native implementation. Generated edge pixels remain on an editable layer; interior transparency is retained. A redundant mask-coordinate calculation and a synthetic event-coordinate test were repaired; all 47 focused tests pass. The first full run exposed two outdated API counts; these and the shared Image > Crop integration are covered by the final 1,637 passing Release tests. The universal macOS 14+ package verifies. Exact Photoshop rendering, advanced presets/settings and live/platform checks remain open. Patch, Content-Aware Move and Red Eye are next. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-170).

## 2026-10-26 — Step169: Content-Aware Scale

Native seam carving now shrinks or enlarges a raster layer or selected pixels while retaining protected content. The existing canvas transform controls add reference-point, Amount, saved alpha-channel and skin-tone options; preview, cancellation and one-step undo share the engine with the API. The factory shortcut is connected. A compile-time error-property assignment was repaired, and all 25 focused engine, desktop/API, menu and transform tests pass. A procedural output comparison was inspected. The universal macOS 14+ package verifies. Photoshop numerical equality, nonlinear mask deformation and live/platform qualification remain open. Content-aware crop fill is next. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-169).

## 2026-10-26 — Step168: Content-Aware Fill workspace

The next major workflow now has native sampling and selection brushes, a preview, color/rotation/scale/mirror adaptation, current/new/duplicate-layer outputs, cancellation and undo. The desktop and `contentAware.fill` API share the Swift implementation derived from the licensed Rust source. A compile error and an AppKit test-controller initialization crash were repaired; all 30 final focused tests pass. A procedural before/after image was inspected. The universal macOS 14+ package verifies. Exact Photoshop output, live interaction, cross-document sampling and finer workspace controls remain open. Content-Aware Scale and crop fill are next. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-168).

## 2026-10-26 — Step167: Alpha channels and Quick Mask

The maintainer reinforced breadth over fine fidelity. Persistent grayscale channels, saved selections, painting/filtering, Quick Mask, native20 saving and history now work through the native UI and two typed API operations. Three Select commands and Q are connected. Three compile failures and repairs are retained;47 initial and73 final focused tests pass. The final universal macOS 14+ package and28 refresh-repair tests pass. PSD/spot channels, cross-document operations and independent/live fidelity remain open. Full-suite and platform qualification are batched. Content-Aware Fill is next. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-167).

## 2026-10-26 — Step166: Native Select and Mask workspace

A major selection workflow now has a native Swift matting engine and workspace: guided edge detection, global refinements, decontamination, brushes/lasso, subject selection, local history and six output choices. The factory menu/shortcut and existing selection/mask controls open it. The Photato API shares the engine and prepared document history; new-document outputs require transfer permission and leave the source untouched. Compilation repairs, the missing decontamination-preview correction and their passing focused tests are preserved. Offscreen captures have unreliable native-control compositing and are not accepted visual qualification; live work awaits unlock. All47 initial/12 repaired focused checks and1597 final full Release tests and54 checks per architecture pass; the universal macOS 14+ package verifies. Adobe proprietary hair/Object Aware algorithms, action descriptors, exact output and broader contexts remain open. Next major workflow: channels, saved selections and Quick Mask. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-166).


## 2026-10-26 — Step171: Native retouching tools

Patch, Content-Aware Move/Extend and Red Eye now share native prepared edits with toolbar controls, history and three API operations. The implementation reuses the source-port healing/fill foundations. Tests exposed nested-array inference, a mutable concurrency capture, integer-depth/linear-buffer confusion and a full-coverage Float32 rounding defect; each failure and repair is retained. All 123 focused/regression tests pass. All 39 optimized focused checks also pass, and the universal macOS 14+ package verifies. Independent Photoshop algorithms and live/platform parity remain unqualified. The next major family is Camera Raw. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-171).

## 2026-10-26 — Step172: Camera Raw Filter

**Camera Raw Filter (step172):** Light, color, curves, mixer/grading, detail and effects now have a native workspace with preview, settings files, local/document history, editable Smart Filters and both API paths. All 67 final focused/regression and 1,659 full optimized tests pass. The universal macOS 14+ package verifies. Sensor RAW/DNG import, lens corrections, local masks, XMP, exact Adobe output and live/platform qualification remain open. Next: actual sensor RAW development. See [Camera Raw evidence](../PhotoCraftSwift/docs/CAMERA_RAW_REFERENCES.json). The first build caught multi-variable observation declarations; the next test run caught obsolete all-filter assumptions and a test ID changed by Smart Object conversion. All failed attempts and repairs are retained. This increment implements RGB development; sensor decoding is a separate next step, not a completed RAW01 claim. [Complete development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-172).


## 2026-10-26 — Step173: sensor RAW development

**Sensor RAW development (step173):** Supported camera RAW/DNG files now retain their original source in editable Smart Objects, with native sensor controls, preview, history, native22 saving and both API paths. All 96 final focused and 96 optimized focused tests pass. The universal macOS 14+ package verifies. Camera-specific qualification, local RAW masks/XMP, editable PSD RAW interchange and exact Photoshop output remain open. Next major family: photo alignment and merging. See [RAW evidence](../PhotoCraftSwift/docs/RAW_DEVELOPMENT_REFERENCES.json). The generated Bayer DNG has no embedded preview. Independent Core Image comparisons exposed a strip row-order error; it was repaired before the final 96-case pass. Empty small-fixture decoder probes, compilation failures and failing assertions remain recorded. Offscreen native workspace tests cover preview and local/document history; they are not live UI qualification. See [the complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-173).


## 2026-10-26 — Step174: photo blending and focus stacking

**Auto-Blend Layers (step174):** Panorama seams and focus stacking now have native preview/Cancel/OK, editable masks, multiband blending, transparent-area fill, Undo/Redo and both API paths. All 69 focused/regression and 69 optimized focused tests pass. The universal macOS 14+ package verifies. All 15 follow-up catalogue checks pass after test-only expectation updates. Auto-Align, Photomerge, HDR and exact/live/platform qualification remain open. Next: native Auto-Align Layers. See [blend evidence](../PhotoCraftSwift/docs/PHOTO_BLEND_REFERENCES.json). The Swift pyramid translation matches an independently compiled original-Rust fixture. Installed Photoshop source establishes the bounded panorama action descriptor vocabulary; no Adobe code was executed or copied. Compilation and two fixture failures were repaired with previous attempts retained. Source pixels remain unchanged; masks are editable and a merged output hides the originals to preserve alpha. Masks-only output retains layer selection. This does not establish Adobe algorithm, visual or factory-dialog equivalence. See [the complete record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-174).

### 26 October: editable statistical stacks

The major-feature pass added file/folder/open-document loading and statistical Smart Objects. All eleven PhotoCraft operators preserve original photo layers; changing or removing a mode is undoable, and editing the source refreshes each shared instance with its own mode. The native Statistics/Load Layers dialogs include optional shared alignment and preview/cancel. Native23 retains mode metadata, and unsupported editable PSD export fails explicitly. Three Photato commands and the installed Adobe renderer descriptor use the same engine. Original-Rust and analytical checks distinguish source-port correctness from unqualified Photoshop equality. The failed adapter/compiler/test assumptions and passing repairs are retained in [step178](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-178).

## 2026-10-27 — Step183: native Artboards

Artboards now form a complete basic multi-layout workflow: create, convert layers/groups, move/resize/duplicate, edit backgrounds/guides, save native27, and export separate files or a multipage PDF. Native controls, Photato commands and published Adobe jobs share the core metadata/clipping engine. Negative coordinates rebase physical pixels without resampling; extraction retains source layers and gradients. Compilation repairs and an outdated archive-version test expectation are preserved in the detailed record. Exact Photoshop output, richer contexts, PSD interchange and Frames remain open. No live interaction is claimed while the desktop is locked. [Full development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-183).

## 2026-10-27 — Step184: native Frames

Frames now retain an editable boundary separately from image contents. Native K tool drawing, type/shape conversion, fitting, replacement and independent transformations share one-step history and API commands. Closed text contours preserve counters, empty frames show placeholders and optional strokes, and source bytes survive transforms. Native28 preserves metadata; PSD writes reject instead of dropping it. Three compilation attempts exposed accessor/visibility/glyph/concurrency issues and their preserved repairs preceded passing module and140 integration checks. No live desktop pass is claimed. Minor refinements are deferred while major workflows remain missing; Blur Gallery is next. [Full record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-184).

## 2026-10-27 — Step185: native Blur Gallery

All five Blur Gallery tools now share editable source-relative geometry, a native preview workspace, local/document history and Smart Filter persistence with the API. Spatial blur follows the original Rust Gaussian-level approach; path/spin use premultiplied sampling. Bokeh/noise and bounded spin strobes extend the core workflow. Compiler integration failures, stale archive/PSD tests and an action descriptor that incorrectly accepted defaults were repaired and preserved. A single-flash invariant exposed a sampling edge case and drove a functional repair. Offscreen layout was inspected but does not prove live behavior. Exact Photoshop output and richer subfunctions remain open while work proceeds to major lens/perspective workspaces. [Full record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-185).

## 2026-10-27 — Step186: native Lens Correction

Lens Correction now shares its typed Swift geometry and settings across native controls, Smart Filters, direct API edits and recorded Actions/Batch. The workspace includes correction/profile controls, straighten/distortion gestures, grid/navigation, preview/Cancel and local/document history. The original Rust calibration estimates are labelled as generic; no manufacturer database is claimed. The vignette midpoint follows the documented Adobe direction. Integration repaired a throwing loop, value-access conflict, a test-only Equatable assumption and legacy tests that wrongly expected identity defaults to change pixels. Smart Object geometry now resolves the actual placed/prior-filter input. All97 final focused Debug tests pass. Broader packaging is batched with Adaptive Wide Angle and Vanishing Point; the current universal candidate remains step185. Exact/live/platform/profile/PSD gaps remain open. [Full record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-186).

## 2026-10-27 — Step187: native Adaptive Wide Angle

Straightening now works through a native constraint workspace with lines, polygons, individual edge orientations and five projection choices. The Swift solver ports the source camera/mesh approach, with an explicit cylindrical panorama and bounded geometry cache. A shared input helper keeps Lens and Wide Angle coordinates aligned with placed Smart Objects and preceding filters. Native controls, history, native31 persistence, direct API and recorded Actions/Batch share the same correction engine. The first integrated17 tests and final107 focused regression tests all pass; catalogue archive/identity/unsupported-PSD expectations were updated before broad regression. No failed test attempts occurred. The offscreen image verifies preview/overlay/layout only. Exact/live/profile/PSD and performance qualification remain open, with optimized/universal work batched after Vanishing Point. [Full record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-187).

## 2026-10-27 — Step188: native Vanishing Point

Perspective planes, related-plane edits, perspective paste/clone/brush, local preview/history, native32 and a typed API now share a Swift prepared edit. Seven new source/test files and18 changed files are enumerated in the run manifest; none removed. The core derives from the original Rust plane and paste/clone geometry with native brush support. Failed attempts exposed a conversion-signature error, an Observation declaration restriction, a cross-test-target helper reference and a Float32 renderer/document-depth mismatch; all repairs and failure logs are preserved. The final117 focused Debug checks pass, including native/API agreement and cancellation. The full1816-test optimized suite and universal package subsequently pass for steps186–188. A documentation helper used the wrong CSV field name; its partial output was retained, the complete matrix restored and the edit reapplied without touching frozen build inputs. Secondary tool/Actions/PSD and exact/live/platform gaps stay open. The offscreen view is layout evidence only. [Full record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-188).

## 2026-10-27 — Step189: native brush workflow

The circular painter now has an optional native dynamics engine, with seeded spacing, custom tips, shape/scatter/color/transfer/texture/dual behavior, flow, smoothing, pose, symmetry and timed airbrush strokes. Modeless Brush Settings and Brushes windows, factory menus/F5 and the options bar make the configuration usable while painting. Canvas previews render the same frozen stroke as the final undoable edit, preserving selections, placement and supported mask/channel targets. Presets save atomically in the native format or the supported ABR subset; twelve generated presets contain no Adobe-owned assets. New typed APIs expose configuration, preset management and painting; advanced Actions use version 2 to prevent old readers from silently dropping settings.

Validation found and repaired analytic test expectations, an API schema concurrency error, invalid Smart Object/mask fixtures, a preview scheduling race and a genuine nested-command stack overflow caused by large inline brush settings. Immutable indirect settings preserve value semantics and the wire format while keeping command values small. Every failed attempt and the crash report remain saved. All 103 focused Debug and 1834 full optimized tests pass. The universal macOS 14+ package verifies. Offscreen layout and synthetic AppKit events are separate from live desktop/tablet evidence; the desktop remains locked. The current Adobe brush-resource job path, physical bristle simulation and exact Photoshop output remain open. Next major batch: Pencil, Mixer Brush, Color Replacement, Pattern Stamp and the two missing erasers. No source publication, installed/root app replacement or user-settings change occurred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-189), [checkpoint189](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_189.json), [brush references](../PhotoCraftSwift/docs/BRUSH_REFERENCES.json).

## 2026-10-27 — Step190: six native painting tools

Pencil/Auto Erase, Color Replacement, Mixer Brush, Pattern Stamp, Background Eraser and Magic Eraser now use the shared native brush, selection, layer protection and history infrastructure. Factory B/S/E toolbar groups expose their controls. Mixer paint wells update only after successful commit; sampling, load/clean and automatic choices share native/API behavior. Aligned Pattern Stamp retains its phase. Brush/Pencil create an ordinary transparent layer when painting above nonraster content. Masks and grayscale channels work where applicable, including transformed Smart Filter mask coordinates.

Three typed API commands expose configuration, painting and Mixer state. Tests cover visible previews, Cancel, Undo, source preservation, archives, settings, protected/transformed targets, native/API equivalence and invalid/busy/stale/revoked requests. Validation repaired a real no-op tile allocation, an existing sampler visibility boundary and two erroneous test helper/target assumptions; failed logs are retained. All 184 focused Debug and 1851 full optimized tests pass. The universal macOS 14+ package verifies. The original Rust, root/installed app and user settings remain unchanged. The desktop remains locked, so offscreen and synthetic-event tests are not live UI qualification. Full Adobe brush-resource jobs, new-tool Actions/Batch recording, physical wet-media behavior and exact Photoshop output remain open. Major feature breadth continues with Adjustment Brush; secondary controls and numerical/cosmetic refinements wait.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-190), [checkpoint190](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_190.json), [paint-tool references](../PhotoCraftSwift/docs/PAINT_TOOL_REFERENCES.json).

## 2026-10-27 — Step191: editable local adjustments

Adjustment Brush creates a masked adjustment on its first stroke and paints further coverage onto that editable mask. Fifteen native adjustment types reuse the existing engines and Properties editors. Add/Subtract, object clicks, overlays, inversion, replacement, New Adjustment, density/feather and brush controls form one native workflow. Original pixels remain unchanged. The on-device Vision integration selects the foreground instance at the clicked point; synthetic detector/label-buffer tests validate the new path without claiming live inference qualification.

Four Photato commands share the native engine, strict schemas, session state and transaction/history behavior. Native/API mask refinements are equivalent. Recorded Actions version3 preserves brush requests, semantic layer references, explicit object coverage and replacement operations; older action files remain readable. The captured factory Frame/K binding is retained despite conflicting newer Adobe prose; Adjustment Brush has no invented shortcut. No dedicated Adobe masked-paint endpoint is claimed.

Validation found and fixed a missing shared const-schema rule, outdated command-count assertions and an out-of-canvas test fixture. Final API review corrected an assumed mask endpoint by adding density/feather operations and updated action-library version descriptions. Failed attempts remain saved. All 156 focused Debug and156 focused optimized checks pass. Full regression and universal packaging are batched with the next major selection increment; the last verified package190 does not contain191. All1444 frozen inputs,754 original Rust files and four protected files verify. Photato.xcodeproj remains present/unchanged. The desktop remains locked; no live UI comparison or physical platform qualification is claimed. Full presets, newer adjustment types, exact pixels/models and richer Adobe compatibility remain open. Major feature work continues with Object Selection, Quick Selection and Selection Brush; fine numeric/cosmetic work waits.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-191), [checkpoint191](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_191.json), [Adjustment Brush evidence](../PhotoCraftSwift/docs/ADJUSTMENT_BRUSH_REFERENCES.json).

## 2026-10-27 — Step192: three major selection tools

Object Selection now supports rectangle/lasso initialization through native graph cut and clicked-object targeting through Apple's local Vision adapter. Quick Selection follows image boundaries from painted seeds. Selection Brush paints editable soft coverage with a colored overlay. The graph, mixture model, geodesic costs and boundary refinement were translated from the preserved MIT/Apache PhotoCraft sources into Swift, with attribution and native cancellation/work limits. Source images remain unchanged; existing masks, history and Select and Mask workflows consume the result.

Four typed API commands expose configuration and all three tools through the same native transaction, with discoverable state/result schemas and request lifecycle guards. Actions version4 retains explicit coverage on its original canvas; replay does not silently redetect objects. Native archives remain32. Tests include independent exhaustive small-graph cuts, textured segmentation fixtures, reduced-resolution recut, offscreen/synthetic interaction, soft coverage at 8/16/32-bit, current/composite sampling, cancellation and native/HTTP equality. No test attempt failed; one stale-context patch made no changes and was reapplied correctly. Validation also corrected stale overlays on tool changes and the API's omitted Object Selection mode fallback.

All155 broad focused Debug checks,7 final dedicated workflow checks and1876 full optimized tests pass. The universal macOS 14+ package verifies and includes191 Adjustment Brush. All1455 frozen inputs, four protected files and754 original Rust hashes verify. The Xcode project remains present and unchanged. Source deltas, build/signature evidence and prior attempts are retained. No live desktop qualification was possible because the last authoritative desktop state remains locked. Photoshop byte/model equivalence, broader finder/People workflows and platform qualification remain open. Continue major workflow breadth with Sky Selection and Sky Replacement.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-192), [checkpoint192](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_192.json), [selection references](../PhotoCraftSwift/docs/SELECTION_TOOL_REFERENCES.json).

## 2026-10-27 — Step193: Sky Selection and Sky Replacement

Select > Sky now runs the source-derived detector in Swift. Edit > Sky Replacement opens a native preview with imported skies or a raster layer source, sky placement, manual Add/Subtract mask brushing, edge refinement, sky brightness/temperature and foreground color/light controls. Output preserves the original layers and either adds editable masks/transforms/adjustments or a merged duplicate. The user sky library persists atomically and reports invalid files instead of overwriting them. The classical detector is not represented as Adobe AI, and no proprietary sky assets were copied.

Three Photato commands expose selection, replacement and sky-library management with strict discovery schemas, observable state, document/library revisions and the same prepared history path as the desktop. Select Sky records explicit coverage in Actions4; replacement recording remains visibly unsupported. The Adobe contract has no dedicated sky route. Native archive32 and the Xcode project remain unchanged.

The development record preserves failed compilation, test assumptions and a metadata-validation defect that blocked output. The attempted arbitrary sourceTags metadata was removed; existing native layers retain editability. Follow-up tests verify no-sky/manual fallback, all depths, canvas gestures, preview/local/document Undo, read/close cancellation, native/API equality, valid source-layer strokes, selection combinations, library corruption and stale/busy/revoked requests. The only retained numerical discrepancy is Float32 duplicate recomposition at up to2.98e-8 in the synthetic fixture; integer-depth samples match. The functional tolerance is1e-7, with exact bytes explicitly deferred under the maintainer's major-first priority. The renderer was not changed to chase that detail.

A documentation helper used the wrong CSV column and partially wrote the command matrix. The partial file was preserved; reconstruction from earlier backups/update blocks exactly matched final192's recorded hash before applying the one intended change atomically. All645 prior rows remain. The first recovery attempt stopped before writing because an obsolete626-row assertion failed; both helpers remain evidence.

All113 focused Debug and113 optimized tests pass. The universal macOS 14+ package verifies. Last full regression is1876 passing tests at192; the next major batch will broaden again. All1464 frozen inputs, four protected files and754 original Rust hashes verify. Fresh package extraction confirms both architectures, macOS 14 minimum, ad-hoc signature, licenses and icon. The offscreen synthetic preview is readable; no live desktop test was performed because the latest authoritative desktop state remains locked. Exact/model/preset/Actions/full-context/platform requirements remain open. Next is Focus Area, followed by Mask All Objects; numerical and cosmetic work stays deferred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-193), [checkpoint193](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_193.json), [sky references](../PhotoCraftSwift/docs/SKY_REFERENCES.json).

## 2026-10-27 — Step194: Focus Area

Focus Area now selects sharp regions using a native Swift translation of PhotoCraft's local Laplacian-energy detector, normalization, guided cleanup and upsampling. The source's range direction contradicted Adobe's documented interface, so the native controls deliberately increase strictness as range rises; manual zero selects the entire image. Auto range/noise estimates are transparent native heuristics, with exact Adobe algorithms/defaults still unqualified. Attribution preserves the original MIT/Apache provenance.

The existing refinement workspace supplies the preview, Add/Subtract brushes, view modes, local history and six selection/mask/layer/document outputs. Focus controls add Auto/manual range/noise and Soften Edge. Turning Auto off preserves the displayed estimate. Preview can show the unmodified image. Select and Mask handoff keeps corrected coverage in the draft without changing the source until OK. Native document reload/close cancels pending analysis and cannot commit late results.

Select > Focus Area is bound in the captured menu position. The new selection.focus API uses strict settings/stroke schemas, requested/effective workspace state, shared native preparation/history and existing new-document permission/revision/lifecycle guards. Selection output records coverage in Actions4; nonselection output remains explicitly unsupported for recording. Native archive32 and the Xcode project are unchanged. No dedicated Adobe endpoint or focus actionJSON conformance is claimed.

The first core and integration runs passed. Expanded controls exposed a Swift exclusivity compile error; the failed attempt is preserved and the settings copy repaired. Code review also found hard-mask output could resurrect discarded tiny components at the soft-field threshold; hard output now uses cleaned binary labels, with a focused regression. Six core and seven new workflow tests cover sharp/blur/noise/flat/depth/cancellation, six native/API outputs, source and archive preservation, transforms/locks, sampling independent of prior selection, controls/brush/handoff, new-document/read/close lifecycle and invalid/stale/busy/revoked requests. The offscreen synthetic preview is readable; it is not live desktop evidence.

All83 final focused Debug and1903 full optimized tests pass. The universal macOS 14+ package verifies and includes193 Sky workflows. All1470 frozen inputs, four protected files and754 original Rust hashes verify. Fresh extraction checks both architectures, macOS 14 minimum, signature, version, licenses and icon. No installed/root app replacement, publication, commit or user settings change occurred. The original full Photoshop objective remains active. Next: Mask All Objects with separate editable per-object mask groups, followed by broader object-selection workflows; numerical/cosmetic refinements remain deferred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-194), [checkpoint194](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_194.json), [Focus Area references](../PhotoCraftSwift/docs/FOCUS_AREA_REFERENCES.json).

## 2026-10-27 — Step195: Mask All Objects

Mask All Objects now creates one editable masked group per locally detected foreground instance. This advances beyond the source Rust implementation, which explicitly combines all objects into a single mask. The native Vision adapter performs one inference and requests each actual instance independently. Groups are empty Pass Through folders above the original clipping family, ready for a targeted adjustment; original pixels, masks, hierarchy and document selection remain intact. Source layers may remain locked, but locked parents reject insertion.

The captured Layer menu and layer context menu now invoke the shared native command. The new layer.maskAllObjects API brings the catalogue to90 and exposes schemas, availability, limits and created group IDs. Both paths use prepared history transactions and preserve atomic failure on cancellation, revocation, invalid masks and resource limits. Native32 archives retain editable groups. Recorded Actions reports explicit unsupported status; no Adobe route or actionJSON conformance is invented.

Seven new workflow tests exercise multiple injected instances, all three native depths, source retention, targeted adjustments, archive/Undo/Redo, nested clipping placement, transformed inputs/locks, menus/context, native cancellation/reload and actual HTTP equivalence/schema/error/lifecycle/resource cases. The first test build failed on throwing/actor test syntax and was repaired. The second run had one partial-schema-helper assertion failure; the result envelope was correct, and its declared extension fields now validate independently. Both failed attempts remain preserved. A code review added a conservative padded-tile memory budget for thin canvases.

All82 focused Debug and82 optimized tests pass. Real Apple Vision inference succeeds on the1024×1024 icon with source retention and Undo/Redo. Latest full/universal baseline194 has1903 passing tests and excludes195. The real-model mask was inspected as the expected Photato icon silhouette; it is neither a real-photo multi-object accuracy study nor live Photoshop evidence. All1475 frozen inputs,754 original Rust files and four protected hashes verify. Five source/test files were added,12 inputs modified, none removed; exact lists are in changes01. No installed/root app replacement, publication, commit or settings mutation occurred. The Xcode project and version remain unchanged. Full qualification will be batched after the next major selection workflow.

Next is Object Finder with cached hover highlighting/click selection, refresh/cancellation, source invalidation, controls and API. People/body-part workflows and exact parity remain open. [Details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-195), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_195.json), [references](../PhotoCraftSwift/docs/MASK_ALL_OBJECTS_REFERENCES.json).

## 2026-10-27 — Step196: Object Finder

Object Finder now runs one local Vision instance analysis and reuses its masks while the pointer moves. The canvas shows the actual hovered mask; clicking selects it with New/Add/Subtract/Intersect modes and optional Hard Edge. A click during inference waits for the matching source. Selection-only changes reuse detection, while source edits, layer/tool switches, sample mode, refresh and document replacement invalidate it. The native options add Finder, Hard Edge, refresh, highlight color and cancellation; Escape also cancels detection. Manual rectangle/lasso and the earlier direct point detector remain available.

Three APIs expose detection, temporary hover and cached selection, including optional bounded raw masks for clients that draw their own overlay. Configuration and result/state schemas are discoverable. Cache identity prevents stale selection; native and HTTP paths share selection/history/Actions. Detection and hover never dirty the document. Native32 remains unchanged and recorded Actions4 stores resulting coverage, not an unverified adaptive detector. No new Adobe endpoint or semantic-model equivalence is claimed.

Three imaging tests and seven workflow tests cover hit testing, source/cache keys, hard edges/modes, repeated hover without repeated inference, native click/Undo/Redo/Actions, pending clicks, source/sample/tool/lifecycle invalidation, model failure, actual HTTP schemas/mask export/configuration/hover/select and invalid/stale/busy/refreshed/cancelled/revoked requests. The first build caught two test-helper access mistakes, preserved and repaired.70 focused tests pass. Escape received a dedicated synthetic event check. The offscreen canvas visibly shows the expected enlarged blue mask; several unshown native option controls still have blank interiors in snapshots, so complete control/live rendering remains unqualified and cosmetic work is deferred.

All70 final focused Debug and1920 full optimized tests pass. The universal macOS 14+ package verifies and includes195 Mask All Objects. Real local Vision detect/hit/select/save/Undo succeeds. All1480 frozen inputs,754 Rust source hashes and four protected files verify. Five code/test files were added,13 inputs modified and none removed. Universal extraction verifies arm64/x86_64, macOS 14 minimum, signature, version, licenses and icon. The Xcode project, root/installed app, user settings and version remain unchanged. Source and package identities are recorded in checkpoint196;195 evidence is annotated with this subsequent full qualification while its original checkpoint stays immutable.

The next major workflow is Select People. Adobe’s February23 workflow describes a thumbnail picker and whole-person/feature selection; the public Apple SDK supports person-instance masks on macOS 14. It does not itself provide semantic hair/beard/skin parts. The saved plan requires capability/model verification and honest unavailable parts rather than generic shapes presented as precise selection. No live desktop re-probe occurred while the desktop remains locked.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-196), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_196.json), [references](../PhotoCraftSwift/docs/OBJECT_FINDER_REFERENCES.json).

## 2026-10-27 — Step197: Select People

The native Object Selection options now open a person picker backed by Apple's macOS 14 person-instance request. It detects people separately from ordinary foreground objects, creates bounded thumbnails and previews actual masks on the canvas. Choose one or several people, apply New/Add/Subtract/Intersect with optional Hard Edge, or hand the resulting selection to Select and Mask for manual refinement. Hover, detection and picker state do not dirty the document; applying the union uses one Undo and Actions4 explicit coverage. Native32 remains unchanged.

Three matching APIs expose detection, hover and selection, with optional full-canvas UInt8 mask export and96px PNG thumbnails. Strict cache IDs, source/sample/layer/tool invalidation and cancellation/read/close/revocation guards keep results tied to the current image. Empty detections return an empty ready list; model failures remain visible. Hair/skin/facial features are explicitly unavailable because the Apple request does not provide those semantic labels. No new Adobe route or model equality is claimed.

The first compile found a SwiftUI binding through an immutable workspace reference. A mistakenly gated repair command did not apply before the second attempt; both failed logs remain. Explicit get/set binding repaired it. Seven new imaging/workflow tests plus shared selection/API regression coverage pass. Offscreen overlays are readable, but some unshown native controls remain blank, so full live/control rendering is not qualified. The desktop remains locked and was not re-probed.

All46 focused Debug and46 optimized tests pass;9 optimized menu checks also pass. Real local Vision finds1 person in a portrait and2 in an overlapping two-person photo; selection, source retention, native save and Undo/Redo succeed. Latest full1920-test/universal baseline196 excludes197. Timings in the model report include selection/archive/overlay work, not just inference. NASA images stay in local evidence with attribution/use provenance; they are not bundled or published. All1485 frozen inputs,754 original Rust hashes and four protected files verify. Five files added, nine modified inputs, none removed. Xcode project/version/root and installed apps/settings remain unchanged. Broad/full/universal qualification stays batched. Next: evaluate and verify a suitably licensed semantic model through native Core ML before exposing hair/skin/clothes classes; fine cosmetic/numerical details stay deferred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-197), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_197.json), [references](../PhotoCraftSwift/docs/PEOPLE_SELECTION_REFERENCES.json).

## 2026-10-27 — Step198: people feature segmentation

The native person picker now selects hair, face skin, body skin, clothes and accessories, independently or together, for selected people. Feature probability maps intersect Vision person instances; the existing selection modes, Hard Edge, refinement, Undo/Redo, Actions4 and native32 archive paths remain shared with the API. Missing or failing optional model resources leave whole-person selection available and disclose feature availability/errors. Fine facial labels remain unavailable.

Google's official Apache2.0 MediaPipe multiclass256 model was pinned by source SHA, with embedded class, normalization and SOFTMAX metadata verified. An independent bounded graph converter produces a macOS 14 Core ML MLProgram; the deployed app uses only Swift and Apple frameworks. Offline Python/TensorFlow tools regenerate the ignored resource and record provenance. Twelve comparisons, including photographs on CPU/all compute, match original-runtime classifications within declared numerical tolerances. The first converter failed on a scalar reduction axis; the first Swift build failed actor isolation. Both failures and passing repairs are preserved. Actual Swift inference matches original photo probabilities within0.000006974, and one/two-person selection/save/Undo checks pass. Native overlays were inspected; no pixel-perfect Adobe or live-desktop claim is made.

All61 focused Debug and1933 full optimized tests pass. The universal macOS 14+ package includes197 Select People and the native feature model; fresh extraction verifies both architectures, signature and model provenance. Xcode Debug build also passes. All1502 frozen inputs match the workspace/isolation. Seventeen newly covered inputs include existing NOTICE/.gitignore, generated native resources and new tooling; ten previously covered inputs changed and none were removed. NOTICE/.gitignore were modified, not newly created. The Xcode project deliberately gains a verified optional model resource phase; original bytes are retained. Root app/ZIP, user settings and754 original Rust hashes remain unchanged. No version change, publication or installation occurred. Independent platform, exact/model/default/persistence and live UI qualification remain open.

Next is G03 live shape drawing/editing, with native UI, history, persistence and API as one workflow. Existing rectangle/ellipse/path foundations and original Rust live-shape code can be reused; proprietary shape-library assets will not be copied. Fine semantic-mask and numerical/cosmetic refinement remains deferred under the major-first scheduling instruction.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-198), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_198.json), [references](../PhotoCraftSwift/docs/PEOPLE_FEATURE_REFERENCES.json).

## 2026-10-27 — Step199: native live shapes

The legacy rectangle/ellipse fill-only mouse-up path now uses native live geometry shared by seven tools: rectangle, ellipse, triangle, polygon, star, line/arrows and custom shapes. Retained components support boolean drawing, individual corners and parameter editing; fills and strokes support none, solid, gradient and embedded pattern paints, with alignment/dash/cap/join controls. Native properties preview and cancellation, shape/path/pixel output, custom preset definition/import/export, U-group integration, native33 saving and Actions5 shape recording accompany three API commands. Rasterize Shape uses the existing native raster/API engine. Rust geometry provenance remains explicit; no Adobe artwork/presets are redistributed.

Initial compiler/fixture failures were preserved and repaired. A background stack overflow revealed that nested Frame commands allocated the large primitive command dispatcher twice; indirect shape enum storage helped but did not resolve it. Separating modular dispatch from the primitive switch fixed the underlying nesting problem without dropping protection validation. A reused dictionary-only API decoder also raised an Objective-C exception for mode strings; the shape decoder now explicitly supports typed JSON fragments. All failed runs and diagnostic stacks remain in the199 evidence directory.

All80 focused Debug and1944 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1511 frozen inputs match the workspace and isolation;9 files added,26 changed and0 removed. Root app/ZIP, Xcode project, workspace preferences and754 original Rust source hashes remain unchanged. Native events and offscreen snapshots demonstrate functional integration; locked-session native chrome/text does not fully render in those snapshots, so no live visual qualification is claimed. Full editable PSD/.csh/gradient cross-profile transfers and precise Adobe output/default parity remain open. No version bump, installation, publication or commit occurred.

Next is the missing major Pen/Paths workflow. Fine shape rasterization/default/cosmetic refinements remain deferred under the maintainer's major-first instruction.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-199), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_199.json), [references](../PhotoCraftSwift/docs/SHAPE_REFERENCES.json).

## 2026-10-27 — Step200: native Pen and Paths

Freeform and Curvature Pen now join the P tool group. Freeform previews sampled geometry, fits editable cubic handles on release, extends endpoints and cancels without history. Curvature clicks interpolate smooth anchors, double-click toggles corners, clicking the first point closes a contour and anchors remain draggable. The Paths panel exposes selection tracing with tolerance, foreground fill and current-brush stroke with optional pressure simulation. All share existing saved/work paths, vector masks, native persistence and Undo. Five typed API commands expose the same engines, geometry, settings and state. Rust marching squares/fitting provenance is recorded.

Two compile attempts caught a shadowed error assignment and a test whitespace error. The first runtime suite exposed a shared API guard that rejected selected paths; a narrowly scoped path-context option repaired that without removing channel/mask/busy/revocation protection. Preserved failed attempts remain under the200 run directory.

All100 focused Debug and1951 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1518 frozen inputs match workspace/isolation;7 additions,12 modifications and0 removals are enumerated in changes01.json. Protected root app/ZIP, Xcode project, workspace preferences and754 original Rust hashes remain unchanged. Synthetic native events are functional evidence; the locked desktop was not re-probed. Full G04, exact Photoshop curve/pressure kernels, magnetic pen, multiple-anchor editing, advanced Fill/Stroke options, clipping exports and semantic Actions remain open. Next major breadth is multilingual/OpenType typography. No installation/publication/commit or version bump occurred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-200), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_200.json), [references](../PhotoCraftSwift/docs/PATH_WORKFLOW_REFERENCES.json).

## 2026-10-27 — Step201: native advanced typography

Vertical Type joins the T tool group with native editable point/paragraph text. Properties exposes OpenType features, variable axes and a language tag; the Glyphs panel pages installed fonts and inserts retained glyph identities at the text cursor. Font discovery and glyph insertion have typed APIs, while text creation/editing exposes the same options. The published Adobe text adapter accepts vertical orientation and small capitals through existing contract fields. Native34 and Actions6 retain advanced metadata; the bounded PSD subset retains orientation and represented flags and rejects metadata it cannot preserve.

The first two compile attempts caught CoreText option-set syntax and API range-type conversions. Focused runtime tests caught missing version34 reader allowlists. An initial ligature expectation used a font that did not provide that substitution on this host; an independent six-font probe established HelveticaNeue as the valid regression font. A new downgrade test needed property-list parsing. Final review repaired paragraph formatting loss on glyph insertion through shared desktop/API construction. Failed attempts and repairs remain individually saved.

All 70 focused Debug and 1959 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1524 source inputs match workspace/isolation;6 additions/23 modifications/0 removals are enumerated in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Tests prove host native rendering, metadata/Undo/API behavior and source-derived codec round trips; no live desktop, independent Photoshop output or physical platform certification is claimed. Application0.2.0build2 and the Xcode project remain unchanged; no installation, publication or commit. T04 path/warp text is next; minor utilities and exact/cosmetic refinements remain deferred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-201), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_201.json), [references](../PhotoCraftSwift/docs/ADVANCED_TYPOGRAPHY_REFERENCES.json).

## 2026-10-27 — Step202: editable shaped text

Text can follow a saved path, fit inside a closed shape, use fifteen preset warps, or dynamically fit Block, Circle, Arch and Bow layouts. A native workspace retains rich text beside the curved preview, layout controls, local Undo, canvas preview and one document transaction. Logical-origin compensation prevents normalized glyph bounds from moving the text anchor or its mask. The native API exposes the same layout engine through text.layout and complete text descriptions. Native35 and Actions7 retain geometry; unsupported editable PSD output fails explicitly.

The first five compile attempts caught Core Foundation casting, a test initializer, Observation declarations/initialization, a mutable detached-task capture and API helper mismatches. Runtime checks then found two inconsistent HTTP input error codes and an older test still rejecting newly supported archive35. Each attempt and repair is retained. Offscreen diagnostics show all seven layouts; the hidden-window native sheet is synthetic evidence, not a live desktop check.

All 89 focused Debug and 1966 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1530 frozen inputs match workspace/isolation;6 additions/27 modifications/0 removals are enumerated in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and the Xcode project remain unchanged; no installation, publication or commit. Full T04/Photoshop equality remains open. Filter Gallery is the next major family; minor typography utilities and numerical/cosmetic refinements remain deferred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-202), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_202.json), [references](../PhotoCraftSwift/docs/SHAPED_TEXT_REFERENCES.json).

## 2026-10-27 — Step203: native Filter Gallery

The47 original artistic effects are now Swift kernels with a native gallery workspace: category thumbnails rendered from the actual layer, parameter and color controls, effect ordering/visibility, before-after preview/zoom, local Undo and one document commit. Smart Objects retain source pixels and editable effects. Existing native filter APIs and Actions/Batch share the same command; native36 and Actions8 prevent older formats from silently discarding Gallery metadata. Exact Adobe ActionJSON and editable PSD mappings remain explicitly unsupported.

The first compile found a duplicate decoder variable. New engine/workspace/API tests then passed; broader regression checks found older assumptions that every filter used native15 or supported Adobe/PSD descriptors. Those qualification lists were corrected. An independent adapter executed the original unmodified Rust kernels and helper bodies, producing47 synthetic default fixtures: the Swift results match every RGBA8 byte. This is source-port evidence, not Photoshop equality. A hidden-window image verifies readable controls and layout; it is not a live desktop check.

All42 focused Debug and1973 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1589 frozen inputs match workspace/isolation;59 additions/20 modifications/0 removals are listed in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and Xcode project unchanged; no installation, publication or commit. The next major family is Smart Sharpen/Reduce Noise; minor variants and exact numerical/cosmetic polishing stay deferred.

[Development details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-203), [checkpoint](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_203.json), [references](../PhotoCraftSwift/docs/FILTER_GALLERY_REFERENCES.json).

## 2026-10-27 — Step204: paused with a current dashboard

The maintainer paused development after the verified Filter Gallery checkpoint and asked to see remaining work. The master goal is paused. Preserved exact package/source identity and the next Smart Sharpen/Reduce Noise plan. A current expandable dashboard distinguishes81 major,21 minor and3 final broad packages from285 partial/360 pending command statuses and282 wired/443 unavailable menu commands. Existing functions still need qualification inside those broad packages, so these are not percentage-complete estimates. The October9 snapshot remains unchanged. No application source or package changed.

[Pause checkpoint](../PhotoCraftSwift/docs/PAUSE_CHECKPOINT_204.json), [development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-204).

## 2026-10-27 — Step205: investigation paused, live dashboard reopened

A brief resumed Smart Sharpen/Reduce Noise source investigation produced no application changes or new builds. The maintainer requested pause again; the goal is paused and checkpoint203 remains the last verified implementation. Saved the exact next-major work and opened the existing live dashboard against the current project. Its105 open broad packages include implemented capabilities still awaiting strict parity qualification. Source and package hashes remain unchanged.

[Pause checkpoint](../PhotoCraftSwift/docs/PAUSE_CHECKPOINT_205.json), [development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-205).

## 2026-10-27 — Step206: native photo detail workflows

The maintainer explicitly resumed development. Smart Sharpen and Reduce Noise now have native controls, preview at Fit/100%, Cancel/local Undo, one document commit and editable Smart Filters. Gaussian sharpening and guided denoising follow the original Rust approach; Lens/Motion use actual native disk/line deconvolution. Tonal fades, JPEG-grid softening and additional RGB channel denoising are available. Native37/Actions9 and the shared Photato API retain the new settings. Exact Adobe descriptors and editable PSD remain unqualified and reject explicitly.

The first compile exposed grouped Observation properties; splitting them repaired it. Integration tests initially referenced two wrong API names; these were corrected with failures retained. All45 focused checks pass, including noise/edge behavior, blur direction, depth/alpha, desktop/API equivalence, history, persistence, cancellation and rejection guards. Both offscreen panels were inspected. An API review also caught unnecessary internal fields in the preview-state payload. The first full build was stopped and retained, then the payload and a public round-trip check were repaired before restarting. All45 final focused Debug and1980 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1595 frozen inputs match the tested source;6 additions/19 modifications/0 removals are listed in changes02.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and Xcode project unchanged. The next major workflow plan covers Lens Blur depth maps and iris controls.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-206), [scope and evidence](../PhotoCraftSwift/docs/PHOTO_DETAIL_REFERENCES.json).

[Verified checkpoint206](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_206.json).

## 2026-10-27 — Step207: native Lens Blur

Implemented iris/depth/highlight/noise controls with native preview, focus picking, local history, one commit and API support. Live mask/channel references remain editable; invalid sources or source deletion reject. Native38 and Actions10 preserve settings. Adobe excludes Lens Blur from Smart Filters, so Photato's editable version is explicitly a native extension.

All53 focused and1990 full optimized tests pass. Early failures, including a real background stack overflow in nested Smart Filter mask dispatch, were preserved and repaired. Offscreen layout was inspected. Production packaging was batched with the user's208 title/overflow fixes; the combined208 universal package now verifies. Full Photoshop parity remains open. [Evidence](../PhotoCraftSwift/docs/LENS_BLUR_REFERENCES.json).

## 2026-10-27 — Step208: title and viewport corrections

The user requested `Photato - <current doc name>` and supplied a screenshot of canvas content covering window controls. Read-only live inspection and a failing pixel-boundary regression confirmed the overflow. Added view/layer clipping and a saved CGContext clip around the full draw pass. Window titles now update with active tabs and document names; native API state exposes the same title. The first resized fixture misinterpreted bitmap Y coordinates; its repaired rerun proves no pixels escape the viewport. Failure evidence is preserved.

All 59 focused Debug and 1,991 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1,601 frozen inputs match workspace/isolation; one test file added, six files modified, none removed. Four protected files and754 original Rust hashes remain unchanged. Separate current Debug live checks cover title,200% zoom, horizontal/vertical scrolling and actual native window resizing. No user document input/edit/save; validation app exited. Application0.2.0build2 and Xcode project unchanged. The current Lens Blur work is included in this package. [Evidence](../PhotoCraftSwift/docs/WINDOW_PRESENTATION_REFERENCES.json), [checkpoint208](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_208.json).

## 2026-10-27 — Step209: Photato identity cleanup

At the maintainer’s request, removed the retired family identity from About, demo names, project documentation, the diary and archived text copies. Photato retains its own name, supplied icon and original PhotoCraft attribution. Renamed owned TIFF fixture group metadata without changing image samples. All50 focused checks pass, including TIFF decoding/pixels, gradient presets, support links and window/viewport regressions. The refreshed universal macOS 14+ app verifies after extraction; its contents have no retired branding. Earlier208 full1991-test results remain historical. Archived signed binaries and screenshots are retained as historical evidence. The repository stays private until the software’s release day, when it will become public.

## 2026-10-27 — Step210: the developer diary on the website

The maintainer requested an elegant way to read the developer diary from the Photato website. The website now presents210 dated, expandable entries with local search, chronological sorting, keyboard access, stable per-entry links and a downloadable narrative diary. The existing Forensic Intelligence visual style is retained. Desktop and320/390px mobile views were inspected; search, empty state, sorting, permalinks and mobile navigation pass with no browser warnings/errors. The GitHub repository already exists; it remains private during development and will become public on the same day the software is released. The website is saved locally for the maintainer to publish.

## 2026-10-27 — Step211: private GitHub development build

At the maintainer's request, the verified universal macOS 14+ development build is now attached to a private GitHub draft release. It includes Lens Blur, the document window title and canvas containment fixes, and the current branding cleanup. The repository remains private until software release day.

A fresh extraction verifies the signature, executable hash and both architectures. All four uploaded assets were downloaded again and their hashes match. The package is ad-hoc signed, not notarized or App Store signed. The 50 focused tests apply to this snapshot; the preceding 1,991-test full run is historical. Full Photoshop parity and the physical platform matrix remain open. The release notes explicitly state that local build sources are newer than GitHub main; this build-only upload does not push source changes. [Private draft release](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-04479448d8da0ffe8270). [Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-211).

## 2026-10-27 — Step212: distortion workflows and window-build handoff

Displace, Shear, Wave, Pinch, Spherize, Twirl, Ripple, Polar Coordinates and ZigZag now have native Swift settings, previews, Cancel/Undo and editable Smart Filters. Displacement maps stay embedded with the document; Shear curves can be edited directly. The Photato API shares the same operations. Native39 and Actions11 preserve the new settings. The first integration attempts exposed a Swift getter, a test comparison and missing archive negotiation paths; each failed attempt was preserved and repaired. The full run also found two outdated version expectations, corrected before the final run.

All45 focused checks and2,003 final full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. Adobe's observed dialogs informed controls and parameter ranges; exact Photoshop pixels, action descriptors, editable PSD interchange, live native filters and the physical platform matrix remain unqualified. Other major F02 filter families remain open.

The maintainer's recurring workspace-overlap screenshot was traced to an older test app still running before the clipping fix. Its document was saved separately, and the verified corrected build was installed alongside it. The title appears correctly, but the Mac locked before the same-document zoom/scroll check and handoff could finish. That live check remains pending; automated containment checks pass.

The diary overview was checked at desktop and phone widths, with five readable numbered steps and no horizontal page overflow. At the maintainer’s request, it explains the actual engineering process, licensed PhotoCraft provenance, public specifications, black-box comparisons and saved-file analysis. It explicitly excludes decompiling/disassembling Photoshop or copying proprietary Adobe implementation code. It does not assert a formal clean-room separation or the unsupported broader statement that no reverse engineering of any kind occurred. [Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-212).

## 2026-10-27 — Step213: native Pixelate workflows

Color Halftone, Crystallize, Facet, Fragment, Mezzotint and Pointillize now run in native Swift. Facet and Fragment apply immediately; the other four have settings, previews and local Undo. Smart Filters keep their source and editable parameters. Native40 and Actions12 save those settings, and the Photato API uses the same commands as the desktop. Pointillize captures the current background color; seeded patterns make repeatable renders possible.

Eighteen synthetic reference images produced by the original, unmodified Rust filter source match byte-for-byte. The first focused run exposed unnecessary sparse-tile allocation on an unchanged white image; that was repaired without changing expected pixel output. All68 final focused checks and2,015 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. Hosted workspace images were inspected; they are not live interaction evidence.

Adobe's published API lists these filter families but requires recorded action descriptors. Those mappings and editable PSD interchange remain incomplete. Exact Photoshop pixels/defaults/depth availability, live interactions and the physical platform matrix also remain open. Other major F02 workflows are still outstanding; the next family is Stylize.

The recurring workspace-overlap report remains a delivery handoff in progress. The older test app is still running; the corrected installed build and saved copy of its document retain their verified hashes. Automated canvas-containment checks pass. The Mac remains locked, so reopening that document, checking zoom/scroll/resize and safely closing the obsolete test window still await unlock. No new live pass is claimed. [Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-213).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-07.md) · [Next page](part-05.md)
