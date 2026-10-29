import Foundation
import PhotoCraftCore

/// TIFF's Photoshop structures use the TIFF byte order, while channel sample
/// bytes remain big endian. Convert framing for the shared PSD reader/writer.
/// Only understood little-endian payloads are converted; opaque rich payloads
/// must not be passed to a big-endian decoder by guesswork.
enum TIFFLayerEndian {
  struct Cursor {
    let input: Data
    var output: Data
    var offset = 0
    var limit: Int
    let order: TIFFContainer.Order
    init(_ data: Data, order: TIFFContainer.Order = .little) {
      input = Data(data); output = Data(data); limit = data.count; self.order = order
    }
    var remaining: Int { limit - offset }
    mutating func skip(_ count: Int) throws {
      guard count >= 0, count <= remaining else { throw CraftError.invalid("Truncated TIFF layer record.") }
      offset += count
    }
    @discardableResult mutating func n(_ count: Int) throws -> Int {
      let start = offset
      try skip(count)
      let bytes = Data(input[start..<offset].reversed())
      output.replaceSubrange(start..<offset, with: bytes)
      let canonical = order == .little ? bytes : Data(input[start..<offset])
      let value = canonical.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
      // Eight-byte floating-point fields preserve their raw bits.
      return Int(truncatingIfNeeded: value)
    }
    mutating func i16() throws -> Int { Int(Int16(bitPattern: UInt16(try n(2)))) }
    mutating func i32() throws -> Int { Int(Int32(bitPattern: UInt32(try n(4)))) }
    mutating func word() throws -> String {
      let start = offset
      try skip(4)
      output.replaceSubrange(start..<offset, with: input[start..<offset].reversed())
      return String(decoding: (order == .little ? output : input)[start..<offset], as: UTF8.self)
    }
    mutating func padding() throws {
      guard input[offset..<limit].allSatisfy({ $0 == 0 }) else {
        throw CraftError.invalid("Invalid TIFF layer padding.")
      }
      offset = limit
    }
    mutating func mask() throws -> PSDMaskRecord? {
      let count = try n(4), start = offset, parentLimit = limit
      guard count <= remaining else { throw CraftError.invalid("Truncated TIFF mask.") }
      limit = start + count
      defer { limit = parentLimit }
      if count == 0 { return nil }
      for _ in 0..<4 { try n(4) }
      try skip(1)
      let flags = try n(1), parameters = flags & 16 != 0
      func fits(_ at: Int) -> Bool {
        guard parameters, at < start + count else { return false }
        let f = input[at]
        guard f & 0xf0 == 0 else { return false }
        let size = 1 + (f & 1 != 0 ? 1 : 0) + (f & 2 != 0 ? 8 : 0)
          + (f & 4 != 0 ? 1 : 0) + (f & 8 != 0 ? 8 : 0)
        return (at + size...at + size + 3).contains(start + count)
      }
      let realFirst = parameters && !fits(start + 18) && fits(start + 36)
      if realFirst {
        try skip(2); for _ in 0..<4 { try n(4) }
      }
      if parameters {
        let f = try n(1)
        guard f & 0xf0 == 0 else { throw CraftError.invalid("Invalid TIFF mask parameters.") }
        if f & 1 != 0 { try skip(1) }
        if f & 2 != 0 { try n(8) }
        if f & 4 != 0 { try skip(1) }
        if f & 8 != 0 { try n(8) }
      }
      if !realFirst && remaining >= 18 {
        try skip(2); for _ in 0..<4 { try n(4) }
      }
      try padding()
      return try PSDMaskRecord.read(Data((order == .little ? output : input)[start..<offset]))
    }
  }

  static func payload(_ input: Data, tag: String, global: Bool,
    order: TIFFContainer.Order = .little) throws -> Data {
    var c = Cursor(input, order: order)
    switch tag {
    case "luni":
      let count = try c.n(4)
      guard count <= c.remaining / 2 else { throw CraftError.invalid("Truncated TIFF Unicode name.") }
      for _ in 0..<count { try c.n(2) }
      try c.padding()
    case "lsct", "lsdk":
      guard [4, 12, 16].contains(input.count) else { throw CraftError.invalid("Invalid TIFF group record.") }
      try c.n(4)
      if c.remaining >= 8 { _ = try c.word(); _ = try c.word() }
      if c.remaining == 4 { try c.n(4) }
    case "lspf", "lyid", "lyvr":
      guard input.count == 4 else { throw CraftError.invalid("Invalid TIFF integer layer property.") }
      try c.n(4)
    case "lclr":
      guard input.count == 8 else { throw CraftError.invalid("Invalid TIFF layer color.") }
      try c.n(2); try c.padding()
    case "fxrp":
      guard input.count == 16 else { throw CraftError.invalid("Invalid TIFF reference point.") }
      try c.n(8); try c.n(8)
    case "lnsr", "clbl", "infx", "lmgm", "vmgm", "knko", "iOpa":
      // Byte-valued flags and the opaque layer-name-source identifier.
      return input
    case "LMsk" where global, "FMsk" where global:
      guard input.count >= 12, input.count <= 16 else {
        throw CraftError.invalid("Invalid TIFF user-mask display metadata.")
      }
      for _ in 0..<6 { try c.n(2) }
      try c.skip(c.remaining)
    case "Mt16" where global, "Mt32" where global, "Mtrn" where global:
      guard input.isEmpty else { throw CraftError.unsupported("Nonempty TIFF transparency metadata.") }
    case "levl", "curv", "hue2", "blnc", "thrs", "post", "grdm", "vmsk", "vsms":
      return try TIFFRichEndian.convert(input, tag: tag, order: order)
    default:
      throw CraftError.unsupported(
        "Little-endian TIFF Photoshop block '\(tag)' is not yet supported. Choose big-endian TIFF or PSD to preserve its contents.")
    }
    return c.output
  }

  static func layers(_ data: Data, order: TIFFContainer.Order,
    target: TIFFContainer.Order = .big) throws -> Data {
    if order == target { return data }
    var c = Cursor(data, order: order)
    let count = abs(try c.i16())
    guard count <= 1024 else { throw CraftError.invalid("TIFF exceeds the layer record limit.") }
    var channels: [(length: Int, height: Int)] = []
    for _ in 0..<count {
      try Task.checkCancellation()
      let top = try c.i32(), left = try c.i32()
      let bottom = try c.i32(), right = try c.i32()
      let height = bottom - top, width = right - left, number = try c.n(2)
      guard (0...Surface.maxDimension).contains(height),
        (0...Surface.maxDimension).contains(width), number <= 6 else {
        throw CraftError.invalid("Invalid TIFF layer bounds or channel count.")
      }
      var current: [(id: Int, length: Int)] = []
      for _ in 0..<number { current.append((try c.i16(), try c.n(4))) }
      guard try c.word() == "8BIM" else { throw CraftError.invalid("Invalid TIFF layer signature.") }
      _ = try c.word(); try c.skip(4)
      let extraSize = try c.n(4), extraStart = c.offset, parentLimit = c.limit
      guard extraSize <= c.remaining else { throw CraftError.invalid("Truncated TIFF layer extras.") }
      c.limit = extraStart + extraSize
      let mask = try c.mask()
      let rangeSize = try c.n(4)
      guard rangeSize % 4 == 0, rangeSize <= c.remaining else {
        throw CraftError.invalid("Invalid TIFF blending ranges.")
      }
      for _ in 0..<rangeSize / 4 { try c.n(4) }
      let nameCount = try c.n(1)
      try c.skip(nameCount + (4 - (nameCount + 1) % 4) % 4)
      while c.remaining >= 12 {
        guard try c.word() == "8BIM" else { throw CraftError.invalid("Invalid TIFF layer tag signature.") }
        let key = try c.word(), size = try c.n(4), at = c.offset
        try c.skip(size)
        let converted = try payload(Data(c.input[at..<c.offset]), tag: key, global: false, order: order)
        c.output.replaceSubrange(at..<c.offset, with: converted)
        if size % 2 != 0 { try c.skip(1) }
      }
      try c.padding()
      c.limit = parentLimit
      for channel in current {
        let rows: Int
        if channel.id < -1 {
          guard let mask else { throw CraftError.invalid("Missing TIFF channel mask.") }
          let bounds = try mask.selected(channel.id).0
          rows = bounds.width == 0 ? 0 : bounds.height
        } else { rows = width == 0 ? 0 : height }
        channels.append((channel.length, rows))
      }
    }
    for channel in channels {
      try Task.checkCancellation()
      let start = c.offset
      guard channel.length >= 2, channel.length <= c.remaining else {
        throw CraftError.invalid("Truncated TIFF layer channel.")
      }
      let parentLimit = c.limit
      c.limit = start + channel.length
      let compression = try c.n(2)
      guard compression <= 3 else { throw CraftError.unsupported("Unsupported TIFF layer compression.") }
      if compression == 1 {
        guard channel.height <= c.remaining / 2 else { throw CraftError.invalid("Truncated TIFF RLE row table.") }
        for _ in 0..<channel.height { try c.n(2) }
      }
      try c.skip(c.remaining)
      c.limit = parentLimit
    }
    try c.padding()
    return c.output
  }
}
