import Foundation
import PhotoCraftCore

/// PSD path records are 26 bytes; six signed 8.24 coordinates are stored vertical-first.
enum PSDPaths {
  static func readNames(_ data: Data) throws -> [String] {
    var r = PSDReader(data: data)
    func key() throws -> String {
      let count = try r.u32()
      guard count <= 1024 else { throw CraftError.invalid("PSD path metadata key is too long.") }
      return try r.string(count == 0 ? 4 : count)
    }
    func string() throws -> String {
      let count = try r.u32()
      guard count <= 1024 else { throw CraftError.invalid("PSD path name is too long.") }
      var units: [UInt16] = []
      for _ in 0..<count { units.append(UInt16(try r.u16())) }
      if units.last == 0 { units.removeLast() }
      return String(decoding: units, as: UTF16.self)
    }
    guard try r.u32() == 16 else {
      throw CraftError.unsupported("Unsupported path metadata version.")
    }
    _ = try string()
    guard try key() == "pathsDataClass", try r.u32() == 1,
      try key() == "pathList", try r.string(4) == "VlLs"
    else {
      throw CraftError.unsupported("Unsupported PSD path metadata descriptor.")
    }
    let count = try r.u32()
    guard count <= 128 else { throw CraftError.invalid("Too many PSD saved paths.") }
    var names: [String] = []
    for _ in 0..<count {
      guard try r.string(4) == "Objc" else { throw CraftError.invalid("Invalid path name object.") }
      _ = try string()
      guard try key() == "pathInfoClass", try r.u32() == 1,
        try key() == "pathUnicodeName", try r.string(4) == "TEXT"
      else {
        throw CraftError.unsupported("Unsupported PSD path name descriptor.")
      }
      names.append(try string())
    }
    guard r.remaining == 0 else { throw CraftError.invalid("Trailing PSD path metadata.") }
    return names
  }
  static func writeNames(_ names: [String]) -> Data {
    var w = PSDWriter()
    func key(_ s: String) {
      w.n(s.utf8.count, 4)
      w.text(s)
    }
    func string(_ s: String) {
      let units = Array((s + "\0").utf16)
      w.n(units.count, 4)
      for u in units { w.n(Int(u), 2) }
    }
    w.n(16, 4)
    string("")
    key("pathsDataClass")
    w.n(1, 4)
    key("pathList")
    w.text("VlLs")
    w.n(names.count, 4)
    for name in names {
      w.text("Objc")
      string("")
      key("pathInfoClass")
      w.n(1, 4)
      key("pathUnicodeName")
      w.text("TEXT")
      string(name)
    }
    return w.data
  }
  static func read(_ data: Data, width: Int, height: Int) throws -> VectorPath {
    guard data.count % 26 == 0, data.count <= (VectorPath.maxKnots + 258) * 26 else {
      throw CraftError.invalid("Invalid PSD path record length.")
    }
    var r = PSDReader(data: data)
    var path = VectorPath()
    var expected = 0
    while r.remaining > 0 {
      let selector = try r.u16()
      var record = PSDReader(data: try r.bytes(24))
      switch selector {
      case 0, 3:
        guard expected == 0, path.components.count < 256 else {
          throw CraftError.invalid("Invalid PSD path knot count.")
        }
        expected = try record.u16()
        guard expected <= VectorPath.maxKnots - path.knotCount else {
          throw CraftError.invalid("PSD path exceeds the anchor limit.")
        }
        let operation: PathOperation
        switch try record.i16() {
        case -1: operation = .join
        case 0: operation = .exclude
        case 1: operation = .combine
        case 2: operation = .subtract
        case 3: operation = .intersect
        default: throw CraftError.unsupported("Unknown PSD path operation.")
        }
        path.components.append(PathComponent(closed: selector == 0, operation: operation))
      case 1, 2, 4, 5:
        guard expected > 0, let component = path.components.last,
          component.closed == (selector <= 2)
        else { throw CraftError.invalid("Unexpected PSD path knot.") }
        func point() throws -> PathPoint {
          let y = Double(try record.i32()) / 16_777_216 * Double(height)
          let x = Double(try record.i32()) / 16_777_216 * Double(width)
          return PathPoint(x, y)
        }
        let incoming = try point()
        let anchor = try point()
        let outgoing = try point()
        path.components[path.components.count - 1].knots.append(
          PathKnot(
            anchor,
            incoming: incoming, outgoing: outgoing, smooth: selector == 1 || selector == 4))
        expected -= 1
      case 6: break  // The reserved fill-rule payload is not a stored editable rule.
      case 7: break  // Clipboard bounds do not change the path geometry.
      case 8:
        let fill = try record.u16()
        guard fill <= 1 else { throw CraftError.invalid("Invalid PSD initial path fill.") }
        path.inverted = fill == 1
      default: throw CraftError.unsupported("Unknown PSD path selector.")
      }
    }
    guard expected == 0 else { throw CraftError.invalid("Truncated PSD path knots.") }
    try path.validate()
    if try VectorPathGeometry.fillRulesDiffer(path) { path.fillRule = .evenOdd }
    return path
  }
  static func write(_ path: VectorPath, width: Int, height: Int) throws -> Data {
    try path.validate()
    if path.fillRule == .nonZero, try VectorPathGeometry.fillRulesDiffer(path) {
      throw CraftError.unsupported(
        "PSD uses Even-Odd contour filling. Save the editable native file or merge path components to retain this Nonzero winding region.")
    }
    var w = PSDWriter()
    func record(_ selector: Int, _ data: Data) {
      w.n(selector, 2)
      w.data.append(data)
      w.data.append(contentsOf: repeatElement(0, count: 24 - data.count))
    }
    record(6, Data())
    var initial = PSDWriter()
    initial.n(path.inverted ? 1 : 0, 2)
    record(8, initial.data)
    for (i, component) in path.components.enumerated() {
      var length = PSDWriter()
      length.n(component.knots.count, 2)
      let operation: Int
      switch i == 0 && component.operation != .subtract ? .combine : component.operation {
      case .combine: operation = 1
      case .subtract: operation = 2
      case .intersect: operation = 3
      case .exclude: operation = 0
      case .join: operation = -1
      }
      length.n(operation, 2)
      length.n(1, 2)
      record(component.closed ? 0 : 3, length.data)
      for knot in component.knots {
        var data = PSDWriter()
        for p in [knot.incoming, knot.anchor, knot.outgoing] {
          for n in [p.y / Double(height), p.x / Double(width)] {
            let fixed = (n * 16_777_216).rounded()
            guard fixed >= Double(Int32.min), fixed <= Double(Int32.max) else {
              throw CraftError.unsupported("Path coordinate exceeds PSD's signed 8.24 range.")
            }
            data.n(Int(fixed), 4)
          }
        }
        record(component.closed ? (knot.smooth ? 1 : 2) : (knot.smooth ? 4 : 5), data.data)
      }
    }
    return w.data
  }
  static func readMask(_ data: Data, width: Int, height: Int) throws -> VectorMask {
    var r = PSDReader(data: data)
    guard try r.u32() == 3 else {
      throw CraftError.unsupported("Unsupported PSD vector mask version.")
    }
    let flags = try r.u32()
    guard flags & ~7 == 0 else {
      throw CraftError.unsupported("Unsupported PSD vector mask flags.")
    }
    let padding = r.remaining % 26
    guard padding <= 3 else { throw CraftError.invalid("Invalid PSD vector mask padding.") }
    let records = try r.bytes(r.remaining - padding)
    guard try r.bytes(padding).allSatisfy({ $0 == 0 }) else {
      throw CraftError.invalid("Invalid PSD vector mask padding.")
    }
    var path = try read(records, width: width, height: height)
    if !path.isEmpty {
      // Preserve component operations and order. Geometry evaluates a leading
      // subtraction as the complement of the first contour, including later
      // intersections; the vector-mask flag remains a separate final inversion.
      path.inverted = false
    } else {
      path.inverted.toggle()
    }
    if flags & 1 != 0 { path.inverted.toggle() }
    var mask = VectorMask(path: path)
    mask.linked = flags & 2 == 0
    mask.enabled = flags & 4 == 0
    return mask
  }
  static func writeMask(_ mask: VectorMask, width: Int, height: Int) throws -> Data {
    try mask.validate()
    var w = PSDWriter()
    var path = mask.path
    var flags = (mask.linked ? 0 : 2) | (mask.enabled ? 0 : 4)
    if path.isEmpty {
      path.inverted.toggle()
    } else if path.inverted {
      flags |= 1
      path.inverted = false
    }
    w.n(3, 4)
    w.n(flags, 4)
    w.data.append(try write(path, width: width, height: height))
    return w.data
  }
}
