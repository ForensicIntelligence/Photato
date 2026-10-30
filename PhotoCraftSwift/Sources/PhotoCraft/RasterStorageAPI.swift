import Foundation
import PhotoCraftCore

/// Observable storage budgets are separate from logical canvas geometry.
enum RasterStorageAPI {
  static var stateSchema: [String: Any] { ["type":"object","additionalProperties":false,
    "required":["heapEstimateBytes","referencedMappedSampleBytes","durable"],
    "properties":["heapEstimateBytes":["type":"integer","minimum":0],
      "referencedMappedSampleBytes":["type":"integer","minimum":0],"durable":["const":false]]] }
  static func state(_ d: CraftDocument) -> [String: Any] {
    ["heapEstimateBytes":d.estimatedBytes,"referencedMappedSampleBytes":d.mappedRasterBytes,"durable":false]
  }
  static var capabilities: [String: Any] { ["stateSchema":stateSchema,
    "maximumDimension":Surface.maxDimension,"logicalMaximumPixels":Surface.maxPixels,
    "nativePagedInput":["chunkedVersions":"11 through62","tileReferenceHeapEstimateBytes":128,
      "nativeFileMaximumBytes":NativeArchive.maximumFileBytes,"nativeDataMaximumBytes":NativeArchive.maximumBytes,"dataAndFile":true,
      "integrity":"Every unique raster blob hash and finite sample is checked before immutable scratch publication; repeated digests share one mapped tile. File reads retain identity checks. Legacy inline archives keep decoded-data budgets.",
      "limits":"File admission is4TiB with bounded reads/writes; metadata and Data containers remain512MiB. Flat manifest/blob index and65536 unique-blob limit remain. Metadata buffers and OS-managed mapped pages are separate from the owned-sample estimate. Recovery admission still uses its separately qualified policy."],
    "tileSide":Surface.tileSide,"maximumImageIOConversionPatchPixels":2048*64,
    "maximumFloat32ProviderBytes":1_073_741_824,"scratchMaximumBytes":RasterTileStore.defaultMaximumBytes,
    "sampleStorage":"Immutable private unlinked mapped tiles. A pixel edit promotes only touched tiles to COW heap buffers; native archives retain portable sample bits.",
    "accounting":"heapEstimateBytes includes owned sample buffers and mapped-tile index estimates; referencedMappedSampleBytes sums tile references, not physical disk usage or RSS. macOS manages mapped-page residency.",
    "limits":"ImageIO can retain a decoded source/cache. TIFF strip codecs remain bounded to512MiB per strip. Native file transactions admit4TiB; native Data/metadata and PSD/PSB retain512MiB limits; paged chunked native input budgets tile references plus owned non-raster data, while legacy/history/recovery policies retain decoded budgets. Hierarchical indexes, durable scratch recovery, streamed large PSB and general large-document operations remain open.",
    "adobe":"No new endpoint. Existing resource jobs share raster decoding and retain their separately pinned input/output and job budgets."] }
}
