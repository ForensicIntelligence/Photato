import Foundation
import PhotoCraftCore

/// Two-pass baseline Huffman optimization. DCT coefficients, quantization,
/// component sampling and all non-Huffman metadata stay unchanged.
/// Original Swift implementation of canonical, length-limited Huffman coding.
enum JPEGEntropyOptimizer {
  private struct Table {
    var counts: [Int]
    var symbols: [Int]
    var decode: [Int: Int] = [:]
    var encode: [Int: (code: Int, length: Int)] = [:]
    init(counts: [Int], symbols: [Int]) throws {
      guard counts.count == 17, counts[0] == 0, counts.dropFirst().allSatisfy({ (0...255).contains($0) }),
        counts.reduce(0, +) == symbols.count, !symbols.isEmpty, symbols.count <= 256,
        Set(symbols).count == symbols.count, symbols.allSatisfy({ (0...255).contains($0) })
      else { throw JPEGContainer.invalid() }
      self.counts = counts; self.symbols = symbols
      var code = 0, index = 0
      for length in 1...16 {
        for _ in 0..<counts[length] {
          // JPEG reserves the all-ones code for entropy padding.
          guard code < (1 << length) - 1 else { throw JPEGContainer.invalid() }
          let symbol = symbols[index]; index += 1
          decode[(1 << length) | code] = symbol
          encode[symbol] = (code, length)
          code += 1
        }
        code <<= 1
      }
    }
    func symbol(_ reader: inout Reader) throws -> Int {
      var code = 0
      for length in 1...16 {
        code = (code << 1) | (try reader.read(1))
        if let symbol = decode[(1 << length) | code] { return symbol }
      }
      throw JPEGContainer.invalid()
    }
    static func optimized(_ frequencies: [Int]) throws -> Table {
      struct Node { var weight: Int; var leaves: [Int]; var tie: Int }
      var nodes = frequencies.enumerated().compactMap { index, count in
        count > 0 ? Node(weight: count, leaves: [index], tie: index) : nil
      }
      // A dummy leaf reserves a missing all-ones code after canonical assignment.
      nodes.append(Node(weight: 1, leaves: [256], tie: 256))
      guard nodes.count > 1 else { throw JPEGContainer.invalid() }
      var depths = [Int](repeating: 0, count: 257)
      while nodes.count > 1 {
        nodes.sort { $0.weight == $1.weight ? $0.tie < $1.tie : $0.weight < $1.weight }
        let a = nodes.removeFirst(), b = nodes.removeFirst()
        let leaves = a.leaves + b.leaves
        for leaf in leaves { depths[leaf] += 1 }
        nodes.append(Node(weight: a.weight + b.weight, leaves: leaves, tie: min(a.tie, b.tie)))
      }
      var counts = [Int](repeating: 0, count: max(17, (depths.max() ?? 0) + 1))
      for depth in depths where depth > 0 { counts[depth] += 1 }
      if counts.count > 17 {
        for length in stride(from: counts.count - 1, through: 17, by: -1) {
          while counts[length] > 0 {
            guard counts[length] >= 2 else { throw JPEGContainer.invalid() }
            var shorter = length - 2
            while shorter > 0 && counts[shorter] == 0 { shorter -= 1 }
            guard shorter > 0 else { throw JPEGContainer.invalid() }
            counts[length] -= 2; counts[length - 1] += 1
            counts[shorter] -= 1; counts[shorter + 1] += 2
          }
        }
      }
      guard let longest = (1...16).last(where: { counts[$0] > 0 }) else { throw JPEGContainer.invalid() }
      counts[longest] -= 1
      let symbols = (0..<256).filter { frequencies[$0] > 0 }.sorted {
        depths[$0] == depths[$1] ? $0 < $1 : depths[$0] < depths[$1]
      }
      return try Table(counts: Array(counts.prefix(17)), symbols: symbols)
    }
  }
  private struct Reader {
    let bytes: [UInt8], end: Int
    var position: Int
    var buffer = 0, remaining = 0
    mutating func read(_ count: Int) throws -> Int {
      var value = 0
      for _ in 0..<count {
        if remaining == 0 {
          guard position < end else { throw JPEGContainer.invalid() }
          buffer = Int(bytes[position]); position += 1
          if buffer == 255 {
            guard position < end, bytes[position] == 0 else { throw JPEGContainer.invalid() }
            position += 1
          }
          remaining = 8
        }
        remaining -= 1; value = (value << 1) | ((buffer >> remaining) & 1)
      }
      return value
    }
    func finish() throws {
      guard position == end, buffer & ((1 << remaining) - 1) == (1 << remaining) - 1
      else { throw JPEGContainer.invalid() }
    }
    mutating func restart(_ sequence: Int) throws {
      guard buffer & ((1 << remaining) - 1) == (1 << remaining) - 1,
        position < end, bytes[position] == 255 else { throw JPEGContainer.invalid() }
      while position < end && bytes[position] == 255 { position += 1 }
      guard position < end, bytes[position] == 208 + sequence else { throw JPEGContainer.invalid() }
      position += 1; buffer = 0; remaining = 0
    }
  }
  private struct Writer {
    var bytes = Data(), buffer = 0, count = 0
    mutating func write(_ value: Int, _ length: Int) throws {
      guard length > 0 else { return }
      for bit in stride(from: length - 1, through: 0, by: -1) {
        buffer = (buffer << 1) | ((value >> bit) & 1); count += 1
        if count == 8 {
          guard bytes.count + 2 <= JPEGContainer.maximumBytes else { throw JPEGContainer.invalid() }
          bytes.append(UInt8(buffer)); if buffer == 255 { bytes.append(0) }
          buffer = 0; count = 0
        }
      }
    }
    mutating func finish() throws {
      if count > 0 { try write((1 << (8 - count)) - 1, 8 - count) }
    }
    mutating func restart(_ sequence: Int) throws {
      try finish()
      guard bytes.count + 2 <= JPEGContainer.maximumBytes else { throw JPEGContainer.invalid() }
      bytes.append(contentsOf: [255, UInt8(208 + sequence)])
    }
  }
  private struct Component {
    let id: Int, horizontal: Int, vertical: Int
  }
  static func optimize(_ data: Data) throws -> Data {
    guard data.count <= JPEGContainer.maximumBytes else { throw JPEGContainer.invalid() }
    let bytes = [UInt8](data), records = try JPEGContainer.segments(bytes)
    let frames = records.filter { (192...207).contains($0.marker) && ![196, 200, 204].contains($0.marker) }
    guard frames.count == 1, frames[0].marker == 192,
      records.filter({ $0.marker == 218 }).count == 1,
      let scan = records.first(where: { $0.marker == 218 }), let entropy = scan.entropy
    else { throw JPEGContainer.invalid() }
    // Restrict to the platform's baseline, single interleaved scan output.
    guard records.allSatisfy({ [192,196,218,217,219,221,254].contains($0.marker) || (224...239).contains($0.marker) }),
      records.last?.marker == 217, scan.range.lowerBound > frames[0].range.lowerBound,
      records.filter({ $0.marker == 196 || $0.marker == 219 }).allSatisfy({ $0.range.upperBound <= scan.range.lowerBound })
    else { throw JPEGContainer.invalid() }
    var restartInterval = 0
    let restartRecords = records.filter { $0.marker == 221 }
    guard restartRecords.count <= 1 else { throw JPEGContainer.invalid() }
    for record in restartRecords {
      guard record.payload.count == 2, record.range.upperBound <= scan.range.lowerBound
      else { throw JPEGContainer.invalid() }
      restartInterval = Int(bytes[record.payload.lowerBound]) * 256 + Int(bytes[record.payload.lowerBound + 1])
    }
    let frame = Array(bytes[frames[0].payload])
    guard frame.count >= 6, frame[0] == 8, [1,3].contains(frame[5]),
      frame.count == 6 + 3 * Int(frame[5]) else { throw JPEGContainer.invalid() }
    let height = Int(frame[1]) * 256 + Int(frame[2]), width = Int(frame[3]) * 256 + Int(frame[4])
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= Surface.maxPixels / height else { throw JPEGContainer.invalid() }
    let components = (0..<Int(frame[5])).map { index -> Component in
      let offset = 6 + 3 * index
      return Component(id: Int(frame[offset]), horizontal: Int(frame[offset + 1] >> 4),
        vertical: Int(frame[offset + 1] & 15))
    }
    guard Set(components.map(\.id)).count == components.count,
      components.allSatisfy({ (1...4).contains($0.horizontal) && (1...4).contains($0.vertical) }),
      components.reduce(0, { $0 + $1.horizontal * $1.vertical }) <= 10 else { throw JPEGContainer.invalid() }
    let header = Array(bytes[scan.payload])
    guard header.count == 4 + 2 * components.count, Int(header[0]) == components.count,
      Array(header.suffix(3)) == [0,63,0] else { throw JPEGContainer.invalid() }
    var tables: [Int: Table] = [:]
    for record in records where record.marker == 196 {
      var position = record.payload.lowerBound
      while position < record.payload.upperBound {
        guard position + 17 <= record.payload.upperBound else { throw JPEGContainer.invalid() }
        let id = Int(bytes[position]); position += 1
        guard [0,1,2,3,16,17,18,19].contains(id) else { throw JPEGContainer.invalid() }
        let counts = [0] + bytes[position..<(position + 16)].map(Int.init); position += 16
        let size = counts.reduce(0, +)
        guard size <= record.payload.upperBound - position, tables[id] == nil else { throw JPEGContainer.invalid() }
        tables[id] = try Table(counts: counts, symbols: bytes[position..<(position + size)].map(Int.init))
        position += size
      }
    }
    var blocks: [(dc: Int, ac: Int)] = []
    var seen = Set<Int>()
    for index in components.indices {
      let id = Int(header[1 + index * 2]), selectors = Int(header[2 + index * 2])
      guard seen.insert(id).inserted, let component = components.first(where: { $0.id == id }),
        selectors >> 4 <= 3, selectors & 15 <= 3,
        tables[selectors >> 4] != nil, tables[16 | (selectors & 15)] != nil else { throw JPEGContainer.invalid() }
      for _ in 0..<(components.count == 1 ? 1 : component.horizontal * component.vertical) {
        blocks.append((selectors >> 4, 16 | (selectors & 15)))
      }
    }
    let h = components.count == 1 ? 1 : components.map(\.horizontal).max()!
    let v = components.count == 1 ? 1 : components.map(\.vertical).max()!
    let mcus = ((width + h * 8 - 1) / (h * 8)) * ((height + v * 8 - 1) / (v * 8))
    var frequencies = tables.mapValues { _ in [Int](repeating: 0, count: 256) }
    func walk(_ visit: (Int, Int, Int, Int) throws -> Void,
      restart: (Int) throws -> Void) throws {
      var reader = Reader(bytes: bytes, end: entropy.upperBound, position: entropy.lowerBound)
      for mcu in 0..<mcus {
        try Task.checkCancellation()
        if restartInterval > 0 && mcu > 0 && mcu % restartInterval == 0 {
          let sequence = (mcu / restartInterval - 1) % 8
          try reader.restart(sequence); try restart(sequence)
        }
        for block in blocks {
          let dc = try tables[block.dc]!.symbol(&reader)
          guard dc <= 11 else { throw JPEGContainer.invalid() }
          try visit(block.dc, dc, reader.read(dc), dc)
          var coefficient = 1
          while coefficient < 64 {
            let ac = try tables[block.ac]!.symbol(&reader)
            let run = ac >> 4, size = ac & 15
            if size == 0 {
              guard ac == 0 || ac == 240 else { throw JPEGContainer.invalid() }
              try visit(block.ac, ac, 0, 0)
              if ac == 0 { break }
              coefficient += 16
              guard coefficient <= 64 else { throw JPEGContainer.invalid() }
            } else {
              guard size <= 10, coefficient + run < 64 else { throw JPEGContainer.invalid() }
              try visit(block.ac, ac, reader.read(size), size)
              coefficient += run + 1
            }
          }
        }
      }
      try reader.finish()
    }
    try walk({ id, symbol, _, _ in frequencies[id]![symbol] += 1 }, restart: { _ in })
    var optimized: [Int: Table] = [:]
    for (id, frequency) in frequencies where frequency.contains(where: { $0 > 0 }) {
      optimized[id] = try Table.optimized(frequency)
    }
    var writer = Writer()
    try walk({ id, symbol, value, length in
      guard let code = optimized[id]?.encode[symbol] else { throw JPEGContainer.invalid() }
      try writer.write(code.code, code.length); try writer.write(value, length)
    }, restart: { sequence in try writer.restart(sequence) })
    try writer.finish()
    var dht = Data()
    for id in optimized.keys.sorted() {
      let table = optimized[id]!
      dht.append(UInt8(id)); dht.append(contentsOf: table.counts.dropFirst().map(UInt8.init))
      dht.append(contentsOf: table.symbols.map(UInt8.init))
    }
    var output = Data([255,216])
    for record in records {
      if record.marker == 196 { continue }
      if record.marker == 218 {
        let size = dht.count + 2
        output.append(contentsOf: [255,196,UInt8(size >> 8),UInt8(size & 255)])
        output.append(dht)
      }
      output.append(contentsOf: bytes[record.range])
      if record.entropy != nil { output.append(writer.bytes) }
      guard output.count <= JPEGContainer.maximumBytes else { throw JPEGContainer.invalid() }
    }
    return output
  }
}
