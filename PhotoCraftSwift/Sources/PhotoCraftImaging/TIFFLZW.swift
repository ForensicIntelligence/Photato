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
    let input = [UInt8](data)
    var bit = 0, width = 9, next = 258, previous: [UInt8]?
    var table = (0..<256).map { [UInt8($0)] } + [[UInt8]](repeating: [], count: 3840)
    var output: [UInt8] = [], cleared = false
    output.reserveCapacity(expected)
    while input.count * 8 - bit >= width {
      try Task.checkCancellation()
      var code = 0
      for _ in 0..<width {
        code = (code << 1) | Int((input[bit / 8] >> (7 - bit % 8)) & 1)
        bit += 1
      }
      if code == 256 { width = 9; next = 258; previous = nil; cleared = true; continue }
      guard cleared else { throw CraftError.invalid("Missing TIFF LZW clear code.") }
      if code == 257 {
        guard output.count == expected else { throw CraftError.invalid("Incomplete TIFF LZW samples.") }
        return output
      }
      let word: [UInt8]
      if code < next, code < 256 || code >= 258 { word = table[code] }
      else if code == next, let previous, let first = previous.first { word = previous + [first] }
      else { throw CraftError.invalid("Invalid TIFF LZW dictionary code.") }
      guard !word.isEmpty, word.count <= expected - output.count else {
        throw CraftError.invalid("Excessive TIFF LZW sample stream.")
      }
      output.append(contentsOf: word)
      if let previous, next < 4096 {
        table[next] = previous + [word[0]]; next += 1
        if next == (1 << width) - 1 && width < 12 { width += 1 }
      }
      previous = word
    }
    throw CraftError.invalid("Missing TIFF LZW end code.")
  }
}
