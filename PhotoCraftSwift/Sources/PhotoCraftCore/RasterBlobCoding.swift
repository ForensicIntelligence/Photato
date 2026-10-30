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
