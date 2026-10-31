import Foundation
import PhotoCraftCore

/// Observable storage budgets are separate from logical canvas geometry.
enum RasterStorageAPI {
  static var stateSchema: [String: Any] { ["type":"object","additionalProperties":false,
    "required":["heapEstimateBytes","referencedMappedSampleBytes","referencedMappedIndexBytes","durable"],
    "properties":["heapEstimateBytes":["type":"integer","minimum":0],
      "referencedMappedSampleBytes":["type":"integer","minimum":0],"referencedMappedIndexBytes":["type":"integer","minimum":0],"durable":["const":false]]] }
  static func state(_ d: CraftDocument) -> [String: Any] {
    ["heapEstimateBytes":d.estimatedBytes,"referencedMappedSampleBytes":d.mappedRasterBytes,"referencedMappedIndexBytes":d.mappedRasterIndexBytes,"durable":false]
  }
  static var capabilities: [String: Any] { ["stateSchema":stateSchema,
    "maximumDimension":Surface.maxDimension,"logicalMaximumPixels":Surface.maxPixels,
    "nativePagedInput":["chunkedVersions":"11 through63","tileReferenceHeapEstimateBytes":Surface.smallMappedReferenceAdmissionBytes,
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
    "limits":"ImageIO can retain a decoded source/cache. TIFF strip codecs remain bounded to512MiB per strip. Native file transactions admit4TiB; native Data/metadata and PSD/PSB retain512MiB limits; paged chunked native input budgets tile references plus owned non-raster data, while legacy/history/recovery policies retain decoded budgets. Metadata streaming, mip pyramids, durable scratch recovery, streamed large PSB and general large-document operations remain open.",
    "adobe":"No new endpoint. Existing resource jobs share raster decoding and retain their separately pinned input/output and job budgets."] }
}
