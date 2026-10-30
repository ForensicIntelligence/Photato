import Foundation

extension NativeArchive {
  /// Explicit paged reads account mapped tile references against the owned-heap
  /// estimate, while scratch samples have their own disk allowance. macOS controls
  /// mapped-page residency. Legacy inline archives keep their decoded-sample limit.
  public static func decodePaged(_ data: Data, heapByteLimit: Int = 1_073_741_824,
    scratchByteLimit: Int = RasterTileStore.defaultMaximumBytes,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes) throws -> CraftDocument {
    try validatePagedOptions(heapByteLimit, scratchByteLimit, maximumMetadataBytes)
    try Task.checkCancellation()
    guard data.starts(with: NativeChunkedArchive.magic) else {
      guard data.count <= maximumMetadataBytes else {
        throw NativeArchiveMemoryLimit.metadata(requiredBytes:data.count,limitBytes:maximumMetadataBytes)
      }
      return try decode(data,rasterByteLimit:heapByteLimit)
    }
    return try NativeChunkedArchive.decodeRecovery(count:data.count,rasterByteLimit:heapByteLimit,
      maximumMetadataBytes:maximumMetadataBytes,backing:RasterTileStore(maximumBytes:scratchByteLimit)) { offset,count in
        guard offset >= 0,count >= 0,offset <= data.count,count <= data.count-offset else {
          throw CraftError.invalid("Invalid native archive range.")
        }
        let start=data.startIndex+offset
        return data.subdata(in:start..<start+count)
      }.document
  }
  public static func readPaged(_ url: URL, heapByteLimit: Int = 1_073_741_824,
    scratchByteLimit: Int = RasterTileStore.defaultMaximumBytes,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes) throws -> CraftDocument {
    try readRecoveryPaged(url,heapByteLimit:heapByteLimit,scratchByteLimit:scratchByteLimit,
      maximumMetadataBytes:maximumMetadataBytes).document
  }
  public static func readRecoveryPaged(_ url: URL, heapByteLimit: Int = 1_073_741_824,
    scratchByteLimit: Int = RasterTileStore.defaultMaximumBytes,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes) throws -> RecoveryContents {
    try validatePagedOptions(heapByteLimit,scratchByteLimit,maximumMetadataBytes)
    return try NativeArchiveFileSource.withStableMetadata {
      let source=try NativeArchiveFileSource(url,maximumBytes:NativeArchive.maximumFileBytes)
      let result:RecoveryContents
      if try source.read(at:0,count:min(source.count,NativeChunkedArchive.magic.count)) == NativeChunkedArchive.magic {
        result=try NativeChunkedArchive.decodeRecovery(count:source.count,rasterByteLimit:heapByteLimit,
          maximumMetadataBytes:maximumMetadataBytes,backing:RasterTileStore(maximumBytes:scratchByteLimit),
          maximumFileBytes:NativeArchive.maximumFileBytes) {
            try source.read(at:$0,count:$1)
          }
      } else {
        guard source.count <= min(maximumMetadataBytes,NativeArchive.maximumBytes) else {
          throw NativeArchiveMemoryLimit.metadata(requiredBytes:source.count,limitBytes:maximumMetadataBytes)
        }
        result = .init(document:try decode(Data(contentsOf:url,options:.mappedIfSafe),rasterByteLimit:heapByteLimit),context:nil,invalidContext:false)
      }
      try source.validateUnchanged()
      return result
    }
  }
  private static func validatePagedOptions(_ heap:Int,_ scratch:Int,_ metadata:Int) throws {
    guard (0...1_073_741_824).contains(heap),(0...RasterTileStore.defaultMaximumBytes).contains(scratch),
      (0...NativeArchive.maximumBytes).contains(metadata) else { throw CraftError.invalid("Invalid paged native read budget.") }
  }
}
