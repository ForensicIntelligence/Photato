import Darwin
import Foundation

/// Immutable, unlinked regular block address space. A mapped presence bitmap
/// replaces a whole-plane heap index; file holes are never interpreted as samples.
final class ComponentPlaneMapping: @unchecked Sendable {
  let address: UnsafeMutableRawPointer
  let length: Int
  let sampleOffset: Int
  let blockBytes: Int
  let blockCount: Int
  let storedBytes: Int
  private let fd: Int32
  init(fd: Int32, length: Int, sampleOffset: Int, blockBytes: Int, blockCount: Int, storedBytes: Int) throws {
    let pointer = mmap(nil, length, PROT_READ, MAP_SHARED, fd, 0)
    guard let pointer, pointer != MAP_FAILED else { throw RasterScratchFailure.io(operation: "component mapping", code: errno) }
    address = pointer; self.fd = fd; self.length = length; self.sampleOffset = sampleOffset
    self.blockBytes = blockBytes; self.blockCount = blockCount; self.storedBytes = storedBytes
    _ = madvise(pointer, length, MADV_RANDOM)
  }
  deinit { munmap(address, length); close(fd) }
  func contains(_ key: Int) -> Bool {
    key >= 0 && key < blockCount && address.assumingMemoryBound(to: UInt8.self)[key / 8] & (1 << (key % 8)) != 0
  }
  func sampleAddress(_ key: Int) -> UnsafeRawPointer { UnsafeRawPointer(address.advanced(by: sampleOffset + key * blockBytes)) }
  func block(_ key: Int) -> ComponentBlock? { contains(key) ? ComponentBlock(mapping: self, key: key) : nil }
  func makeIterator() -> AnyIterator<Int> {
    var key = 0
    return AnyIterator { [self] in
      while key < blockCount {
        // Skip empty bitmap bytes without walking every virtual sample block.
        if key % 8 == 0 && address.assumingMemoryBound(to: UInt8.self)[key / 8] == 0 { key += 8; continue }
        let current = key; key += 1
        if contains(current) { return current }
      }
      return nil
    }
  }
}

final class ComponentPlaneWriter {
  private var fd: Int32
  private let sampleOffset: Int
  private let blockBytes: Int
  private let blockCount: Int
  private let length: Int
  private let maximumBytes: Int
  private let stride: Int
  private var presence: Data
  private var samples = 0
  private var failed = false
  init(plane: ComponentPlane, maximumBytes: Int, directory: URL?) throws {
    guard maximumBytes >= 0, maximumBytes <= RasterTileStore.defaultMaximumBytes else { throw CraftError.invalid("Invalid component scratch budget.") }
    self.maximumBytes = maximumBytes; stride = plane.sampleBytes
    blockBytes = ComponentPlane.blockSamples * stride
    blockCount = (plane.count + ComponentPlane.blockSamples - 1) / ComponentPlane.blockSamples
    let indexBytes = (blockCount + 7) / 8, page = Int(getpagesize())
    sampleOffset = ((indexBytes + page - 1) / page) * page
    length = sampleOffset + blockCount * blockBytes
    guard sampleOffset <= maximumBytes else { throw RasterScratchFailure.capacity(requiredBytes: sampleOffset, limitBytes: maximumBytes) }
    presence = Data(count: indexBytes)
    let folder = directory ?? FileManager.default.temporaryDirectory
    guard folder.isFileURL else { throw CraftError.invalid("Component scratch requires a local directory.") }
    let path = folder.appendingPathComponent("photato-component-\(UUID().uuidString).scratch")
    let handle = path.withUnsafeFileSystemRepresentation { open($0!, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR) }
    guard handle >= 0 else { throw RasterScratchFailure.io(operation: "component creation", code: errno) }
    let removed = path.withUnsafeFileSystemRepresentation { unlink($0!) }
    guard removed == 0 else { let code = errno; close(handle); throw RasterScratchFailure.io(operation: "component unlink", code: code) }
    guard ftruncate(handle, off_t(length)) == 0 else { let code = errno; close(handle); throw RasterScratchFailure.io(operation: "component extent", code: code) }
    fd = handle
  }
  deinit { if fd >= 0 { close(fd) } }
  func write(key: Int, block: ComponentBlock) throws {
    guard !failed, fd >= 0, key >= 0, key < blockCount else { throw CraftError.invalid("Component scratch writer is unavailable or has an invalid block.") }
    do {
      try Task.checkCancellation()
      let present = presence[key / 8] & (1 << (key % 8)) != 0
      let required = sampleOffset + (samples + (present ? 0 : 1)) * blockBytes
      guard required <= maximumBytes else { throw RasterScratchFailure.capacity(requiredBytes: required, limitBytes: maximumBytes) }
      try block.withBytes(stride: stride) { try writeBytes($0, offset: sampleOffset + key * blockBytes) }
      if !present { presence[key / 8] |= 1 << (key % 8); samples += 1 }
    } catch { failed = true; throw error }
  }
  func finish() throws -> ComponentPlaneMapping {
    guard !failed, fd >= 0 else { throw CraftError.invalid("Component scratch writer cannot publish after completion or failure.") }
    do {
      try Task.checkCancellation()
      try presence.withUnsafeBytes { try writeBytes($0, offset: 0) }
      guard fsync(fd) == 0 else { throw RasterScratchFailure.io(operation: "component synchronization", code: errno) }
      let result = try ComponentPlaneMapping(fd: fd, length: length, sampleOffset: sampleOffset, blockBytes: blockBytes, blockCount: blockCount, storedBytes: sampleOffset + samples * blockBytes)
      fd = -1; return result
    } catch { failed = true; throw error }
  }
  private func writeBytes(_ bytes: UnsafeRawBufferPointer, offset: Int) throws {
    var done = 0
    while done < bytes.count {
      let written = pwrite(fd, bytes.baseAddress!.advanced(by: done), bytes.count - done, off_t(offset + done))
      if written < 0 && errno == EINTR { continue }
      guard written > 0 else { throw RasterScratchFailure.io(operation: "component write", code: written == 0 ? EIO : errno) }
      done += written
    }
  }
}
