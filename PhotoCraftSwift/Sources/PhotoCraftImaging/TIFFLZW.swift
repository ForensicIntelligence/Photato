import Foundation
import PhotoCraftCore

/// TIFF 6.0 LZW: MSB-first codes, clear/end markers and early width changes.
/// This is independent of the PackBits RLE used by PSD.
enum TIFFLZW {
  static func encode(_ input: [UInt8]) throws -> Data {
    var output = Data(), pending: UInt32 = 0, pendingBits = 0
    var width = 9, readerNext = 258, readerHasPrevious = false
    func emit(_ code: Int) {
      pending = (pending << width) | UInt32(code)
      pendingBits += width
      while pendingBits >= 8 {
        pendingBits -= 8
        output.append(UInt8(truncatingIfNeeded: pending >> pendingBits))
      }
      pending &= (1 << pendingBits) - 1
      if code == 256 {
        width = 9; readerNext = 258; readerHasPrevious = false
      } else if code != 257 {
        if readerHasPrevious && readerNext < 4096 {
          readerNext += 1
          if readerNext == (1 << width) - 1 && width < 12 { width += 1 }
        }
        readerHasPrevious = true
      }
    }
    emit(256)
    var table: [UInt32: Int] = [:], next = 258
    if let first = input.first {
      var prefix = Int(first)
      for i in 1..<input.count {
        if i % 4096 == 0 { try Task.checkCancellation() }
        let byte = input[i], key = (UInt32(prefix) << 8) | UInt32(byte)
        if let found = table[key] { prefix = found; continue }
        emit(prefix)
        if next < 4096 { table[key] = next; next += 1 }
        else { emit(256); table.removeAll(keepingCapacity: true); next = 258 }
        prefix = Int(byte)
      }
      emit(prefix)
    }
    emit(257)
    if pendingBits > 0 { output.append(UInt8(truncatingIfNeeded: pending << (8 - pendingBits))) }
    try Task.checkCancellation()
    return output
  }
  static func decode(_ data: Data, expected: Int) throws -> [UInt8] {
    guard expected >= 0, expected <= TIFFContainer.byteLimit else {
      throw CraftError.invalid("Invalid TIFF LZW sample budget.")
    }
    let reader = try RowReader(data, expected: expected)
    let output = try reader.read(expected)
    try reader.finish()
    return output
  }

  final class RowReader {
    private var source: PSDReader
    private var bytes = Data()
    private var inputIndex = 0
    private var bitBuffer: UInt32 = 0
    private var bufferedBits = 0
    private let expected: Int
    private var width = 9
    private var next = 258
    private var previous: [UInt8]?
    private var table = (0..<256).map { [UInt8($0)] } + [[UInt8]](repeating: [], count: 3840)
    private var pending: [UInt8] = []
    private var cursor = 0
    private var delivered = 0
    private var cleared = false
    private var ended = false

    convenience init(_ data: Data, expected: Int) throws {
      try self.init(PSDReader(data: data), expected: expected)
    }
    init(_ source: PSDReader, expected: Int) throws {
      guard expected >= 0 else { throw CraftError.invalid("Invalid TIFF LZW sample budget.") }
      self.source = source
      self.expected = expected
    }

    private func readCode() throws -> Int? {
      while bufferedBits < width {
        if inputIndex == bytes.count {
          guard source.remaining > 0 else { return nil }
          bytes = try source.bytes(min(PSDFileSource.pageBytes, source.remaining))
          inputIndex = 0
        }
        bitBuffer = (bitBuffer << 8) | UInt32(bytes[inputIndex])
        inputIndex += 1
        bufferedBits += 8
      }
      bufferedBits -= width
      let code = Int(bitBuffer >> bufferedBits)
      bitBuffer &= (1 << bufferedBits) - 1
      return code
    }

    func read(_ count: Int) throws -> [UInt8] {
      guard count >= 0, count <= expected - delivered else {
        throw CraftError.invalid("Excessive TIFF LZW sample stream.")
      }
      var output: [UInt8] = []
      output.reserveCapacity(count)
      while output.count < count {
        if cursor == pending.count {
          guard let word = try nextWord() else { throw CraftError.invalid("Incomplete TIFF LZW samples.") }
          guard word.count <= expected - delivered else { throw CraftError.invalid("Excessive TIFF LZW sample stream.") }
          pending = word
          cursor = 0
        }
        let size = min(count - output.count, pending.count - cursor)
        output.append(contentsOf: pending[cursor..<cursor + size])
        cursor += size
        delivered += size
      }
      return output
    }

    func finish() throws {
      guard delivered == expected, cursor == pending.count else {
        throw CraftError.invalid("Incomplete TIFF LZW samples.")
      }
      guard try nextWord() == nil else { throw CraftError.invalid("Excessive TIFF LZW sample stream.") }
    }

    private func nextWord() throws -> [UInt8]? {
      if ended { return nil }
      while let code = try readCode() {
        try Task.checkCancellation()
        if code == 256 {
          width = 9
          next = 258
          previous = nil
          cleared = true
          continue
        }
        guard cleared else { throw CraftError.invalid("Missing TIFF LZW clear code.") }
        if code == 257 {
          ended = true
          return nil
        }
        let word: [UInt8]
        if code < next, code < 256 || code >= 258 {
          word = table[code]
        } else if code == next, let previous, let first = previous.first {
          word = previous + [first]
        } else {
          throw CraftError.invalid("Invalid TIFF LZW dictionary code.")
        }
        guard let first = word.first else { throw CraftError.invalid("Invalid TIFF LZW dictionary code.") }
        if let previous, next < 4096 {
          table[next] = previous + [first]
          next += 1
          if next == (1 << width) - 1, width < 12 { width += 1 }
        }
        previous = word
        return word
      }
      throw CraftError.invalid("Missing TIFF LZW end code.")
    }
  }
}
