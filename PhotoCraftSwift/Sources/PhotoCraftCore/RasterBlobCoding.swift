import Foundation

/// Internal coding contexts. Portable archives supply owned, validated byte ranges;
/// ephemeral history supplies owned blobs. Neither accepts external filenames.
protocol RasterBlobEncoding: AnyObject {
  func storeBytes(_ data: Data) throws -> String
}
protocol RasterBlobDecoding: AnyObject {
  func bytes(_ digest: String, maximumBytes: Int) throws -> Data
  func tile(_ digest: String) throws -> [Pixel]
}

/// Chunked native input can publish checked immutable tiles directly to scratch.
/// Ordinary history and legacy providers retain their owned-sample budget.
protocol MappedRasterBlobDecoding: RasterBlobDecoding {
  var usesMappedTiles: Bool { get }
  func storedTile(_ digest: String) throws -> RasterTile
}

/// Version63 uses compact ordinal pages instead of a manifest key per tile.
protocol IndexedRasterBlobEncoding: RasterBlobEncoding {
  func storeOrdinal(_ data: Data) throws -> UInt64
}
protocol IndexedRasterBlobDecoding: MappedRasterBlobDecoding {}

/// Raw component pages are distinct from RGBA Pixel tile payloads. Older archive
/// versions keep their original whole-plane layout and cannot opt into this key.
protocol ComponentBlobEncoding: RasterBlobEncoding {
  var supportsComponentPages: Bool { get }
}
protocol ComponentBlobDecoding: RasterBlobDecoding {
  var supportsComponentPages: Bool { get }
  var usesMappedComponents: Bool { get }
  func reserveComponentScratch(bytes: Int) throws
}

final class ComponentScratchBudget {
  private let limit: Int
  private var used = 0
  init(limit: Int = RasterTileStore.defaultMaximumBytes) { self.limit = limit }
  func reserve(_ bytes: Int) throws {
    guard bytes >= 0, bytes <= limit - used else {
      throw RasterScratchFailure.capacity(requiredBytes: used.addingReportingOverflow(bytes).overflow ? Int.max : used + bytes, limitBytes: limit)
    }
    used += bytes
  }
}
