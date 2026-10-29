import Foundation
import PhotoCraftCore

struct PcraftZstdHuffman {
  struct Entry { let symbol: UInt8; let bits: Int }
  let log: Int
  let entries: [Entry]

  static func read(_ input: inout PcraftBytes) throws -> Self {
    let header = Int(try input.number(1))
    var weights: [Int]
    if header < 128 {
      weights = try PcraftZstdFSE.weights(input.take(header))
    } else {
      let count = header - 127, bytes = try input.take((count + 1) / 2)
      weights = (0..<count).map { Int(bytes[$0 / 2] >> ($0 % 2 == 0 ? 4 : 0)) & 15 }
    }
    guard !weights.isEmpty, weights.count <= 255,
      weights.allSatisfy({ (0...11).contains($0) }) else {
      throw CraftError.invalid("Invalid Zstandard Huffman weights.")
    }
    let sum = weights.reduce(0) { $0 + ($1 == 0 ? 0 : 1 << ($1 - 1)) }
    guard sum > 0 else { throw CraftError.invalid("Empty Zstandard Huffman tree.") }
    let log = Int.bitWidth - sum.leadingZeroBitCount, missing = (1 << log) - sum
    guard log <= 11, missing.nonzeroBitCount == 1 else {
      throw CraftError.invalid("Incomplete Zstandard Huffman tree.")
    }
    weights.append(Int.bitWidth - missing.leadingZeroBitCount)
    guard weights.contains(1) else { throw CraftError.invalid("Invalid Zstandard Huffman tree depth.") }
    var entries: [Entry] = []
    for weight in 1...log {
      for (symbol, w) in weights.enumerated() where w == weight {
        entries.append(contentsOf: repeatElement(
          Entry(symbol: UInt8(symbol), bits: log + 1 - weight), count: 1 << (weight - 1)))
      }
    }
    guard entries.count == 1 << log else { throw CraftError.invalid("Invalid Zstandard Huffman table.") }
    return Self(log: log, entries: entries)
  }

  func decode(_ bytes: [UInt8], count: Int) throws -> [UInt8] {
    var bits = try PcraftReverseBits(bytes), result: [UInt8] = []
    result.reserveCapacity(count)
    for i in 0..<count {
      if i & 4095 == 0 { try Task.checkCancellation() }
      let entry = try entries[bits.peekPadded(log)]
      _ = try bits.read(entry.bits); result.append(entry.symbol)
    }
    guard bits.remaining == 0 else { throw CraftError.invalid("Trailing Zstandard literal bits.") }
    return result
  }
}
