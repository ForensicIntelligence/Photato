import Foundation
import PhotoCraftCore

enum PSDPatternFill {
  struct Definition: Equatable {
    var name: String
    var fill: PatternFill
  }
  /// PhotoCraft's fill_frame contract: linked PSD phase is relative to the revealed
  /// mask frame. Native fills retain an absolute origin so later mask edits do not
  /// accidentally move their pixels. Convert only at the interchange boundary.
  static func frameOrigin(_ layer: Layer, width: Int, height: Int) throws -> (x: Float, y: Float) {
    let frame = try layer.fillFrame(width: width, height: height)
    return (Float(frame.x), Float(frame.y))
  }

  static func importPlacement(_ layer: inout Layer, width: Int, height: Int) throws {
    guard case .patternFill(var fill) = layer.content, fill.linked else { return }
    let origin = try frameOrigin(layer, width: width, height: height)
    fill.placement.phaseX += origin.x
    fill.placement.phaseY += origin.y
    try fill.validate()
    layer.content = .patternFill(fill)
  }
  static func exportPlacement(_ layer: Layer, width: Int, height: Int) throws -> PatternFill {
    guard case .patternFill(var fill) = layer.content else {
      throw CraftError.invalid("Expected a pattern fill.")
    }
    fill.placement = try fill.flattenedPlacement()
    fill.geometry = nil
    if fill.linked {
      let origin = try frameOrigin(layer, width: width, height: height)
      fill.placement.phaseX -= origin.x
      fill.placement.phaseY -= origin.y
    }
    try fill.validate()
    return fill
  }
  static func read(_ data: Data) throws -> Definition {
    let descriptor = try PSDDescriptor.read(data, padding: true)
    let allowed: Set<String> = ["Ptrn", "Scl ", "Angl", "Algn", "phase"]
    guard ["null", "patternLayer"].contains(descriptor.classID.text),
      Set(descriptor.items.map { $0.key.text }).count == descriptor.items.count,
      descriptor.items.allSatisfy({ allowed.contains($0.key.text) }),
      case .object(let reference) = descriptor["Ptrn"], reference.classID.text == "Ptrn",
      reference.items.count == 2,
      case .text(let name) = reference["Nm  "], case .text(let id) = reference["Idnt"]
    else { throw CraftError.unsupported("Unrepresented PSD Pattern Fill descriptor.") }
    func text(_ units: [UInt16]) -> String {
      String(decoding: units, as: UTF16.self).trimmingCharacters(
        in: CharacterSet(charactersIn: "\0"))
    }
    func number(_ value: PSDValue?, unit: String, fallback: Double) throws -> Float {
      guard let value else { return Float(fallback) }
      let result: Double
      if case .unit(let code, let bits) = value {
        guard code == Data(unit.utf8) else {
          throw CraftError.unsupported("Unsupported Pattern Fill unit.")
        }
        result = Double(bitPattern: bits)
      } else if let scalar = value.number {
        result = scalar
      } else {
        throw CraftError.invalid("Invalid Pattern Fill value.")
      }
      guard result.isFinite, abs(result) <= 1_000_000 else {
        throw CraftError.invalid("Pattern Fill value is out of range.")
      }
      return Float(result)
    }
    var fill = PatternFill(patternID: text(id))
    fill.placement.scale = try number(descriptor["Scl "], unit: "#Prc", fallback: 100)
    fill.placement.angle = try number(descriptor["Angl"], unit: "#Ang", fallback: 0)
    if let aligned = descriptor["Algn"] {
      guard case .boolean(let linked) = aligned else {
        throw CraftError.invalid("Invalid Pattern Fill link flag.")
      }
      fill.linked = linked
    }
    if let phase = descriptor["phase"] {
      guard case .object(let point) = phase, point.classID.text == "Pnt ",
        point.items.count == 2, point["Hrzn"] != nil, point["Vrtc"] != nil
      else { throw CraftError.unsupported("Unsupported Pattern Fill phase.") }
      fill.placement.phaseX = try number(point["Hrzn"], unit: "#Pxl", fallback: 0)
      fill.placement.phaseY = try number(point["Vrtc"], unit: "#Pxl", fallback: 0)
    }
    try fill.validate()
    return Definition(name: text(name), fill: fill)
  }
  static func write(_ fill: PatternFill, pattern: RasterPattern, original: Data? = nil) throws
    -> Data
  {
    var normalized = fill
    normalized.placement = try fill.flattenedPlacement()
    normalized.geometry = nil
    guard pattern.id == fill.patternID else {
      throw CraftError.invalid("Mismatched Pattern Fill reference.")
    }
    try normalized.validate()
    if let original, let decoded = try? read(original),
      decoded == Definition(name: pattern.name, fill: normalized)
    {
      return original
    }
    func text(_ string: String) -> PSDValue { .text(Array(string.utf16) + [0]) }
    let ref = PSDDescriptor(
      "Ptrn", items: [.init("Nm  ", text(pattern.name)), .init("Idnt", text(pattern.id))])
    let phase = PSDDescriptor(
      "Pnt ",
      items: [
        .init("Hrzn", .number(Double(normalized.placement.phaseX))),
        .init("Vrtc", .number(Double(normalized.placement.phaseY))),
      ])
    return try PSDDescriptor(
      "null",
      items: [
        .init("Scl ", .unit(Data("#Prc".utf8), Double(normalized.placement.scale).bitPattern)),
        .init("Ptrn", .object(ref)),
        .init("Angl", .unit(Data("#Ang".utf8), Double(normalized.placement.angle).bitPattern)),
        .init("Algn", .boolean(normalized.linked)), .init("phase", .object(phase)),
      ]
    ).encoded()
  }
}

enum PSDPatterns {
  static let keys = ["Patt", "Pat2", "Pat3"]
  static func read(_ data: Data, tileBudget: Int = 536_870_912) throws -> [RasterPattern] {
    guard data.count <= PatternArchive.maxBytes else {
      throw CraftError.invalid("PSD patterns are too large.")
    }
    var input = PSDReader(data: data)
    var records = Data()
    var count = 0
    while input.remaining >= 4 {
      let size = try input.u32()
      if size == 0 {
        guard input.remaining <= 3 else {
          throw CraftError.invalid("Unexpected PSD pattern terminator.")
        }
        break
      }
      count += 1
      guard count <= PatternArchive.maxCount else {
        throw CraftError.invalid("Too many embedded patterns.")
      }
      records.append(try input.bytes(size))
      let padding = try input.bytes((4 - size % 4) % 4)
      guard padding.allSatisfy({ $0 == 0 }) else {
        throw CraftError.invalid("Invalid PSD pattern padding.")
      }
    }
    guard try input.bytes(input.remaining).allSatisfy({ $0 == 0 }) else {
      throw CraftError.invalid("Unexpected embedded pattern data.")
    }
    var file = PSDWriter()
    file.text("8BPT")
    file.n(1, 2)
    file.n(count, 4)
    file.data.append(records)
    return try PATCodec.readLibrary(file.data, tileBudget: tileBudget).patterns
  }
  static func write(_ patterns: [RasterPattern]) throws -> Data {
    try PatternArchive.validate(patterns)
    var output = PSDWriter()
    for pattern in patterns {
      let body = try PATCodec.write([pattern]).dropFirst(10)
      output.section(Data(body))
      for _ in 0..<((4 - body.count % 4) % 4) { output.n(0, 1) }
      guard output.data.count <= PatternArchive.maxBytes else {
        throw CraftError.invalid("Embedded patterns exceed the file limit.")
      }
    }
    return output.data
  }
  static func exact(_ lhs: [RasterPattern], _ rhs: [RasterPattern]) throws -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (a, b) in zip(lhs, rhs) {
      guard a.id == b.id, a.name == b.name,
        try a.surface.changedTileBounds(comparedTo: b.surface) == nil
      else { return false }
    }
    return true
  }
  static func exportBlocks(_ document: CraftDocument) throws -> [(String, Data)] {
    let original = keys.compactMap { key in
      document.sourceMetadata?["psdGlobal_" + key].map { (key, $0) }
    }
    let patterns = document.patterns ?? []
    if !original.isEmpty {
      var decoded: [RasterPattern] = []
      for (_, data) in original {
        decoded += try read(
          data, tileBudget: 536_870_912 - decoded.reduce(0) { $0 + $1.surface.allocatedBytes })
      }
      if try exact(decoded, patterns) { return original }
    }
    guard !patterns.isEmpty else { return [] }
    let key = document.depth == .u8 ? "Patt" : document.depth == .u16 ? "Pat2" : "Pat3"
    return [(key, try write(patterns))]
  }
}
