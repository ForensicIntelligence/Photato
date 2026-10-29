import Foundation
import PhotoCraftCore

/// Finite-state entropy tables defined by RFC 8878, sections 4.1/4.2.
struct PcraftZstdFSE {
  struct Entry {
    let symbol: Int
    let bits: Int
    let base: Int
  }
  let log: Int
  let entries: [Entry]

  init(symbol: Int) {
    log = 0; entries = [Entry(symbol: symbol, bits: 0, base: 0)]
  }
  init(counts: [Int], log: Int) throws {
    guard (5...9).contains(log), counts.filter({ $0 != 0 }).count >= 2,
      counts.allSatisfy({ $0 >= -1 }), counts.reduce(0, { $0 + abs($1) }) == 1 << log else {
      throw CraftError.invalid("Invalid Zstandard probability distribution.")
    }
    let size = 1 << log, step = size / 2 + size / 8 + 3
    var symbols = [Int](repeating: -1, count: size), high = size - 1
    var next = counts.map { $0 == -1 ? 1 : $0 }
    for (symbol, count) in counts.enumerated() where count == -1 {
      symbols[high] = symbol; high -= 1
    }
    var position = 0
    for (symbol, count) in counts.enumerated() where count > 0 {
      for _ in 0..<count {
        symbols[position] = symbol
        position = (position + step) & (size - 1)
        while position > high { position = (position + step) & (size - 1) }
      }
    }
    guard position == 0, !symbols.contains(-1) else {
      throw CraftError.invalid("Incomplete Zstandard probability table.")
    }
    self.log = log
    entries = symbols.map { symbol in
      let value = next[symbol]; next[symbol] += 1
      let bits = log - (Int.bitWidth - 1 - value.leadingZeroBitCount)
      return Entry(symbol: symbol, bits: bits, base: (value << bits) - size)
    }
  }

  static func read(_ input: inout PcraftBytes, maxSymbol: Int, maxLog: Int) throws -> Self {
    var bits = PcraftForwardBits(bytes: Array(input.bytes[input.position...]))
    let log = try bits.read(4) + 5
    guard log <= maxLog else { throw CraftError.invalid("Oversized Zstandard probability table.") }
    var remaining = (1 << log) + 1, threshold = 1 << log, width = log + 1
    var counts: [Int] = [], zero = false
    while remaining > 1 {
      if zero {
        var repeats: Int
        repeat {
          repeats = try bits.read(2)
          guard counts.count + repeats <= maxSymbol else {
            throw CraftError.invalid("Too many Zstandard probability symbols.")
          }
          counts.append(contentsOf: repeatElement(0, count: repeats))
        } while repeats == 3
      }
      guard counts.count <= maxSymbol else { throw CraftError.invalid("Invalid Zstandard symbol.") }
      let cutoff = 2 * threshold - 1 - remaining
      var count: Int
      if try bits.peek(width - 1) < cutoff {
        count = try bits.read(width - 1)
      } else {
        count = try bits.read(width)
        if count >= threshold { count -= cutoff }
      }
      count -= 1
      remaining -= abs(count); counts.append(count); zero = count == 0
      guard remaining >= 1 else { throw CraftError.invalid("Invalid Zstandard probability total.") }
      while remaining < threshold { threshold >>= 1; width -= 1 }
    }
    input.position += (bits.position + 7) / 8
    return try Self(counts: counts, log: log)
  }

  static func weights(_ encoded: [UInt8]) throws -> [Int] {
    var input = PcraftBytes(bytes: encoded)
    let table = try read(&input, maxSymbol: 11, maxLog: 6)
    var bits = try PcraftReverseBits(input.take(input.remaining))
    var states = [try bits.read(table.log), try bits.read(table.log)]
    var current = 0, result: [Int] = []
    while true {
      let entry = table.entries[states[current]]
      result.append(entry.symbol)
      guard result.count < 255 else { throw CraftError.invalid("Too many Zstandard Huffman weights.") }
      if entry.bits > bits.remaining {
        // The symbol just emitted and the other state are the two final symbols.
        // The zero-padded transition itself has no subsequent symbol.
        result.append(table.entries[states[1 - current]].symbol)
        guard result.count <= 255 else { throw CraftError.invalid("Too many Zstandard Huffman weights.") }
        return result
      }
      states[current] = entry.base + (try bits.read(entry.bits))
      current = 1 - current
    }
  }
}
