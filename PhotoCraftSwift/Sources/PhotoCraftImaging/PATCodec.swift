import Foundation
import PhotoCraftCore

/// Adobe 8BPT v1 presets: RGB, grayscale and indexed patterns, with bounded VMA arrays.
/// Uses the public specification and PhotoCraft psd/patterns.rs as format references.
public enum PATCodec {
  public struct Library: Sendable {
    public let patterns: [RasterPattern]
    public let foldersFlattened: Bool
    public let duplicateRecordsMerged: Int
  }
  /// PhotoCraft's PackBits packet boundaries, including two-byte runs at packet starts.
  static func packBits(_ source: [UInt8]) -> [UInt8] {
    var output: [UInt8] = []
    var i = 0
    while i < source.count {
      var run = 1
      while i + run < source.count && run < 128 && source[i + run] == source[i] { run += 1 }
      if run >= 2 {
        output.append(UInt8(bitPattern: Int8(1 - run)))
        output.append(source[i])
        i += run
        continue
      }
      let start = i
      var length = 0
      while i < source.count && length < 128 {
        if i + 2 < source.count && source[i] == source[i + 1] && source[i] == source[i + 2] {
          break
        }
        i += 1
        length += 1
      }
      output.append(UInt8(length - 1))
      output.append(contentsOf: source[start..<start + length])
    }
    return output
  }
  struct Plane {
    let depth: Int
    let bytes: [UInt8]
  }
  static func rect(_ r: inout PSDReader) throws -> IntRect {
    let top = try r.i32()
    let left = try r.i32()
    let bottom = try r.i32()
    let right = try r.i32()
    let width = right - left
    let height = bottom - top
    guard width > 0, height > 0, width <= 30_000, height <= 30_000,
      width <= RasterPattern.maxPixels / height
    else {
      throw CraftError.invalid("Invalid PAT channel dimensions.")
    }
    return .init(x: left, y: top, width: width, height: height)
  }
  public static func read(_ data: Data) throws -> [RasterPattern] {
    try readLibrary(data).patterns
  }
  public static func readLibrary(_ data: Data, tileBudget: Int = 1_073_741_824) throws -> Library {
    guard data.count <= PatternArchive.maxBytes else {
      throw CraftError.invalid("PAT file is too large.")
    }
    var r = PSDReader(data: data)
    guard try r.string(4) == "8BPT", try r.u16() == 1 else {
      throw CraftError.unsupported("Expected a Photoshop version 1 PAT library.")
    }
    let count = try r.u32()
    guard count <= PatternArchive.maxCount else {
      throw CraftError.invalid("Too many PAT presets.")
    }
    var patterns: [RasterPattern] = []
    var pixels = 0
    var storage = 0
    for _ in 0..<count {
      try Task.checkCancellation()
      guard try r.u32() == 1 else { throw CraftError.unsupported("Unknown PAT pattern version.") }
      let mode = try r.u32()
      guard [1, 2, 3].contains(mode) else {
        throw CraftError.unsupported(
          "PAT color mode \(mode) is not supported. Use RGB, grayscale or indexed patterns.")
      }
      _ = try r.u16()
      _ = try r.u16()  // VMA rectangle is authoritative.
      let length = try r.u32()
      guard length <= 65_536 else { throw CraftError.invalid("PAT name is too long.") }
      var units: [UInt16] = []
      for _ in 0..<length { units.append(UInt16(try r.u16())) }
      while units.last == 0 { units.removeLast() }
      let name = String(decoding: units, as: UTF16.self)
      let id = try r.string(Int(r.u8()))
      let palette = mode == 2 ? Array(try r.bytes(768)) : []
      var version = try r.u32()
      // A few indexed writers insert one extra word after the palette.
      if mode == 2 && version != 3 { version = try r.u32() }
      guard version == 3 else {
        throw CraftError.unsupported("Unknown PAT virtual-memory list version.")
      }
      var arrays = try r.section()
      let box = try rect(&arrays)
      pixels += box.width * box.height
      storage += ((box.width + 63) / 64) * ((box.height + 63) / 64) * 65_536
      guard pixels <= PatternArchive.maxTotalPixels else {
        throw CraftError.invalid("PAT library exceeds its decoded pixel budget.")
      }
      guard storage <= min(1_073_741_824, tileBudget) else {
        throw CraftError.invalid("PAT library exceeds its tiled storage budget.")
      }
      let slots = try arrays.u32()
      guard (1...64).contains(slots) else { throw CraftError.invalid("Invalid PAT channel count.") }
      let channels = mode == 3 ? 3 : 1
      var planes: [Plane] = []
      var decodedBytes = 0
      for _ in 0..<slots + 2 {
        try Task.checkCancellation()
        let written = try arrays.u32()
        guard written <= 1 else { throw CraftError.invalid("Invalid PAT array flag.") }
        if written == 0 { continue }
        let size = try arrays.u32()
        if size == 0 { continue }
        guard size >= 23 else { throw CraftError.invalid("Truncated PAT virtual-memory array.") }
        var a = PSDReader(data: try arrays.bytes(size))
        let depth32 = try a.u32()
        let frame = try rect(&a)
        let depth16 = try a.u16()
        let compression = Int(try a.u8())
        let depth = [1, 8, 16, 32].contains(depth16) ? depth16 : depth32
        guard [1, 8, 16, 32].contains(depth), mode != 2 || depth == 8,
          planes.count <= channels
        else { throw CraftError.unsupported("Unsupported PAT channel layout or depth.") }
        let rowBytes = (frame.width * depth + 7) / 8
        let expected = rowBytes * frame.height
        decodedBytes += expected
        guard decodedBytes <= 256 * 1024 * 1024 else {
          throw CraftError.invalid("PAT channel memory budget exceeded.")
        }
        let bytes: [UInt8]
        if compression == 0 {
          bytes = Array(try a.bytes(expected))
        } else if compression == 1 {
          var lengths: [Int] = []
          for _ in 0..<frame.height { lengths.append(try a.u16()) }
          var decoded: [UInt8] = []
          decoded.reserveCapacity(expected)
          for length in lengths {
            try Task.checkCancellation()
            decoded.append(
              contentsOf: try PSDCodec.decodePackBits(a.bytes(length), expected: rowBytes))
          }
          bytes = decoded
        } else {
          throw CraftError.unsupported("PAT compression \(compression) is not supported.")
        }
        guard a.remaining == 0 else { throw CraftError.invalid("Unexpected PAT channel bytes.") }
        if let first = planes.first, first.depth != depth {
          throw CraftError.unsupported("Mixed-depth PAT channels are not supported.")
        }
        // Expand channels to the VMA canvas, including packed one-bit rows and offsets.
        let fullRow = (box.width * depth + 7) / 8
        var full = [UInt8](repeating: 0, count: fullRow * box.height)
        for y in 0..<frame.height {
          try Task.checkCancellation()
          let dy = y + frame.y - box.y
          guard dy >= 0, dy < box.height else { continue }
          for x in 0..<frame.width {
            let dx = x + frame.x - box.x
            guard dx >= 0, dx < box.width else { continue }
            if depth == 1 {
              if bytes[y * rowBytes + x / 8] & (0x80 >> (x % 8)) != 0 {
                full[dy * fullRow + dx / 8] |= 0x80 >> (dx % 8)
              }
            } else {
              let size = depth / 8
              for b in 0..<size {
                full[dy * fullRow + dx * size + b] = bytes[y * rowBytes + x * size + b]
              }
            }
          }
        }
        planes.append(Plane(depth: depth, bytes: full))
      }
      guard arrays.remaining == 0, planes.count == channels || planes.count == channels + 1 else {
        throw CraftError.invalid("PAT channels do not match the declared color mode.")
      }
      let depth = planes[0].depth
      var surface = try Surface(
        width: box.width, height: box.height,
        depth: depth <= 8 ? .u8 : depth == 16 ? .u16 : .f32)
      func sample(_ channel: Int, _ x: Int, _ y: Int) -> Float {
        let bytes = planes[channel].bytes
        if depth == 1 {
          let bit = bytes[y * ((box.width + 7) / 8) + x / 8] & (0x80 >> (x % 8)) != 0
          return channel < channels ? (bit ? 0 : 1) : (bit ? 1 : 0)
        }
        let i = (y * box.width + x) * (depth / 8)
        if depth == 8 { return Float(bytes[i]) / 255 }
        if depth == 16 { return Float(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])) / 65535 }
        let bits = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[i + $1]) }
        return Float(bitPattern: bits)
      }
      for y in 0..<box.height {
        try Task.checkCancellation()
        for x in 0..<box.width {
          let alpha: Float = planes.count > channels ? sample(channels, x, y) : 1
          var p: Pixel
          if mode == 2 {
            let index = Int(planes[0].bytes[y * box.width + x]) * 3
            p = Pixel(
              Float(palette[index]) / 255, Float(palette[index + 1]) / 255,
              Float(palette[index + 2]) / 255, alpha)
          } else if mode == 1 {
            let gray = sample(0, x, y)
            p = Pixel(gray, gray, gray, alpha)
          } else {
            p = Pixel(sample(0, x, y), sample(1, x, y), sample(2, x, y), alpha)
          }
          guard p.isFinite, (0...1).contains(p.a), [p.r, p.g, p.b].allSatisfy({ abs($0) <= 1e12 })
          else {
            throw CraftError.invalid("PAT contains invalid pixel samples.")
          }
          surface.setPixel(x: x, y: y, p)
        }
      }
      patterns.append(try RasterPattern(name: name, surface: surface, id: id))
    }
    var foldersFlattened = false
    if r.remaining > 0 {
      // Photoshop's installed modern libraries append a folder-order descriptor.
      // Accept only the observed, validated layout; unknown metadata still rejects.
      guard try r.string(4) == "8BIM", try r.string(4) == "phry" else {
        throw CraftError.invalid("Unexpected trailing PAT data.")
      }
      let descriptor = try PSDDescriptor.read(r.bytes(r.u32()))
      guard descriptor.classID.text == "null", descriptor.items.count == 1,
        case .list(let entries) = descriptor["hierarchy"]
      else { throw CraftError.unsupported("Unsupported PAT folder hierarchy.") }
      var nesting = 0
      var presets = 0
      for entry in entries {
        guard case .object(let item) = entry else {
          throw CraftError.invalid("Invalid PAT folder entry.")
        }
        switch item.classID.text {
        case "Grup":
          guard item.items.count == 1, case .text = item["Nm  "], nesting < 64 else {
            throw CraftError.unsupported("Unsupported PAT folder settings.")
          }
          nesting += 1
          foldersFlattened = true
        case "groupEnd":
          guard item.items.isEmpty, nesting > 0 else {
            throw CraftError.invalid("Unbalanced PAT folders.")
          }
          nesting -= 1
        case "preset":
          guard item.items.isEmpty else {
            throw CraftError.unsupported("Unsupported PAT preset settings.")
          }
          presets += 1
        default: throw CraftError.unsupported("Unknown PAT folder entry.")
        }
      }
      guard nesting == 0, presets == patterns.count else {
        throw CraftError.invalid("PAT folders do not match the preset list.")
      }
    }
    guard r.remaining == 0 else { throw CraftError.invalid("Unexpected trailing PAT data.") }
    var unique: [RasterPattern] = []
    var indices: [String: Int] = [:]
    for pattern in patterns {
      if let index = indices[pattern.id] {
        let prior = unique[index]
        guard pattern.name == prior.name,
          try pattern.surface.changedTileBounds(comparedTo: prior.surface) == nil
        else {
          throw CraftError.invalid("PAT contains conflicting presets with the same identifier.")
        }
      } else {
        indices[pattern.id] = unique.count
        unique.append(pattern)
      }
    }
    try PatternArchive.validate(unique)
    return Library(
      patterns: unique, foldersFlattened: foldersFlattened,
      duplicateRecordsMerged: patterns.count - unique.count)
  }

  public static func write(_ patterns: [RasterPattern]) throws -> Data {
    try PatternArchive.validate(patterns)
    var out = PSDWriter()
    out.text("8BPT")
    out.n(1, 2)
    out.n(patterns.count, 4)
    for pattern in patterns {
      try Task.checkCancellation()
      let s = pattern.surface
      let width = s.width
      let height = s.height
      let depth = s.depth == .u8 ? 8 : s.depth == .u16 ? 16 : 32
      out.n(1, 4)
      out.n(3, 4)
      out.n(height, 2)
      out.n(width, 2)
      let units = Array(pattern.name.utf16) + [0]
      out.n(units.count, 4)
      for unit in units { out.n(Int(unit), 2) }
      out.n(pattern.id.utf8.count, 1)
      out.text(pattern.id)
      var body = PSDWriter()
      func rectangle(_ w: inout PSDWriter) { for value in [0, 0, height, width] { w.n(value, 4) } }
      rectangle(&body)
      body.n(24, 4)
      var hasAlpha = false
      for channel in 0..<4 {
        // Transparency occupies the user-mask slot after the 24 color slots.
        if channel == 3 {
          for _ in 3..<24 { body.n(0, 4) }
          if !hasAlpha {
            body.n(0, 4)
            break
          }
        }
        var plane = PSDWriter()
        plane.data.reserveCapacity(width * height * (depth / 8))
        for y in 0..<height {
          try Task.checkCancellation()
          for x in 0..<width {
            let p = s.pixel(x: x, y: y)
            if p.a < 1 { hasAlpha = true }
            let value = [p.r, p.g, p.b, p.a][channel]
            if depth == 32 {
              plane.n(Int(value.bitPattern), 4)
            } else {
              plane.n(Int((unit(value) * (depth == 8 ? 255 : 65535)).rounded()), depth / 8)
            }
          }
        }
        let compressed: Data
        if depth == 8 {
          var lengths = PSDWriter()
          var rows = Data()
          for y in 0..<height {
            try Task.checkCancellation()
            let row = packBits(Array(plane.data[y * width..<(y + 1) * width]))
            lengths.n(row.count, 2)
            rows.append(contentsOf: row)
          }
          lengths.data.append(rows)
          compressed = lengths.data
        } else {
          compressed = plane.data
        }
        body.n(1, 4)
        body.n(23 + compressed.count, 4)
        body.n(depth, 4)
        rectangle(&body)
        body.n(depth, 2)
        body.n(depth == 8 ? 1 : 0, 1)
        body.data.append(compressed)
      }
      body.n(0, 4)  // Unused sheet-mask slot.
      out.n(3, 4)
      out.section(body.data)
      guard out.data.count <= PatternArchive.maxBytes else {
        throw CraftError.invalid("PAT export exceeds the file budget.")
      }
    }
    return out.data
  }
}
