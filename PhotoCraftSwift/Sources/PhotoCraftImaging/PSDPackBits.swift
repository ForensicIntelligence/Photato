import Foundation

/// Native Swift translation of PhotoCraft's crates/psd/src/compression.rs
/// packbits::encode (MIT OR Apache-2.0). Each call encodes one row.
enum PSDPackBits {
  static func encode(_ source: [UInt8]) throws -> Data {
    var output = Data()
    output.reserveCapacity(source.count + source.count / 128 + 1)
    var index = 0
    while index < source.count {
      try Task.checkCancellation()
      var run = 1
      while index + run < source.count && run < 128 && source[index + run] == source[index] {
        run += 1
      }
      if run >= 2 {
        output.append(UInt8(truncatingIfNeeded: 1 - run))
        output.append(source[index])
        index += run
      } else {
        let start = index
        var length = 0
        while index < source.count && length < 128 {
          if index + 2 < source.count && source[index] == source[index + 1]
            && source[index] == source[index + 2] { break }
          index += 1
          length += 1
        }
        output.append(UInt8(length - 1))
        output.append(contentsOf: source[start..<(start + length)])
      }
    }
    return output
  }
}
