import CoreFoundation
import Foundation
import PhotoCraftCore

/// Published create-composite geometry in document coordinates. The engine
/// receives a regular layer transform, so the source and attached masks stay editable.
struct AdobeSmartObjectTransform: Sendable {
  private typealias Object = AdobeActionsRequest.Object

  private let offset: (x: Int?, y: Int?)
  private let dimension: (width: Int?, height: Int?)
  private let points: Bool
  private let angle: Double?
  private let skew: Transform2D?
  private let anchor: (x: Double, y: Double)
  private let horizontalAlignment: Double?
  private let verticalAlignment: Double?

  init(_ raw: Any, path: String) throws {
    let object = try Object(raw, at: path, allowed: [
      "offset", "dimension", "angle", "skew", "anchor", "horizontalAlign", "verticalAlign",
    ])
    let signed = Int(Int32.min)...Int(Int32.max)
    if object.fields["offset"] != nil {
      let value = try object.object("offset", allowed: ["horizontal", "vertical"])
      offset = (try Self.optionalInteger(value, "horizontal", signed),
                try Self.optionalInteger(value, "vertical", signed))
    } else {
      offset = (nil, nil)
    }
    if object.fields["dimension"] != nil {
      let value = try object.object("dimension", allowed: ["width", "height", "unit"])
      dimension = (try Self.optionalInteger(value, "width", 1...32_000),
                   try Self.optionalInteger(value, "height", 1...32_000))
      let unit = try value.fields["unit"].map { _ in try value.string("unit") } ?? "pixels_unit"
      guard unit == "pixels_unit" || unit == "points_unit" else {
        throw AdobeAPIError.invalid("\(value.path).unit must be pixels_unit or points_unit.")
      }
      points = unit == "points_unit"
    } else {
      dimension = (nil, nil)
      points = false
    }
    angle = try object.fields["angle"].map { _ in try Self.number(object, "angle") }
    if object.fields["skew"] != nil {
      let value = try object.object("skew", allowed: ["horizontal", "vertical"])
      let horizontal = Double(try value.integer("horizontal", range: signed)).remainder(dividingBy: 180)
      let vertical = Double(try value.integer("vertical", range: signed)).remainder(dividingBy: 180)
      guard abs(horizontal) != 90, abs(vertical) != 90 else {
        throw AdobeAPIError.invalid("\(value.path) requires finite shear factors.")
      }
      let shear = Transform2D(b: tan(vertical * .pi / 180), c: tan(horizontal * .pi / 180))
      guard (try? shear.validated()) != nil else {
        throw AdobeAPIError.invalid("\(value.path) collapses the layer.")
      }
      skew = shear
    } else {
      skew = nil
    }
    if object.fields["anchor"] != nil {
      let value = try object.object("anchor", allowed: ["horizontal", "vertical"])
      anchor = (try Self.number(value, "horizontal"), try Self.number(value, "vertical"))
    } else {
      anchor = (0.5, 0.5)
    }
    horizontalAlignment = try Self.alignment(object, "horizontalAlign", start: "left", end: "right")
    verticalAlignment = try Self.alignment(object, "verticalAlign", start: "top", end: "bottom")
  }

  func target(from current: Transform2D, source: SmartObject, in document: CraftDocument, adding: Bool) throws -> Transform2D {
    try current.validated()
    let width = Double(source.width), height = Double(source.height)
    let unitScale = points ? document.pixelsPerInch / 72 : 1
    let scaleX = hypot(current.a, current.b)
    let scaleY = (current.a * current.d - current.b * current.c) / scaleX
    let factorX = dimension.width.map { Double($0) * unitScale / (width * scaleX) } ?? 1
    let factorY = dimension.height.map { Double($0) * unitScale / (height * abs(scaleY)) } ?? 1
    let heading = atan2(current.b, current.a) * 180 / .pi

    var target: Transform2D
    if let skew {
      let rotation = (angle ?? heading).remainder(dividingBy: 360)
      target = .rotation(rotation) * skew * .scale(scaleX * factorX, scaleY * factorY)
    } else {
      let basis = Transform2D(a: current.a, b: current.b, c: current.c, d: current.d)
      let rotation = angle.map { $0.remainder(dividingBy: 360) - heading } ?? 0
      target = .rotation(rotation) * basis * .scale(factorX, factorY)
    }
    let pivot = (x: anchor.x * width, y: anchor.y * height)
    let targetPivot = target.point(pivot.x, pivot.y)
    if adding {
      target.tx = Double(offset.x ?? 0) + pivot.x * scaleX * factorX - targetPivot.x
      target.ty = Double(offset.y ?? 0) + pivot.y * abs(scaleY) * factorY - targetPivot.y
    } else {
      let existingX = current.a * pivot.x + current.c * pivot.y
      let existingY = current.b * pivot.x + current.d * pivot.y
      target.tx = offset.x.map(Double.init) ?? (current.tx + (existingX - targetPivot.x))
      target.ty = offset.y.map(Double.init) ?? (current.ty + (existingY - targetPivot.y))
    }
    if horizontalAlignment != nil || verticalAlignment != nil {
      let origin = target.point(0, 0), right = target.point(width, 0)
      let bottom = target.point(0, height), opposite = target.point(width, height)
      if let align = horizontalAlignment, offset.x == nil {
        let minimum = min(origin.x, right.x, bottom.x, opposite.x)
        let maximum = max(origin.x, right.x, bottom.x, opposite.x)
        target.tx += (Double(document.width) - (maximum - minimum)) * align - minimum
      }
      if let align = verticalAlignment, offset.y == nil {
        let minimum = min(origin.y, right.y, bottom.y, opposite.y)
        let maximum = max(origin.y, right.y, bottom.y, opposite.y)
        target.ty += (Double(document.height) - (maximum - minimum)) * align - minimum
      }
    }
    try target.validated()
    return target
  }

  private static func optionalInteger(_ object: Object, _ key: String, _ range: ClosedRange<Int>) throws -> Int? {
    try object.fields[key].map { _ in try object.integer(key, range: range) }
  }

  private static func number(_ object: Object, _ key: String) throws -> Double {
    guard let value = object.fields[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
          value.doubleValue.isFinite else {
      throw AdobeAPIError.invalid("\(object.path).\(key) must be a finite number.")
    }
    return value.doubleValue
  }

  private static func alignment(_ object: Object, _ key: String, start: String, end: String) throws -> Double? {
    guard object.fields[key] != nil else { return nil }
    switch try object.string(key) {
    case start: return 0
    case "center": return 0.5
    case end: return 1
    default: throw AdobeAPIError.invalid("Invalid alignment for \(object.path).\(key).")
    }
  }
}
