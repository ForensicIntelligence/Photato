import Foundation
import PhotoCraftCore

/// The mesh and placed quadrilateral use different coordinate systems.
enum PSDWarp {
  struct Frame: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static func source(width: Int, height: Int) -> Self {
      .init(x: 0, y: 0, width: Double(width), height: Double(height))
    }

    /// A custom placement quad spans the source and the control hull together.
    /// Points pulled outside this frame expand it without stretching the mesh.
    static func placement(_ warp: WarpDefinition?, width: Int, height: Int) -> Self {
      let frame = source(width: width, height: height)
      guard let mesh = warp?.mesh else { return frame }
      var left = 0.0, top = 0.0, right = frame.width, bottom = frame.height
      if let bounds = warp?.sourceBounds {
        left = min(left, bounds.x); top = min(top, bounds.y)
        right = max(right, bounds.x + bounds.width); bottom = max(bottom, bounds.y + bounds.height)
      }
      for point in mesh.points {
        left = min(left, point.x); top = min(top, point.y)
        right = max(right, point.x); bottom = max(bottom, point.y)
      }
      return .init(x: left, y: top, width: right - left, height: bottom - top)
    }

    var corners: [PathPoint] {
      [.init(x, y), .init(x + width, y), .init(x + width, y + height), .init(x, y + height)]
    }
  }

  static func decode(_ placed: PSDDescriptor, width: Int, height: Int) throws -> WarpDefinition? {
    let isQuilt = placed["quiltWarp"] != nil
    guard let value = placed["quiltWarp"] ?? placed["warp"] else { return nil }
    guard case .object(let descriptor) = value,
          case .enumerated(_, let styleID) = descriptor["warpStyle"] else {
      throw CraftError.invalid("Invalid Smart Object Warp descriptor.")
    }
    if styleID.text == "warpNone", !isQuilt { return nil }

    let styleName = styleID.text == "warpFisheye" ? "warpFishEye" : styleID.text
    guard let style = WarpStyle.allCases.first(where: { identifier($0) == styleName }),
          !isQuilt || style == .custom else {
      throw CraftError.unsupported("Unsupported Smart Object Warp style.")
    }
    guard case .object(let bounds) = descriptor["bounds"],
          let x = pixels(bounds["Left"]), let y = pixels(bounds["Top "]),
          let right = pixels(bounds["Rght"]), let bottom = pixels(bounds["Btom"]),
          descriptor["uOrder"]?.number == 4, descriptor["vOrder"]?.number == 4 else {
      throw CraftError.unsupported("Smart Object Warp requires a rectangular cubic source frame.")
    }
    let frame = WarpSourceBounds(x: x, y: y, width: right - x, height: bottom - y)
    try frame.validate()

    var warp = WarpDefinition()
    warp.style = style
    if x != 0 || y != 0 || frame.width != Double(width) || frame.height != Double(height) {
      warp.sourceBounds = frame
    }
    func amount(_ key: String) throws -> Double {
      guard let value = descriptor[key] else { return 0 }
      guard let number = value.number else { throw CraftError.invalid("Invalid Smart Object Warp amount.") }
      return number
    }
    warp.bend = try amount("warpValue")
    warp.horizontalDistortion = try amount("warpPerspective")
    warp.verticalDistortion = try amount("warpPerspectiveOther")
    if let orientation = descriptor["warpRotate"] {
      guard case .enumerated(_, let direction) = orientation,
            ["Hrzn", "Vrtc", "horizontal", "vertical"].contains(direction.text) else {
        throw CraftError.invalid("Invalid Smart Object Warp orientation.")
      }
      warp.vertical = direction.text == "Vrtc" || direction.text == "vertical"
    }
    if style == .custom {
      warp.mesh = try mesh(descriptor, frame: frame, quilt: isQuilt)
    } else if descriptor["customEnvelopeWarp"] != nil {
      throw CraftError.unsupported("A preset with a separate Warp mesh requires native handling.")
    }
    try warp.validate()
    return warp
  }

  private static func mesh(_ descriptor: PSDDescriptor, frame: WarpSourceBounds, quilt: Bool) throws -> WarpMesh {
    guard case .object(let envelope) = descriptor["customEnvelopeWarp"],
          case .objectArray(let count, let points) = envelope["meshPoints"],
          points.classID.text == "rationalPoint" else {
      throw CraftError.invalid("Missing Smart Object Warp control points.")
    }
    let us = try quilt ? slices("quiltSliceX", in: envelope, origin: frame.x, length: frame.width) : [0, 1]
    let vs = try quilt ? slices("quiltSliceY", in: envelope, origin: frame.y, length: frame.height) : [0, 1]
    let columns = 3 * (us.count - 1) + 1, rows = 3 * (vs.count - 1) + 1
    let expected = rows * columns
    guard (!quilt || (descriptor["deformNumCols"]?.number == Double(columns) &&
                      descriptor["deformNumRows"]?.number == Double(rows))),
          count == expected,
          let xs = pixelList(points["Hrzn"], count: expected),
          let ys = pixelList(points["Vrtc"], count: expected) else {
      throw CraftError.invalid("Smart Object Warp control point dimensions disagree.")
    }
    return .init(us: us, vs: vs, points: zip(xs, ys).map { PathPoint($0, $1) })
  }

  private static func slices(_ key: String, in envelope: PSDDescriptor, origin: Double, length: Double) throws -> [Double] {
    guard case .objectArray(let count, let values) = envelope[key], (2...17).contains(count),
          let positions = pixelList(values[key], count: Int(count)),
          abs(positions[0] - origin) <= 1, abs(positions[positions.count - 1] - (origin + length)) <= 1,
          zip(positions, positions.dropFirst()).allSatisfy({ $0 < $1 }) else {
      throw CraftError.invalid("Invalid split Warp slice coordinates.")
    }
    // Photoshop pads the outer slice sentinels by a fraction of a pixel.
    // Interior positions are source pixels and retain their nonuniform spacing.
    return [0] + positions.dropFirst().dropLast().map { ($0 - origin) / length } + [1]
  }

  private static func pixels(_ value: PSDValue?) -> Double? {
    if case .unit(let unit, let bits) = value, unit == Data("#Pxl".utf8) { return Double(bitPattern: bits) }
    return value?.number
  }

  private static func pixelList(_ value: PSDValue?, count: Int) -> [Double]? {
    guard case .units(let unit, let bits) = value, unit == Data("#Pxl".utf8), bits.count == count else { return nil }
    let values = bits.map(Double.init(bitPattern:))
    return values.allSatisfy(\.isFinite) ? values : nil
  }

  private static func identifier(_ style: WarpStyle) -> String {
    if style == .fisheye { return "warpFishEye" }
    return "warp" + style.rawValue.prefix(1).uppercased() + style.rawValue.dropFirst()
  }

  static func encoded(_ warp: WarpDefinition?, width: Int, height: Int) throws -> [PSDDescriptor.Item] {
    let value = warp ?? WarpDefinition()
    try value.validate()
    let bounds = value.sourceBounds ?? WarpSourceBounds(x: 0, y: 0, width: Double(width), height: Double(height))
    func descriptor(_ value: WarpDefinition, key: String) -> PSDDescriptor {
      let rect = PSDDescriptor("classFloatRect", items: [
        .init("Top ", .number(bounds.y)), .init("Left", .number(bounds.x)),
        .init("Btom", .number(bounds.y + bounds.height)), .init("Rght", .number(bounds.x + bounds.width)),
      ])
      return .init(key, items: [
        .init("warpStyle", .enumerated(PSDID("warpStyle"), PSDID(identifier(value.style)))),
        .init("warpValue", .number(value.bend)), .init("warpPerspective", .number(value.horizontalDistortion)),
        .init("warpPerspectiveOther", .number(value.verticalDistortion)),
        .init("warpRotate", .enumerated(PSDID("Ornt"), PSDID(value.vertical ? "Vrtc" : "Hrzn"))),
        .init("bounds", .object(rect)), .init("uOrder", .integer(4)), .init("vOrder", .integer(4)),
      ])
    }
    guard let mesh = value.mesh else { return [.init("warp", .object(descriptor(value, key: "warp")))] }
    let quilt = mesh.us.count > 2 || mesh.vs.count > 2
    let key = quilt ? "quiltWarp" : "warp"
    var record = descriptor(value, key: key)
    func units(_ values: [Double]) -> PSDValue { .units(Data("#Pxl".utf8), values.map(\.bitPattern)) }
    func slice(_ key: String, knots: [Double], start: Double, length: Double) -> PSDDescriptor.Item {
      let positions = [start - 0.6] + knots.dropFirst().dropLast().map { start + $0 * length } + [start + length + 0.6]
      return .init(key, .objectArray(UInt32(positions.count), .init("UntF", items: [.init(key, units(positions))])))
    }
    var envelope = PSDDescriptor("customEnvelopeWarp")
    if quilt {
      record.items += [.init("deformNumRows", .integer(Int32(mesh.rows))), .init("deformNumCols", .integer(Int32(mesh.columns)))]
      envelope.items += [
        slice("quiltSliceX", knots: mesh.us, start: bounds.x, length: bounds.width),
        slice("quiltSliceY", knots: mesh.vs, start: bounds.y, length: bounds.height),
      ]
    }
    let points = PSDDescriptor("rationalPoint", items: [
      .init("Hrzn", units(mesh.points.map(\.x))), .init("Vrtc", units(mesh.points.map(\.y))),
    ])
    envelope.items.append(.init("meshPoints", .objectArray(UInt32(mesh.points.count), points)))
    record.items.append(.init("customEnvelopeWarp", .object(envelope)))
    if quilt {
      return [.init(key, .object(record)), .init("warp", .object(descriptor(WarpDefinition(), key: "warp")))]
    }
    return [.init(key, .object(record))]
  }
}

extension PSDCodec {
  /// The Photoshop manifest reports the same placed quad as the saved document.
  public static func warpedSmartObjectPlacementCorners(_ layer: Layer) throws -> [PathPoint]? {
    guard let source = layer.smartObject,
          try layer.warp != nil || layer.linkedSmartObjectPreview()?.warp != nil else { return nil }
    let (_, placed) = try PSDSmartObjects.encodedQuads(layer, source: source)
    guard case .list(let values) = placed else { return nil }
    let words = values.compactMap(\.number)
    guard words.count == 8 else { throw CraftError.invalid("Invalid Smart Object Warp placement quad.") }
    return stride(from: 0, to: 8, by: 2).map { PathPoint(words[$0], words[$0 + 1]) }
  }
}
