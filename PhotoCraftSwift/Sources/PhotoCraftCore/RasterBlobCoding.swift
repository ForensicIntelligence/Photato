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
