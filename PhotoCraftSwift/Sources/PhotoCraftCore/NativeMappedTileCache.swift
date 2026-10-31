import Darwin
import Foundation

extension NativeArchive {
  public static let indexedTileCacheRecordBytes = 8
  public static let indexedTileCacheFrontEntries = 256
}

/// Decode-local ordinal reuse, independent of the portable archive. Sparse slots
/// stay in an unlinked file; only sample segments have resident references.
/// Serial use, like the enclosing property-list decoder. Never persisted/shared.
final class NativeMappedTileCache {
  static let recordBytes = NativeArchive.indexedTileCacheRecordBytes
  static let baseResidentEstimate = 512
  private let fd: Int32
  private let address: UnsafeMutableRawPointer?
  let mappedBytes: Int
  let records: UInt64
  private let reserveSegment: (Int) throws -> Void
  private let write: (Int32, UnsafeRawPointer, Int, off_t) -> Int
  private var segments: [RasterScratchSegment] = []
  private var identifiers: [ObjectIdentifier: UInt32] = [:]
  private var failed = false
  var residentEstimate: Int { Self.baseResidentEstimate + segments.count * 128 }
  init(records: UInt64, directory: URL? = nil,
       reserveSegment: @escaping (Int) throws -> Void = { _ in },
       write: @escaping (Int32, UnsafeRawPointer, Int, off_t) -> Int = { pwrite($0,$1,$2,$3) }) throws {
    try Task.checkCancellation()
    guard records <= UInt64(Int.max / Self.recordBytes) else {
      throw CraftError.invalid("Native ordinal cache size overflow.")
    }
    let folder = directory ?? FileManager.default.temporaryDirectory
    guard folder.isFileURL else { throw CraftError.invalid("Native ordinal cache requires a local directory.") }
    let url = folder.appendingPathComponent("photato-native-ordinals-\(UUID().uuidString).tmp")
    let descriptor = url.withUnsafeFileSystemRepresentation {
      open($0!,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,S_IRUSR|S_IWUSR)
    }
    guard descriptor >= 0 else { throw RasterScratchFailure.io(operation:"ordinal cache creation",code:errno) }
    guard url.withUnsafeFileSystemRepresentation({ unlink($0!) }) == 0 else {
      let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"ordinal cache unlink",code:code)
    }
    let size = Int(records) * Self.recordBytes
    guard ftruncate(descriptor,off_t(size)) == 0 else {
      let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"ordinal cache growth",code:code)
    }
    var mapping: UnsafeMutableRawPointer?
    if size > 0 {
      mapping = mmap(nil,size,PROT_READ,MAP_SHARED,descriptor,0)
      guard let mapping,mapping != MAP_FAILED else {
        let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"ordinal cache mapping",code:code)
      }
      _ = madvise(mapping,size,MADV_RANDOM)
    }
    self.fd=descriptor;self.address=mapping;self.mappedBytes=size;self.records=records
    self.reserveSegment=reserveSegment;self.write=write
  }
  deinit { if let address { munmap(address,mappedBytes) };close(fd) }
  private func check(_ ordinal: UInt64) throws {
    try Task.checkCancellation()
    guard !failed,ordinal < records else { throw CraftError.invalid("Invalid native ordinal cache lookup or lifecycle.") }
  }
  func tile(at ordinal: UInt64) throws -> RasterTile? {
    try check(ordinal)
    let code=UInt64(littleEndian:address!.loadUnaligned(fromByteOffset:Int(ordinal)*Self.recordBytes,as:UInt64.self))
    guard code != 0 else { return nil }
    let location=code-1,segment=Int(location>>32),offset=Int(location&0xffffffff)
    // Only store() publishes records, after validating these retained mappings.
    guard segment < segments.count,offset <= segments[segment].length-TileArchive.byteCount else {
      throw CraftError.invalid("Invalid native ordinal cache descriptor.")
    }
    return RasterTile(segment:segments[segment],offset:offset)
  }
  func store(_ tile: RasterTile,at ordinal: UInt64) throws {
    do {
      try check(ordinal)
      guard try self.tile(at:ordinal) == nil,let segment=tile.segment,
            tile.count == TileArchive.pixelCount,tile.offset >= 0,
            tile.offset % TileArchive.byteCount == 0,tile.offset <= Int(UInt32.max),
            tile.offset <= segment.length-TileArchive.byteCount else {
        throw CraftError.invalid("Invalid or repeated native ordinal cache entry.")
      }
      let identity=ObjectIdentifier(segment),number:UInt32
      if let existing=identifiers[identity] { number=existing }
      else {
        guard segments.count < Int(UInt32.max) else { throw CraftError.invalid("Too many native ordinal cache segments.") }
        try reserveSegment(128);number=UInt32(segments.count)
        segments.append(segment);identifiers[identity]=number
      }
      var code=(((UInt64(number)<<32)|UInt64(tile.offset))+1).littleEndian
      // Readonly mapping + checked pwrite avoids writable-mmap SIGBUS on disk
      // exhaustion. A failed/partial write poisons this decode-local cache.
      try withUnsafeBytes(of:&code) { bytes in
        var done=0
        while done < Self.recordBytes {
          try Task.checkCancellation()
          let n=write(fd,bytes.baseAddress!.advanced(by:done),Self.recordBytes-done,off_t(Int(ordinal)*Self.recordBytes+done))
          if n < 0 && errno == EINTR { continue }
          guard n > 0,n <= Self.recordBytes-done else {
            throw RasterScratchFailure.io(operation:"ordinal cache write",code:n == 0 ? EIO:errno)
          }
          done += n
        }
      }
    } catch { failed=true;throw error }
  }
}
