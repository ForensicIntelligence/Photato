import Foundation
import PhotoCraftCore

/// Original PhotoCraft blob decompression. No dictionaries, concatenation, or
/// skippable frames are emitted by that writer. Reject these explicitly instead
/// of accepting an unchecked prefix. All output/window allocations are bounded.
enum PcraftZstd {
  static let maximumBytes = 256 * 1024 * 1024
  static func decode(_ data: Data, limit: Int, expectedBytes: Int? = nil) throws -> Data {
    try Task.checkCancellation()
    guard (0...maximumBytes).contains(limit), data.count <= maximumBytes,
      expectedBytes == nil || (0...limit).contains(expectedBytes!) else {
      throw CraftError.invalid("PhotoCraft blob exceeds the decompression limit.")
    }
    var input = PcraftBytes(bytes: [UInt8](data))
    guard try input.number(4) == 0xFD2FB528 else {
      throw CraftError.invalid("Unsupported PhotoCraft Zstandard frame.")
    }
    let descriptor = Int(try input.number(1)), single = descriptor & 32 != 0
    guard descriptor & 8 == 0 else { throw CraftError.invalid("Reserved Zstandard frame flag.") }
    var window: UInt64 = 0
    if !single {
      let value = Int(try input.number(1)), base = UInt64(1) << (10 + (value >> 3))
      window = base + (base / 8) * UInt64(value & 7)
    }
    let dictionary = try input.number([0, 1, 2, 4][descriptor & 3])
    guard dictionary == 0 else { throw CraftError.invalid("PhotoCraft Zstandard dictionaries are unsupported.") }
    let sizeBytes = [single ? 1 : 0, 2, 4, 8][descriptor >> 6]
    var size: UInt64?
    if sizeBytes > 0 { size = try input.number(sizeBytes) + (sizeBytes == 2 ? 256 : 0) }
    if single { window = size! }
    guard window <= maximumBytes, size == nil || size! <= limit,
      expectedBytes == nil || size == nil || size! == expectedBytes! else {
      throw CraftError.invalid("PhotoCraft Zstandard size exceeds its declared budget.")
    }
    var decoder = Decoder(window: Int(window), limit: limit)
    if let size { decoder.output.reserveCapacity(Int(size)) }
    var last = false
    while !last {
      try Task.checkCancellation()
      let header = Int(try input.number(3)), kind = (header >> 1) & 3, count = header >> 3
      last = header & 1 != 0
      let blockLimit = min(Int(window), 128 * 1024)
      guard kind != 3, count <= blockLimit else {
        throw CraftError.invalid("Invalid PhotoCraft Zstandard block.")
      }
      let before = decoder.output.count
      switch kind {
      case 0:
        try decoder.room(count); decoder.output.append(contentsOf: try input.take(count))
      case 1:
        try decoder.room(count)
        decoder.output.append(contentsOf: repeatElement(UInt8(try input.number(1)), count: count))
      default:
        try decoder.compressed(input.take(count))
      }
      guard decoder.output.count - before <= blockLimit else {
        throw CraftError.invalid("Oversized decompressed Zstandard block.")
      }
    }
    if descriptor & 4 != 0 {
      let checksum = try input.number(4)
      guard try UInt32(truncatingIfNeeded: PcraftXXHash64.hash(decoder.output)) == checksum else {
        throw CraftError.invalid("PhotoCraft Zstandard checksum mismatch.")
      }
    }
    guard input.remaining == 0, size == nil || decoder.output.count == size!,
      expectedBytes == nil || decoder.output.count == expectedBytes! else {
      throw CraftError.invalid("PhotoCraft Zstandard length or trailing-data mismatch.")
    }
    return Data(decoder.output)
  }

  private struct Decoder {
    let window: Int
    let limit: Int
    var output: [UInt8] = []
    var huffman: PcraftZstdHuffman?
    var tables: [PcraftZstdFSE?] = [nil, nil, nil]
    var offsets = [1, 4, 8]
    func room(_ count: Int) throws {
      guard count >= 0, count <= limit - output.count else {
        throw CraftError.invalid("PhotoCraft decompressed blob exceeds its limit.")
      }
    }
    mutating func literals(_ input: inout PcraftBytes) throws -> [UInt8] {
      let first = Int(try input.number(1)), kind = first & 3, format = (first >> 2) & 3
      if kind < 2 {
        let size: Int
        switch format {
        case 0, 2: size = first >> 3
        case 1: size = (first >> 4) | (Int(try input.number(1)) << 4)
        default: size = (first >> 4) | (Int(try input.number(2)) << 4)
        }
        guard size <= 128 * 1024, size <= limit - output.count else {
          throw CraftError.invalid("Oversized Zstandard literals.")
        }
        return kind == 0 ? try input.take(size) : Array(repeating: UInt8(try input.number(1)), count: size)
      }
      let width = format < 2 ? 10 : (format == 2 ? 14 : 18)
      let rest = try input.number(format < 2 ? 2 : (format == 2 ? 3 : 4))
      let header = UInt64(first) | (rest << 8)
      let size = Int((header >> 4) & ((1 << width) - 1)), compressed = Int(header >> (4 + width))
      guard size <= 128 * 1024, size <= limit - output.count else {
        throw CraftError.invalid("Oversized Zstandard literals.")
      }
      var stream = try PcraftBytes(bytes: input.take(compressed))
      if kind == 2 { huffman = try PcraftZstdHuffman.read(&stream) }
      guard let huffman else { throw CraftError.invalid("Missing Zstandard Huffman table.") }
      if format == 0 { return try huffman.decode(stream.take(stream.remaining), count: size) }
      guard size >= 6 else { throw CraftError.invalid("Undersized four-stream Zstandard literals.") }
      let counts = [Int(try stream.number(2)), Int(try stream.number(2)), Int(try stream.number(2))]
      let segment = (size + 3) / 4
      var result: [UInt8] = []; result.reserveCapacity(size)
      for i in 0..<4 {
        result.append(contentsOf: try huffman.decode(
          stream.take(i == 3 ? stream.remaining : counts[i]),
          count: i == 3 ? size - segment * 3 : segment))
      }
      return result
    }
    mutating func compressed(_ bytes: [UInt8]) throws {
      var input = PcraftBytes(bytes: bytes)
      let literals = try literals(&input), first = Int(try input.number(1))
      let sequences: Int
      if first < 128 { sequences = first }
      else if first < 255 { sequences = ((first - 128) << 8) + Int(try input.number(1)) }
      else { sequences = Int(try input.number(2)) + 0x7F00 }
      if sequences == 0 {
        guard input.remaining == 0 else { throw CraftError.invalid("Trailing Zstandard sequence bytes.") }
        try room(literals.count); output.append(contentsOf: literals); return
      }
      let modes = Int(try input.number(1))
      guard modes & 3 == 0 else { throw CraftError.invalid("Reserved Zstandard sequence flags.") }
      let maximums = [35, 31, 52]
      for i in 0..<3 {
        switch (modes >> (6 - i * 2)) & 3 {
        case 0: tables[i] = try PcraftZstdFSE(counts: Self.distributions[i], log: i == 1 ? 5 : 6)
        case 1:
          let symbol = Int(try input.number(1))
          guard symbol <= maximums[i] else { throw CraftError.invalid("Invalid Zstandard RLE symbol.") }
          tables[i] = PcraftZstdFSE(symbol: symbol)
        case 2: tables[i] = try PcraftZstdFSE.read(&input, maxSymbol: maximums[i], maxLog: i == 1 ? 8 : 9)
        default:
          guard tables[i] != nil else { throw CraftError.invalid("Missing Zstandard sequence table.") }
        }
      }
      let ll = tables[0]!, of = tables[1]!, ml = tables[2]!
      var bits = try PcraftReverseBits(input.take(input.remaining))
      var states = [try bits.read(ll.log), try bits.read(of.log), try bits.read(ml.log)]
      var literalPosition = 0
      let blockStart = output.count
      for sequence in 0..<sequences {
        if sequence & 1023 == 0 { try Task.checkCancellation() }
        let l = ll.entries[states[0]], o = of.entries[states[1]], m = ml.entries[states[2]]
        let encodedOffset = (1 << o.symbol) + (try bits.read(o.symbol))
        let matchLength = Self.matchBase[m.symbol] + (try bits.read(Self.matchBits[m.symbol]))
        let literalLength = Self.literalBase[l.symbol] + (try bits.read(Self.literalBits[l.symbol]))
        guard literalLength <= literals.count - literalPosition,
          output.count - blockStart + literalLength + matchLength <= 128 * 1024 else {
          throw CraftError.invalid("Invalid Zstandard sequence lengths.")
        }
        try room(literalLength + matchLength)
        output.append(contentsOf: literals[literalPosition..<(literalPosition + literalLength)])
        literalPosition += literalLength
        let offset: Int
        if encodedOffset > 3 {
          offset = encodedOffset - 3; offsets = [offset, offsets[0], offsets[1]]
        } else {
          let index = encodedOffset - 1 + (literalLength == 0 ? 1 : 0)
          if index == 3 {
            offset = offsets[0] - 1; offsets = [offset, offsets[0], offsets[1]]
          } else {
            offset = offsets.remove(at: index); offsets.insert(offset, at: 0)
          }
        }
        guard offset > 0, offset <= output.count, offset <= window else {
          throw CraftError.invalid("Invalid Zstandard back-reference.")
        }
        for _ in 0..<matchLength { output.append(output[output.count - offset]) }
        if sequence + 1 < sequences {
          states[0] = l.base + (try bits.read(l.bits))
          states[2] = m.base + (try bits.read(m.bits))
          states[1] = o.base + (try bits.read(o.bits))
        }
      }
      guard bits.remaining == 0 else { throw CraftError.invalid("Trailing Zstandard sequence bits.") }
      try room(literals.count - literalPosition)
      output.append(contentsOf: literals[literalPosition...])
    }
    static let literalBase = Array(0...15) + [
      16,18,20,22,24,28,32,40,48,64,128,256,512,1024,2048,4096,8192,16384,32768,65536,
    ]
    static let literalBits = Array(repeating: 0, count: 16) + [
      1,1,1,1,2,2,3,3,4,6,7,8,9,10,11,12,13,14,15,16,
    ]
    static let matchBase = Array(3...34) + [
      35,37,39,41,43,47,51,59,67,83,99,131,259,515,1027,2051,4099,8195,16387,32771,65539,
    ]
    static let matchBits = Array(repeating: 0, count: 32) + [
      1,1,1,1,2,2,3,3,4,4,5,7,8,9,10,11,12,13,14,15,16,
    ]
    static let distributions = [
      [4,3,2,2,2,2,2,2,2,2,2,2,2,1,1,1,2,2,2,2,2,2,2,2,2,3,2,1,1,1,1,1,-1,-1,-1,-1],
      [1,1,1,1,1,1,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,-1,-1,-1,-1,-1],
      [1,4,3,2,2,2,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
       1,1,1,1,1,1,1,1,1,1,1,1,1,1,-1,-1,-1,-1,-1,-1,-1],
    ]
  }
}
