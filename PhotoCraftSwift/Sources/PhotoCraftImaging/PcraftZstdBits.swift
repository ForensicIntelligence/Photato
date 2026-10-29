import Foundation
import PhotoCraftCore

/// Checked, byte-aligned access shared by the original-project codecs.
struct PcraftBytes {
  let bytes: [UInt8]
  var position = 0
  var remaining: Int { bytes.count - position }
  mutating func number(_ count: Int) throws -> UInt64 {
    guard (0...8).contains(count), count <= remaining else {
      throw CraftError.invalid("Truncated PhotoCraft compressed data.")
    }
    var result: UInt64 = 0
    for i in 0..<count { result |= UInt64(bytes[position + i]) << (8 * i) }
    position += count
    return result
  }
  mutating func take(_ count: Int) throws -> [UInt8] {
    guard count >= 0, count <= remaining else {
      throw CraftError.invalid("Invalid PhotoCraft compressed length.")
    }
    defer { position += count }
    return Array(bytes[position..<(position + count)])
  }
}

struct PcraftForwardBits {
  let bytes: [UInt8]
  var position = 0
  func peek(_ count: Int) throws -> Int {
    guard (0...31).contains(count), position <= bytes.count * 8 - count else {
      throw CraftError.invalid("Truncated Zstandard probability table.")
    }
    var result = 0, used = 0
    while used < count {
      let at = position + used, n = min(count - used, 8 - at % 8)
      result |= ((Int(bytes[at / 8]) >> (at % 8)) & ((1 << n) - 1)) << used
      used += n
    }
    return result
  }
  mutating func read(_ count: Int) throws -> Int {
    let result = try peek(count); position += count; return result
  }
}

struct PcraftReverseBits {
  let bytes: [UInt8]
  private(set) var remaining: Int
  init(_ bytes: [UInt8]) throws {
    guard let last = bytes.last, last != 0 else {
      throw CraftError.invalid("Missing Zstandard bitstream end marker.")
    }
    self.bytes = bytes
    remaining = (bytes.count - 1) * 8 + 7 - last.leadingZeroBitCount
  }
  func peekPadded(_ count: Int) throws -> Int {
    guard (0...31).contains(count) else { throw CraftError.invalid("Invalid Zstandard bit width.") }
    let available = min(count, remaining)
    let bits = PcraftForwardBits(bytes: bytes, position: remaining - available)
    return try bits.peek(available) << (count - available)
  }
  mutating func read(_ count: Int) throws -> Int {
    guard count <= remaining else { throw CraftError.invalid("Truncated Zstandard bitstream.") }
    let value = try peekPadded(count); remaining -= count; return value
  }
}
