import Darwin
import Foundation

/// Private, process-local metadata. Each immutable record is (tile key, segment/offset).
/// Samples and index pages can be reclaimed independently by the VM system.
final class RuntimeTileIndex: @unchecked Sendable {
  static let recordBytes = 16
  static let maximumEntries = 21_977_344 // ceil(300000/64)^2
  static let writeBufferBytes = 65_536
  let count: Int
  let segments: [RasterScratchSegment]
  private let file: RuntimeIndexFile
  private let address: UnsafeMutableRawPointer?
  private let firstKey:Int
  private let contiguous:Bool
  var mappedBytes: Int { count * Self.recordBytes }
  var residentEstimate: Int { 512 + segments.count * 128 }
  var maximumKey: Int { count == 0 ? -1 : key(at:count-1) }
  fileprivate init(file: RuntimeIndexFile, count: Int, segments: [RasterScratchSegment]) throws {
    self.file=file;self.count=count;self.segments=segments
    if count == 0 { address=nil;firstKey=0;contiguous=true;return }
    let pointer=mmap(nil,count*Self.recordBytes,PROT_READ,MAP_SHARED,file.fd,0)
    guard let pointer,pointer != MAP_FAILED else { throw RasterScratchFailure.io(operation:"index mapping",code:errno) }
    address=pointer;_ = madvise(pointer,count*Self.recordBytes,MADV_RANDOM)
    firstKey=Int(UInt64(littleEndian:pointer.loadUnaligned(as:UInt64.self)))
    let last=Int(UInt64(littleEndian:pointer.loadUnaligned(fromByteOffset:(count-1)*16,as:UInt64.self)))
    // Builder guarantees unique, strictly increasing keys. The endpoint span
    // proves dense runs without another scan or resident per-tile cache.
    contiguous=last-firstKey==count-1
  }
  deinit { if let address { munmap(address,mappedBytes) } }
  func withUnsafeRecordBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
    try body(UnsafeRawBufferPointer(start:address,count:mappedBytes))
  }
  func key(at index: Int) -> Int {
    precondition(index >= 0 && index < count)
    return Int(UInt64(littleEndian:address!.loadUnaligned(fromByteOffset:index*16,as:UInt64.self)))
  }
  func lowerBound(_ key: Int) -> Int {
    if contiguous {
      if key<=firstKey {return 0}
      if key>=firstKey+count {return count}
      return key-firstKey
    }
    var low=0,high=count
    while low<high { let mid=low+(high-low)/2;if self.key(at:mid)<key {low=mid+1}else{high=mid} }
    return low
  }
  func tile(at index: Int) -> RasterTile {
    precondition(index >= 0 && index < count)
    let location=UInt64(littleEndian:address!.loadUnaligned(fromByteOffset:index*16+8,as:UInt64.self))
    let segment=Int(location>>32),offset=Int(location&0xffffffff)
    // Records are produced only by Builder after validating this exact retained mapping.
    precondition(segment<segments.count && offset<=segments[segment].length-TileArchive.byteCount)
    return RasterTile(segment:segments[segment],offset:offset)
  }
  func tile(for key: Int) -> RasterTile? {
    let index=lowerBound(key);return index<count && self.key(at:index)==key ? tile(at:index):nil
  }
  final class Builder {
    private let file: RuntimeIndexFile
    private let maximumBytes: Int
    private let reserveSegment: (Int) throws -> Void
    private var retained: [RasterScratchSegment]=[]
    private var identifiers: [ObjectIdentifier:UInt32]=[:]
    private var buffer=Data()
    private var written=0,lastKey = -1,finished=false,failed=false
    private(set) var count=0
    private(set) var maximumPhysicalWrite=0
    init(maximumBytes: Int = RuntimeTileIndex.maximumEntries*16, directory: URL? = nil,
         reserveSegment: @escaping (Int) throws -> Void = { _ in }) throws {
      guard maximumBytes>=0,maximumBytes<=RuntimeTileIndex.maximumEntries*16 else {throw CraftError.invalid("Invalid runtime index capacity.")}
      file=try RuntimeIndexFile(directory:directory);self.maximumBytes=maximumBytes;self.reserveSegment=reserveSegment
      buffer.reserveCapacity(RuntimeTileIndex.writeBufferBytes)
    }
    func append(key: Int, tile: RasterTile) throws {
      do {
        try Task.checkCancellation()
        guard !finished,!failed,key>lastKey,key>=0,key<RuntimeTileIndex.maximumEntries,
              let segment=tile.segment,tile.count==TileArchive.pixelCount,
              tile.offset>=0,tile.offset%TileArchive.byteCount==0,
              tile.offset<=segment.length-TileArchive.byteCount else { throw CraftError.invalid("Invalid runtime tile index entry or lifecycle.") }
        guard count<maximumBytes/16 else {throw RasterScratchFailure.capacity(requiredBytes:(count+1)*16,limitBytes:maximumBytes)}
        let id=ObjectIdentifier(segment),number:UInt32
        if let existing=identifiers[id] {number=existing}
        else {
          guard retained.count<Int(UInt32.max) else {throw CraftError.invalid("Too many runtime tile segments.")}
          try reserveSegment(128);number=UInt32(retained.count);retained.append(segment);identifiers[id]=number
        }
        var k=UInt64(key).littleEndian,location=((UInt64(number)<<32)|UInt64(tile.offset)).littleEndian
        withUnsafeBytes(of:&k){buffer.append(contentsOf:$0)};withUnsafeBytes(of:&location){buffer.append(contentsOf:$0)}
        count+=1;lastKey=key
        if buffer.count==RuntimeTileIndex.writeBufferBytes {try flush()}
      } catch {failed=true;throw error}
    }
    private func flush() throws {
      try buffer.withUnsafeBytes { bytes in
        var done=0
        while done<bytes.count {
          try Task.checkCancellation();let size=min(RuntimeTileIndex.writeBufferBytes,bytes.count-done)
          maximumPhysicalWrite=max(maximumPhysicalWrite,size)
          let n=pwrite(file.fd,bytes.baseAddress!.advanced(by:done),size,off_t(written+done))
          if n<0 && errno==EINTR {continue}
          guard n>0 else {throw RasterScratchFailure.io(operation:"index write",code:n==0 ? EIO:errno)}
          done+=n
        }
      }
      written+=buffer.count;buffer.removeAll(keepingCapacity:true)
    }
    func finish() throws -> RuntimeTileIndex {
      do {
        try Task.checkCancellation();guard !finished,!failed else {throw CraftError.invalid("Runtime tile index writer is no longer usable.")}
        try flush();let index=try RuntimeTileIndex(file:file,count:count,segments:retained)
        finished=true;return index
      } catch {failed=true;throw error}
    }
  }
}
fileprivate final class RuntimeIndexFile: @unchecked Sendable {
  let fd: Int32
  init(directory: URL?) throws {
    let folder=directory ?? FileManager.default.temporaryDirectory
    guard folder.isFileURL else {throw CraftError.invalid("Runtime tile index requires a local directory.")}
    let url=folder.appendingPathComponent("photato-runtime-index-\(UUID().uuidString).tmp")
    let descriptor=url.withUnsafeFileSystemRepresentation { open($0!,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,S_IRUSR|S_IWUSR) }
    guard descriptor>=0 else {throw RasterScratchFailure.io(operation:"index creation",code:errno)}
    let removed=url.withUnsafeFileSystemRepresentation {unlink($0!)}
    guard removed==0 else {let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"index unlink",code:code)}
    fd=descriptor
  }
  deinit {close(fd)}
}
