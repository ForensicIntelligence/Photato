import Darwin
import Foundation

public enum RasterScratchFailure: Error, LocalizedError, Equatable, Sendable {
  case capacity(requiredBytes: Int, limitBytes: Int)
  case io(operation: String, code: Int32)
  public var errorDescription: String? {
    switch self {
    case .capacity: "Raster scratch storage exceeds its admitted disk budget."
    case .io(let operation, let code): "Raster scratch \(operation) failed: \(String(cString: strerror(code)))"
    }
  }
}

/// Append-only anonymous scratch. Published samples are never modified. Immutable
/// mappings retain the descriptor independently of the writer and document lifetime.
/// macOS manages mapped-page residency; no whole-raster heap buffer is retained.
public final class RasterTileStore: @unchecked Sendable {
  public static let defaultMaximumBytes = 2_199_023_255_552
  private static let segmentBytes = 64 * 1024 * 1024
  private let file: ScratchDescriptor
  private let maximumBytes: Int
  private let lock = NSLock()
  private var segments: [ScratchSegment] = []
  private var count = 0
  public var storedBytes: Int { lock.lock(); defer { lock.unlock() }; return count }
  public init(maximumBytes: Int = defaultMaximumBytes, directory: URL? = nil) throws {
    guard maximumBytes >= 0, maximumBytes <= Self.defaultMaximumBytes,
      MemoryLayout<Pixel>.size == 16, MemoryLayout<Pixel>.stride == 16 else {
      throw CraftError.invalid("Invalid raster scratch capacity or sample layout.")
    }
    self.maximumBytes = maximumBytes
    let folder = directory ?? FileManager.default.temporaryDirectory
    guard folder.isFileURL else { throw CraftError.invalid("Raster scratch requires a local directory.") }
    let url = folder.appendingPathComponent("photato-raster-\(UUID().uuidString).tiles")
    let fd = url.withUnsafeFileSystemRepresentation { open($0!, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR) }
    guard fd >= 0 else { throw RasterScratchFailure.io(operation: "creation", code: errno) }
    // Never expose a mutable path to a live mapping. Closing the last reference
    // reclaims the unlinked file, including cancellation and failed imports.
    let removed = url.withUnsafeFileSystemRepresentation { unlink($0!) }
    guard removed == 0 else { let code = errno; close(fd); throw RasterScratchFailure.io(operation: "unlink", code: code) }
    file = ScratchDescriptor(fd)
  }
  func append(_ tile: RasterTile) throws -> RasterTile {
    try Task.checkCancellation()
    guard tile.count == TileArchive.pixelCount, tile.allSatisfy(\.isFinite) else { throw CraftError.invalid("Invalid scratch tile samples.") }
    lock.lock(); defer { lock.unlock() }
    guard TileArchive.byteCount <= maximumBytes - count else {
      throw RasterScratchFailure.capacity(requiredBytes: count + TileArchive.byteCount, limitBytes: maximumBytes)
    }
    let index = count / Self.segmentBytes, offset = count % Self.segmentBytes
    if index == segments.count {
      let length = (index + 1) * Self.segmentBytes
      guard ftruncate(file.fd, off_t(length)) == 0 else { throw RasterScratchFailure.io(operation: "growth", code: errno) }
      let mapping = mmap(nil, Self.segmentBytes, PROT_READ, MAP_SHARED, file.fd, off_t(index * Self.segmentBytes))
      guard let mapping, mapping != MAP_FAILED else { throw RasterScratchFailure.io(operation: "mapping", code: errno) }
      _ = madvise(mapping, Self.segmentBytes, MADV_RANDOM)
      segments.append(ScratchSegment(file: file, address: mapping, length: Self.segmentBytes))
    }
    try tile.withUnsafeBufferPointer { samples in
      let bytes = UnsafeRawBufferPointer(samples)
      var done = 0
      while done < bytes.count {
        let written = pwrite(file.fd, bytes.baseAddress!.advanced(by: done), bytes.count - done, off_t(count + done))
        if written < 0 && errno == EINTR { continue }
        guard written > 0 else { throw RasterScratchFailure.io(operation: "write", code: written == 0 ? EIO : errno) }
        done += written
      }
    }
    let result = RasterTile(segment: segments[index], offset: offset)
    count += TileArchive.byteCount
    return result
  }
}

fileprivate final class ScratchDescriptor: @unchecked Sendable {
  let fd: Int32
  init(_ fd: Int32) { self.fd = fd }
  deinit { close(fd) }
}
fileprivate final class ScratchSegment: @unchecked Sendable {
  let file: ScratchDescriptor
  let address: UnsafeMutableRawPointer
  let length: Int
  init(file: ScratchDescriptor, address: UnsafeMutableRawPointer, length: Int) {
    self.file = file; self.address = address; self.length = length
  }
  deinit { munmap(address, length) }
}

/// A value-semantic tile. Mutation promotes only the touched immutable disk tile
/// to a uniquely owned Array. Dictionary COW still isolates document snapshots.
struct RasterTile: RandomAccessCollection, MutableCollection, Equatable, @unchecked Sendable {
  typealias Index = Int
  typealias Element = Pixel
  private final class Storage: @unchecked Sendable {
    var array: [Pixel]?
    let segment: ScratchSegment?
    let offset: Int
    init(_ array: [Pixel]) { self.array = array; segment = nil; offset = 0 }
    init(segment: ScratchSegment, offset: Int) { array = nil; self.segment = segment; self.offset = offset }
  }
  private var storage: Storage
  init(_ array: [Pixel]) { storage = Storage(array) }
  init(repeating pixel: Pixel, count: Int) { storage = Storage(Array(repeating: pixel, count: count)) }
  fileprivate init(segment: ScratchSegment, offset: Int) { storage = Storage(segment: segment, offset: offset) }
  func index(after i: Int) -> Int { i + 1 }
  func index(before i: Int) -> Int { i - 1 }
  func index(_ i: Int, offsetBy n: Int) -> Int { i + n }
  func distance(from start: Int, to end: Int) -> Int { end - start }
  var startIndex: Int { 0 }
  var endIndex: Int { storage.array?.count ?? TileArchive.pixelCount }
  var isBacked: Bool { storage.segment != nil }
  var residentBytes: Int { (storage.array?.count ?? 0) * MemoryLayout<Pixel>.stride }
  var identity: UInt { withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) } }
  private mutating func makeMutable() {
    if !isKnownUniquelyReferenced(&storage) || storage.array == nil {
      storage = Storage(withUnsafeBufferPointer { Array($0) })
    }
  }
  subscript(index: Int) -> Pixel {
    get {
      precondition(index >= 0 && index < endIndex)
      if let array = storage.array { return array[index] }
      return storage.segment!.address.advanced(by: storage.offset).assumingMemoryBound(to: Pixel.self)[index]
    }
    _modify {
      precondition(index >= 0 && index < endIndex)
      makeMutable()
      yield &storage.array![index]
    }
  }
  func withUnsafeBufferPointer<T>(_ body: (UnsafeBufferPointer<Pixel>) throws -> T) rethrows -> T {
    if let array = storage.array { return try array.withUnsafeBufferPointer(body) }
    let segment = storage.segment!
    return try withExtendedLifetime(segment) {
      try body(UnsafeBufferPointer(start: segment.address.advanced(by: storage.offset).assumingMemoryBound(to: Pixel.self), count: TileArchive.pixelCount))
    }
  }
  mutating func replaceSubrange<C: Collection>(_ range: Range<Int>, with values: C) where C.Element == Pixel {
    makeMutable(); storage.array!.replaceSubrange(range, with: values)
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage === rhs.storage || lhs.elementsEqual(rhs)
  }
}


extension CraftDocument {
  /// Conservative sum of referenced mapped tile samples, not physical disk usage
  /// or resident pages; repeated shared surfaces can count the same backing twice.
  public var mappedRasterBytes: Int {
    var bytes = 0
    func account(_ s: Surface) { bytes += s.mappedBytes }
    for layer in layers {
      if case .raster(let s) = layer.content { account(s) }
      if let s = layer.mask { account(s) }
      if let s = layer.smartFilters?.mask { account(s) }
      for s in layer.video?.frames ?? [] { account(s) }
    }
    for channel in alphaChannels ?? [] { account(channel.pixels) }
    if let quickMask { account(quickMask.pixels) }
    for pattern in patterns ?? [] { account(pattern.surface) }
    for image in variables?.images ?? [] { account(image.pixels) }
    return bytes
  }
}
