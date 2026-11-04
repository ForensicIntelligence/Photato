import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Observable storage budgets are separate from logical canvas geometry.
enum RasterStorageAPI {
  static var stateSchema: [String: Any] { ["type":"object","additionalProperties":false,
    "required":["heapEstimateBytes","referencedMappedSampleBytes","referencedMappedIndexBytes","nativeComponentLogicalBytes","mappedNativeComponentVirtualBytes","durable"],
    "properties":["heapEstimateBytes":["type":"integer","minimum":0],
      "referencedMappedSampleBytes":["type":"integer","minimum":0],"referencedMappedIndexBytes":["type":"integer","minimum":0],"nativeComponentLogicalBytes":["type":"integer","minimum":0],"mappedNativeComponentVirtualBytes":["type":"integer","minimum":0],"durable":["const":false]]] }
  static func state(_ d: CraftDocument) -> [String: Any] {
    ["heapEstimateBytes":d.estimatedBytes,"referencedMappedSampleBytes":d.mappedRasterBytes,"referencedMappedIndexBytes":d.mappedRasterIndexBytes,"nativeComponentLogicalBytes":d.nativeComponentLogicalBytes,"mappedNativeComponentVirtualBytes":d.mappedNativeComponentVirtualBytes,"durable":false]
  }
  static var capabilities: [String: Any] { ["stateSchema":stateSchema,
    "maximumDimension":Surface.maxDimension,"logicalMaximumPixels":Surface.maxPixels,
    "pagedComposition":["mode":"RGB8/16/32","maximumPatchPixels":Renderer.maximumCompositionPatchPixels,
      "unfeatheredVectorMasks":true,"vectorCoverageMaximumPatchPixels":131_072,
      "vectorGrayScratchMaximumLogicalBytes":Surface.maxPixels,"vectorCoordinateBlockSide":16_384,
      "vectorGrayScratchMaximumBytes":Surface.maxPixels+Surface.maxDimension,
      "vectorGrayScratchPreparation":"Checked bounded zero writes and synchronization prepare active drawing rectangles plus a guard row before native mapped drawing. Admission/I/O failure discards derived output; the original model is unchanged by rendering.",
      "maximumDerivedMaskCacheBytes":Renderer.maximumCompositionMaskCacheBytes,
      "behavior":"The shared native renderer composes groups, clipping, adjustments and supported raster/procedural/affine content in bounded document-coordinate patches into immutable sample/index pages. Eligible coordinate-independent full-canvas stacks merge allocated tile keys and evaluate the implicit background through that same renderer; spatial/dithered sources retain complete patch evaluation.",
      "accounting":"The mask cache limit is a conservative derived-buffer estimate, separate from source aliases, transient compositor/kernel buffers, scratch and OS-managed mapped residency. No whole-canvas descriptor Set or reduced proxy document is used.",
      "vectorCoverage":"Large unfeathered vector masks and path selections use private unlinked file-backed GRAY8, native16K coordinate blocks and bounded immutable output transfers. The gray virtual extent is at most90GB, distinct from physical file allocation, owned heap, native internal buffers and OS-managed mapped residency. Empty/full rectangles stay implicit. Sparse eligible stacks merge vector tile keys and retain actual global opacity. Quantized output currently uses RGBA Float sample tiles; exact Photoshop and cross-block antialiasing remain unqualified.",
      "limits":"Large layer styles, feathered vector masks, oversized feather/local raster planes, Smart Filter/Warp preparation and non-RGB modes retain independent limits. Full dense90GP/4TiB, Photoshop pixel/filter fidelity, frame rate and physical supported-platform qualification remain open."],
    "nativePagedInput":["chunkedVersions":"11 through86","componentPageVersion":86,"componentBlockSamples":4096,"componentPageLeafEntries":1024,"componentPageBranchEntries":256,"componentPageMaximumLevel":2,"componentApplicationMaximumPixels":NativeModeRaster.maximumDocumentPixels,"componentDenseOperationMaximumPixels":NativeModeRaster.maximumPixels,"componentScratchAdmission":"Shares the decode disk allowance with RGBA samples. Raw little-endian component pages validate finite values, alpha, padding, ordered ranges and exact subtree counts before immutable publication; legacy versions keep whole-plane admission.","pagedSelectionVersion":64,"tileReferenceHeapEstimateBytes":Surface.smallMappedReferenceAdmissionBytes,
      "tileReferenceHeapEstimateNotice":"Small direct-reference admission per tile. Large mapped surfaces use the paged-runtime policy below; runtime estimates are not RSS.",
      "runtimeTileIndex":["minimumTiles":Surface.pagedIndexMinimumTiles,"directWorkingSetMaximumTiles":Surface.directTileIndexLimit,"recordBytes":Surface.runtimeIndexRecordBytes,"maximumWriteBytes":Surface.runtimeIndexWriteBufferBytes,"copyOnWriteLevels":4,"maximumNodeChildren":256,"orderedRangeLookup":true,"sharedBaseAndHistory":true,"nativeFileSaveVersion":63],
      "tileOrdinalReuse":["scope":"One native63 paged decode","persistentForDecode":true,"recordBytes":NativeArchive.indexedTileCacheRecordBytes,"frontCacheEntries":NativeArchive.indexedTileCacheFrontEntries,"storage":"Private unlinked sparse readonly mapped descriptors, checked writes, retained immutable sample segments","scratchPolicy":"One decoded sample allocation per distinct raster blob ordinal; repeated references reuse checked samples. Owned decoding keeps its bounded front cache."],
      "indexedArchiveVersion":63,"indexLeafRecords":1024,"indexBranchReferences":256,"indexCacheNodes":8,"tilePageEntries":1024,
      "nativeFileMaximumBytes":NativeArchive.maximumFileBytes,"nativeDataMaximumBytes":NativeArchive.maximumBytes,"dataAndFile":true,
      "integrity":"Every referenced raster blob hash and finite sample is checked before immutable scratch publication. Legacy input shares unique digests;63 paged decoding reuses checked immutable samples for every repeated tile ordinal throughout that decode. File reads retain identity checks. Legacy inline archives keep decoded-data budgets.",
      "limits":"File admission is4TiB with bounded reads/writes; metadata and Data containers remain512MiB. Versions11…62 retain their flat65536-blob table; version63 uses bounded authenticated index nodes and1024-entry raster pages. Large mapped surfaces use an immutable runtime index and persistent COW edit paths. Document metadata and legacy-key decoding/sorting remain resident; edit metadata grows with touched tiles. Metadata buffers and OS-managed mapped pages are separate from the owned-sample estimate. Recovery admission still uses its separately qualified policy."],
    "tileSide":Surface.tileSide,"maximumImageIOConversionPatchPixels":2048*64,
    "maximumFloat32ProviderBytes":1_073_741_824,"scratchMaximumBytes":RasterTileStore.defaultMaximumBytes,
    "sampleStorage":"Immutable private unlinked mapped tiles. Paged runtime indexes retain immutable16-byte descriptors; their pixel edits copy at most four radix nodes and promotes only touched tiles to COW heap buffers; native archives retain portable sample bits.",
    "accounting":"heapEstimateBytes retains direct working-set sample/reference accounting and adds conservative paged tree/retained-segment estimates. referencedMappedSampleBytes and referencedMappedIndexBytes sum references to OS-managed mapped pages; neither measures physical disk usage or RSS. macOS manages mapped-page residency.",
    "limits":"ImageIO can retain a decoded source/cache. TIFF strip codecs remain bounded to512MiB per strip. Native/PSB files admit4TiB and PSD files2GiB; Data/retained metadata remain512MiB. Paged native input budgets tile references plus owned non-raster data, while legacy/history/recovery policies retain separate admission. Metadata streaming, mip pyramids, durable scratch recovery and general large-document/mode/operation capacity remain open.",
    "adobe":"No new endpoint. Existing resource jobs share raster decoding and retain their separately pinned input/output and job budgets."] }
}
