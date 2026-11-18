import Darwin

/// Checked random-access I/O for disposable region data. Sparse unwritten
/// ranges read as zero and writes report I/O errors before an edit can commit.
private struct ColorRegionScratch {
  private let file: ScratchDescriptor

  init() throws {
    file = try ScratchDescriptor(prefix: "photato-color-region", suffix: "scratch")
  }

  func read(_ data: UnsafeMutableRawBufferPointer, at offset: Int) throws {
    var done = 0
    while done < data.count {
      let remaining = data.count - done
      let start = data.baseAddress!.advanced(by: done)
      let amount = pread(file.fd, start, remaining, off_t(offset + done))
      if amount < 0 {
        if errno == EINTR { continue }
        throw RasterScratchFailure.io(operation: "color region read", code: errno)
      }
      if amount == 0 {
        start.initializeMemory(as: UInt8.self, repeating: 0, count: remaining)
        return
      }
      done += amount
    }
  }

  func write(_ data: UnsafeRawBufferPointer, at offset: Int) throws {
    var done = 0
    while done < data.count {
      let amount = pwrite(
        file.fd, data.baseAddress!.advanced(by: done), data.count - done, off_t(offset + done))
      if amount < 0 && errno == EINTR { continue }
      guard amount > 0 else {
        throw RasterScratchFailure.io(operation: "color region write", code: amount == 0 ? EIO : errno)
      }
      done += amount
    }
  }
}

/// Contiguous runs mark one bit per pixel. Only 16 pages stay resident.
final class ColorRegionMarks {
  private static let pageBytes = 16_384
  private struct Page {
    var number = -1
    var data = [UInt8](repeating: 0, count: ColorRegionMarks.pageBytes)
    var dirty = false
  }

  private let scratch: ColorRegionScratch
  private var pages = [Page](repeating: Page(), count: 16)

  init() throws {
    scratch = try ColorRegionScratch()
  }

  private func slot(for byte: Int) throws -> Int {
    let page = byte / Self.pageBytes
    let slot = page % pages.count
    if pages[slot].number != page {
      try Task.checkCancellation()
      if pages[slot].dirty {
        let offset = pages[slot].number * Self.pageBytes
        try pages[slot].data.withUnsafeBytes { try scratch.write($0, at: offset) }
      }
      try pages[slot].data.withUnsafeMutableBytes { try scratch.read($0, at: page * Self.pageBytes) }
      pages[slot].number = page
      pages[slot].dirty = false
    }
    return slot
  }

  func contains(_ index: Int) throws -> Bool {
    let byte = index >> 3
    let slot = try slot(for: byte)
    return pages[slot].data[byte % Self.pageBytes] & (UInt8(1) << (index & 7)) != 0
  }

  func insert(_ indices: ClosedRange<Int>) throws {
    let first = indices.lowerBound, last = indices.upperBound
    let firstByte = first >> 3, lastByte = last >> 3
    let left = UInt8.max << (first & 7)
    let right = UInt8.max >> (7 - (last & 7))
    var byte = firstByte
    while byte <= lastByte {
      let slot = try slot(for: byte)
      let stop = min(lastByte, (byte / Self.pageBytes + 1) * Self.pageBytes - 1)
      let lower = byte % Self.pageBytes
      let upper = stop % Self.pageBytes
      pages[slot].data.withUnsafeMutableBufferPointer { page in
        for offset in lower...upper {
          let position = byte + offset - lower
          let mask = (position == firstByte ? left : UInt8.max) & (position == lastByte ? right : UInt8.max)
          page[offset] |= mask
        }
      }
      pages[slot].dirty = true
      byte = stop + 1
    }
  }
}

/// The depth-first span worklist spills complete blocks. Each pop retains the
/// same last-in, first-out order regardless of how many blocks reach disk.
final class ColorRegionWorklist {
  private static let entriesPerBlock = 2048
  private static let blockBytes = entriesPerBlock * MemoryLayout<Int>.stride
  private let scratch: ColorRegionScratch
  private var pending: [Int] = []
  private var blocks = 0

  init(seed: Int) throws {
    scratch = try ColorRegionScratch()
    pending.reserveCapacity(Self.entriesPerBlock)
    pending.append(seed)
  }

  func push(_ index: Int) throws {
    if pending.count == Self.entriesPerBlock {
      let offset = blocks * Self.blockBytes
      try pending.withUnsafeBytes { try scratch.write($0, at: offset) }
      pending.removeAll(keepingCapacity: true)
      blocks += 1
    }
    pending.append(index)
  }

  func pop() throws -> Int? {
    if pending.isEmpty && blocks > 0 {
      blocks -= 1
      pending = [Int](repeating: 0, count: Self.entriesPerBlock)
      let offset = blocks * Self.blockBytes
      try pending.withUnsafeMutableBytes { try scratch.read($0, at: offset) }
    }
    return pending.popLast()
  }
}
