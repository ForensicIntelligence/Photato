import Foundation
import PhotoCraftCore

/// Editable RGB shape descriptors and their Photoshop raster caches.
enum PSDLiveShape {
  private static let currentKeys = ["vscg", "vsms", "vstk", "vogk", "vowv", "sn2P"]
  private static let legacyKeys = ["SoCo", "vmsk", "vogk", "vowv", "sn2P"]
  private static let header = Data("SoCo".utf8)
  private static let originVersion = Data([0, 0, 0, 1])
  private static let alignments: [String: ShapeStroke.Alignment] = [
    "strokeStyleAlignCenter": .center, "strokeStyleAlignInside": .inside, "strokeStyleAlignOutside": .outside]
  private static let caps: [String: ShapeStroke.Cap] = [
    "strokeStyleButtCap": .butt, "strokeStyleRoundCap": .round, "strokeStyleSquareCap": .square]
  private static let joins: [String: ShapeStroke.Join] = [
    "strokeStyleMiterJoin": .miter, "strokeStyleRoundJoin": .round, "strokeStyleBevelJoin": .bevel]

  private static let radiiKeys = ["topLeft", "topRight", "bottomRight", "bottomLeft"]

  private struct Rectangle {
    var x: Double, y: Double, width: Double, height: Double
    var corners: [(Double, Double)] { [(x, y), (x + width, y), (x + width, y + height), (x, y + height)] }
  }

  private struct Primitive {
    let geometry: ShapeGeometry
    let rectangle: Rectangle
  }

  static func hasDefinition(_ tags: [String: Data]) -> Bool {
    tags["vscg"] != nil || (tags["SoCo"] != nil && tags["vmsk"] != nil && tags["vogk"] != nil)
  }

  static func read(_ tags: [String: Data], x: Int, y: Int, cache: Surface, document: CraftDocument) throws -> ShapeContent {
    guard document.colorMode == .rgb, document.depth != .f32 else {
      throw CraftError.unsupported("Editable Photoshop shapes require 8- or 16-bit RGB.")
    }
    let hasOrigination = tags["vogk"] != nil
    var primitives: [Primitive] = try tags["vogk"].map { data in
      guard data.starts(with: originVersion) else {
        throw CraftError.unsupported("Unrepresented Photoshop shape origination version.")
      }
      return try readGeometry(data)
    } ?? []
    let vector: Data
    let fill: ShapePaint
    let stroke: ShapeStroke
    if let generator = tags["vscg"] {
      guard generator.starts(with: header), let path = tags["vsms"], let appearance = tags["vstk"] else {
        throw CraftError.unsupported("Unrepresented Photoshop shape fill, contour or stroke.")
      }
      vector = path
      let (style, fillEnabled) = try readStyle(appearance)
      let color = try PSDSolidColor.read(Data(generator.dropFirst(4)))
      fill = fillEnabled ? .init(color: color) : .none
      stroke = style
    } else {
      guard primitives.count == 1, let generator = tags["SoCo"], let path = tags["vmsk"], tags["vsms"] == nil,
        tags["vstk"] == nil else {
        throw CraftError.unsupported("Legacy Photoshop live shapes require solid fill and a single vector contour.")
      }
      vector = path
      fill = try .init(color: PSDSolidColor.read(generator))
      stroke = ShapeStroke()
    }
    let mask = try PSDPaths.readMask(vector, width: document.width, height: document.height)
    if primitives.count > 1 {
      let links = try PSDPaths.maskOriginationIndices(vector)
      guard links.sorted() == Array(primitives.indices) else {
        throw CraftError.unsupported("The Photoshop shape contours do not reference distinct live origins.")
      }
      primitives = links.map { primitives[$0] }
    }
    guard mask.enabled, mask.linked, !mask.path.inverted else {
      throw CraftError.unsupported("The Photoshop shape requires an enabled, linked contour without mask inversion.")
    }
    if hasOrigination {
      guard mask.path.components.count == primitives.count,
            try zip(mask.path.components, primitives).allSatisfy({ outline, primitive in
              try matches(outline, primitive: primitive, tolerance: tolerance(document))
            }) else {
        throw CraftError.unsupported("The linked Photoshop shape path does not match its axis-aligned live geometry.")
      }
    }
    var definition = ShapeDefinition(geometry: primitives.first?.geometry ?? .init(), fill: fill, stroke: stroke)
    definition.fillRule = mask.path.fillRule
    definition = try localize(definition, primitives: primitives, path: mask.path, x: x, y: y, document: document)
    var shape = try ShapeContent(definition: definition)
    shape.width = cache.width; shape.height = cache.height
    shape.importedAppearance = .init(definition: definition, pixels: cache, vectorRecord: vector)
    return shape
  }

  private static func readGeometry(_ origination: Data) throws -> [Primitive] {
    let origin = try PSDDescriptor.read(Data(origination.dropFirst(4)), padding: true)
    guard case .list(let values)? = origin["keyDescriptorList"], (1...256).contains(values.count) else {
      throw CraftError.unsupported("Unrepresented Photoshop shape origination.")
    }
    var records = try values.map { value in
      guard case .object(let descriptor) = value else {
        throw CraftError.unsupported("Unrepresented Photoshop shape origination record.")
      }
      return descriptor
    }
    if records.count > 1, records.contains(where: { $0["keyOriginIndex"] != nil }) {
      let indices = records.compactMap { $0["keyOriginIndex"]?.number }
      guard indices.sorted() == records.indices.map(Double.init) else {
        throw CraftError.unsupported("Unrepresented Photoshop shape origination indices.")
      }
      records = zip(indices, records).sorted { $0.0 < $1.0 }.map { $0.1 }
    }
    return try records.map(readPrimitive)
  }

  private static func readPrimitive(_ record: PSDDescriptor) throws -> Primitive {
    guard let type = record["keyOriginType"]?.number,
      case .object(let box)? = record["keyOriginShapeBBox"],
      let left = number(box["Left"], unit: "#Pxl"), let top = number(box["Top "], unit: "#Pxl"),
      let right = number(box["Rght"], unit: "#Pxl"), let bottom = number(box["Btom"], unit: "#Pxl") else {
      throw CraftError.unsupported("Unrepresented Photoshop shape origination.")
    }
    // Photoshop has already applied its stored Trnf to the document-space bounds
    // and contour. Verify the contour against those bounds before using them.
    let rectangle = Rectangle(x: left, y: top, width: right - left, height: bottom - top)
    var geometry = ShapeGeometry(kind: type == 5 ? .ellipse : .rectangle,
      width: rectangle.width, height: rectangle.height)
    switch type {
    case 1, 5: break
    case 2:
      guard case .object(let radii)? = record["keyOriginRRectRadii"], radii.classID.text == "radii",
        radii["unitValueQuadVersion"]?.number == 1 else {
        throw CraftError.unsupported("Unrepresented Photoshop rounded rectangle radii.")
      }
      geometry.radii = try radiiKeys.map { key in
        guard let radius = number(radii[key], unit: "#Pxl") else {
          throw CraftError.unsupported("Unrepresented Photoshop rounded rectangle radius.")
        }
        return radius
      }
    default:
      throw CraftError.unsupported("Unrepresented Photoshop live shape type.")
    }
    return Primitive(geometry: geometry, rectangle: rectangle)
  }

  private static func localized(_ primitives: [Primitive], path: VectorPath,
                                transform: Transform2D) throws -> [ShapeComponent] {
    if primitives.isEmpty { return try ShapeDefinition.editablePathComponents(path.transformed(transform)) }
    return zip(primitives, path.components).map { primitive, outline in
      let placement = transform * .translation(primitive.rectangle.x, primitive.rectangle.y)
      var component = ShapeComponent(geometry: primitive.geometry, transform: placement, operation: outline.operation)
      var contour = outline
      contour.operation = .combine
      component.pathOverride = VectorPath(components: [contour], fillRule: path.fillRule).transformed(transform)
      component.pathReferenceTransform = placement
      return component
    }
  }

  private static func localize(_ definition: ShapeDefinition, primitives: [Primitive], path: VectorPath,
                               x: Int, y: Int, document: CraftDocument) throws -> ShapeDefinition {
    var definition = definition
    let transform = Transform2D.translation(Double(x), Double(y))
    definition.components = try localized(primitives, path: path, transform: transform.inverted())
    if path.components.first?.operation == .subtract {
      definition.exteriorFrame = try ShapeDefinition.exteriorFrame(
        canvas: .init(x: 0, y: 0, width: document.width, height: document.height), transform: transform)
    }
    return definition
  }

  private static func readStyle(_ appearance: Data) throws -> (ShapeStroke, Bool) {
    let style = try PSDDescriptor.read(appearance, padding: true)
    guard let fillEnabled = flag(style["fillEnabled"]), let strokeEnabled = flag(style["strokeEnabled"]),
      style.classID.text == "strokeStyle", style["strokeStyleVersion"]?.number == 2,
      case .list(let dashValues)? = style["strokeStyleLineDashSet"], dashValues.count <= 32,
      let alignment = alignments[choice(style["strokeStyleLineAlignment"]) ?? ""],
      let cap = caps[choice(style["strokeStyleLineCapType"]) ?? ""],
      let join = joins[choice(style["strokeStyleLineJoinType"]) ?? ""],
      let width = number(style["strokeStyleLineWidth"], unit: "#Pxl"),
      let miter = style["strokeStyleMiterLimit"]?.number,
      let opacity = number(style["strokeStyleOpacity"], unit: "#Prc"),
      ["Nrml", "normal"].contains(choice(style["strokeStyleBlendMode"]) ?? ""),
      case .object(let paint)? = style["strokeStyleContent"] else {
      throw CraftError.unsupported("This Photoshop shape uses unqualified stroke settings.")
    }
    guard (0...100).contains(opacity), flag(style["strokeStyleScaleLock"]) != true,
      flag(style["strokeStyleStrokeAdjust"]) != true else {
      throw CraftError.unsupported("This Photoshop stroke uses unqualified scaling, adjustment or opacity.")
    }
    let dash = try dashValues.map { value in
      guard let length = number(value, unit: "#Nne") else {
        throw CraftError.unsupported("The Photoshop dash length must be relative to stroke width.")
      }
      return length
    }
    guard dash.isEmpty || number(style["strokeStyleLineDashOffset"], unit: "#Pnt") == 0 else {
      throw CraftError.unsupported("The Photoshop dash phase is unsupported.")
    }
    let color = try PSDSolidColor.read(paint.encoded())
    var stroke = ShapeStroke()
    stroke.width = width; stroke.alignment = alignment; stroke.cap = cap; stroke.join = join; stroke.miterLimit = miter
    stroke.paint = strokeEnabled ? .init(color: color) : .none
    stroke.dash = dash
    if !dash.isEmpty { stroke.widthRelativeDashes = true }
    if opacity != 100 { stroke.opacity = Float(opacity / 100) }
    return (stroke, fillEnabled)
  }

  static func supported(_ layer: Layer, in document: CraftDocument) -> Bool {
    (try? exportGeometry(layer, document: document)) != nil
  }

  /// PSD uses integer cache bounds. Project a fractional layer placement using the
  /// compositor's sampler while keeping the live path in its original document position.
  static func prepared(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    guard layer.affine != nil else { return layer }
    let (original, primitives, path) = try exportGeometry(layer, document: document)
    let pixels = try Renderer.layerSurface(layer, in: document)
    let placement = layer.coordinateTransform
    let bounds = try placement.bounds(width: pixels.width, height: pixels.height)
    guard bounds.width <= 32768, bounds.height <= 32768, bounds.width * bounds.height <= 8_388_608 else {
      throw CraftError.unsupported("The projected Photoshop shape cache exceeds the editable shape budget.")
    }
    let cache = try RasterGeometry.render(pixels, transform: placement, bounds: bounds, method: .bilinear)
    let local = Transform2D.translation(-Double(bounds.x), -Double(bounds.y))
    let definition = try localize(original, primitives: primitives, path: path,
                                  x: bounds.x, y: bounds.y, document: document)
    var shape = try ShapeContent(definition: definition)
    shape.width = cache.width
    shape.height = cache.height
    shape.importedAppearance = .init(definition: definition, pixels: cache)
    var result = layer
    result.content = .shape(shape)
    result.x = bounds.x
    result.y = bounds.y
    result.affine = nil
    if layer.mask != nil {
      var properties = layer.effectiveMaskProperties
      properties.transform = local * layer.maskCoordinateTransform
      result.maskProperties = properties
    }
    return result
  }

  private static func exportGeometry(_ layer: Layer, document: CraftDocument) throws
    -> (ShapeDefinition, [Primitive], VectorPath) {
    guard document.colorMode == .rgb, document.depth != .f32, let shape = layer.shape,
      layer.vectorMask == nil, layer.smartObject == nil else { throw unsupported }
    if let affine = layer.affine {
      guard affine.a == 1, affine.b == 0, affine.c == 0, affine.d == 1 else { throw unsupported }
    }
    let definition = shape.editableDefinition
    guard let first = definition.components.first, definition.inverted != true,
      definition.stroke.dash.isEmpty || (definition.stroke.widthRelativeDashes == true && definition.stroke.phase == 0),
      definition.stroke.pathContours != true,
      [.none, .solid].contains(definition.fill.kind), [.none, .solid].contains(definition.stroke.paint.kind),
      definition.fill.color.a == 1, definition.stroke.paint.color.a == 1, let path = try layer.shapePath(),
      !path.inverted else {
      throw unsupported
    }
    let leadingSubtract = path.components.first?.operation == .subtract
    if leadingSubtract {
      guard let frame = definition.exteriorFrame else { throw unsupported }
      if try VectorPathGeometry.filledRegion(path).inverted {
        let mapped = try layer.shapeTransform() * frame
        guard mapped.a == Double(document.width), mapped.d == Double(document.height),
              mapped.b == 0, mapped.c == 0, abs(mapped.tx) < 1e-9, abs(mapped.ty) < 1e-9 else { throw unsupported }
      }
    } else {
      guard first.operation == .combine || first.operation == .join else { throw unsupported }
    }
    if definition.components.count == 1, first.geometry.kind == .custom {
      return (definition, [], path)
    }
    if leadingSubtract, definition.components.allSatisfy({ $0.geometry.kind == .custom }) {
      return (definition, [], path)
    }
    guard path.components.count == definition.components.count else { throw unsupported }
    let origin = try layer.shapeTransform()
    let primitives = try zip(definition.components, path.components).map { part, outline in
      let transform = origin * part.transform
      guard [.rectangle, .ellipse].contains(part.geometry.kind),
            transform.a == 1, transform.b == 0, transform.c == 0, transform.d == 1 else { throw unsupported }
      let border = Rectangle(x: transform.tx, y: transform.ty, width: part.geometry.width, height: part.geometry.height)
      let primitive = Primitive(geometry: part.geometry, rectangle: border)
      guard try matches(outline, primitive: primitive, tolerance: tolerance(document)) else { throw unsupported }
      return primitive
    }
    return (definition, primitives, path)
  }

  static func write(_ layer: Layer, document: CraftDocument) throws -> [(String, Data)] {
    let (definition, primitives, path) = try exportGeometry(layer, document: document)
    if let original = layer.shape?.importedAppearance, original.definition == definition,
      let raw = layer.sourceTags, let vector = original.vectorRecord,
      let parsed = try? PSDPaths.readMask(vector, width: document.width, height: document.height), parsed.path == path {
      if raw["vscg"] != nil, raw["vsms"] == vector {
        return currentKeys.compactMap { key in raw[key].map { (key, $0) } }
      }
      if raw["SoCo"] != nil, raw["vogk"] != nil, raw["vmsk"] == vector {
        return legacyKeys.compactMap { key in raw[key].map { (key, $0) } }
      }
    }
    let stroke = definition.stroke
    let fill = definition.fill.kind == .solid ? definition.fill.color : .black
    let paint = try PSDDescriptor.read(PSDSolidColor.write(stroke.paint.kind == .solid ? stroke.paint.color : .black))
    let strokeStyle = PSDDescriptor("strokeStyle", items: [
      .init("strokeStyleVersion", .integer(2)), .init("strokeEnabled", .boolean(stroke.paint.kind != .none)),
      .init("fillEnabled", .boolean(definition.fill.kind != .none)),
      .init("strokeStyleLineWidth", unit("#Pxl", stroke.width)), .init("strokeStyleLineDashOffset", unit("#Pnt", 0)),
      .init("strokeStyleMiterLimit", .number(stroke.miterLimit)),
      .init("strokeStyleLineCapType", enumeration("strokeStyleLineCapType", caps.first { $0.value == stroke.cap }!.key)),
      .init("strokeStyleLineJoinType", enumeration("strokeStyleLineJoinType", joins.first { $0.value == stroke.join }!.key)),
      .init("strokeStyleLineAlignment", enumeration("strokeStyleLineAlignment", alignments.first { $0.value == stroke.alignment }!.key)),
      .init("strokeStyleScaleLock", .boolean(false)), .init("strokeStyleStrokeAdjust", .boolean(false)),
      .init("strokeStyleLineDashSet", .list(stroke.dash.map { unit("#Nne", $0) })),
      .init("strokeStyleBlendMode", enumeration("BlnM", "Nrml")),
      .init("strokeStyleOpacity", unit("#Prc", Double(stroke.opacity ?? 1) * 100)),
      .init("strokeStyleContent", .object(PSDDescriptor("solidColorLayer", items: paint.items))),
      .init("strokeStyleResolution", .number(document.pixelsPerInch))])
    let records = primitives.enumerated().map {
      PSDValue.object(origination($0.element, index: $0.offset, resolution: document.pixelsPerInch))
    }
    let vector = try [("vscg", header + PSDSolidColor.write(fill)),
      ("vsms", PSDPaths.writeMask(VectorMask(path: path), width: document.width, height: document.height,
                                 linkShapeOrigins: !records.isEmpty))]
    if records.isEmpty { return try vector + [("vstk", strokeStyle.encoded())] }
    let origin = PSDDescriptor("null", items: [.init("keyDescriptorList", .list(records))])
    return try vector + [("vowv", Data([0,0,0,2])), ("vogk", originVersion + origin.encoded()),
                         ("vstk", strokeStyle.encoded()), ("sn2P", originVersion)]
  }

  private static func origination(_ primitive: Primitive, index: Int, resolution: Double) -> PSDDescriptor {
    let rectangle = primitive.rectangle
    let bounds = PSDDescriptor("unitRect", items: [
      .init("unitValueQuadVersion", .integer(1)), .init("Top ", unit("#Pxl", rectangle.y)),
      .init("Left", unit("#Pxl", rectangle.x)), .init("Btom", unit("#Pxl", rectangle.y + rectangle.height)),
      .init("Rght", unit("#Pxl", rectangle.x + rectangle.width))])
    let geometry = primitive.geometry
    let type: Int32 = geometry.kind == .ellipse ? 5 : (geometry.radii.contains { $0 > 0 } ? 2 : 1)
    var live: [PSDDescriptor.Item] = [
      .init("keyOriginType", .integer(type)), .init("keyOriginResolution", .number(resolution))]
    if type == 2 {
      let values = zip(radiiKeys, geometry.radii).map { PSDDescriptor.Item($0.0, unit("#Pxl", $0.1)) }
      let radii = PSDDescriptor("radii", items: [.init("unitValueQuadVersion", .integer(1))] + values)
      live.append(.init("keyOriginRRectRadii", .object(radii)))
    }
    live.append(.init("keyOriginShapeBBox", .object(bounds)))
    if type == 1 {
      let corners = zip(["rectangleCornerA", "rectangleCornerB", "rectangleCornerC", "rectangleCornerD"], rectangle.corners)
        .map { name, point in PSDDescriptor.Item(name, .object(PSDDescriptor("Pnt ", items: [
          .init("Hrzn", .number(point.0)), .init("Vrtc", .number(point.1))]))) }
      live.append(.init("keyOriginBoxCorners", .object(PSDDescriptor("null", items: corners))))
      let transform = PSDDescriptor("Trnf", items: zip(["xx", "xy", "yx", "yy", "tx", "ty"], [1.0, 0, 0, 1, 0, 0])
        .map { PSDDescriptor.Item($0.0, .number($0.1)) })
      live.append(.init("Trnf", .object(transform)))
    }
    live.append(.init("keyOriginIndex", .integer(Int32(index))))
    return PSDDescriptor("null", items: live)
  }

  private static let unsupported = CraftError.unsupported("PSD editable shape export currently supports axis-aligned rectangles, ellipses and finite outlines with solid paint and zero-phase, width-relative dashes. Save other shapes as Photato.")
  private static func tolerance(_ document: CraftDocument) -> Double { Double(max(document.width, document.height)) / 16_777_216 + 1e-8 }

  private static func matches(_ component: PathComponent, primitive: Primitive, tolerance: Double) throws -> Bool {
    guard component.closed, (4...8).contains(component.knots.count) else { return false }
    let rectangle = primitive.rectangle
    let expected = try primitive.geometry.path().transformed(.translation(rectangle.x, rectangle.y))
    // At maximum corner radius a straight run can collapse to one point. Photoshop may omit it.
    func segments(_ knots: [PathKnot]) -> [[PathPoint]] {
      knots.indices.compactMap { index in
        let start = knots[index], end = knots[(index + 1) % knots.count]
        let points = [start.anchor, start.outgoing, end.incoming, end.anchor]
        return points.allSatisfy { $0 == start.anchor } ? nil : points
      }
    }
    let reference = segments(expected.components[0].knots), observed = segments(component.knots)
    guard !reference.isEmpty, reference.count == observed.count else { return false }
    func sameOrder(_ candidate: [[PathPoint]]) -> Bool {
      candidate.indices.contains { start in
        reference.indices.allSatisfy { index in
          zip(reference[index], candidate[(start + index) % candidate.count]).allSatisfy { a, b in
            abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
          }
        }
      }
    }
    return sameOrder(observed) || sameOrder(observed.reversed().map { Array($0.reversed()) })
  }
  private static func flag(_ value: PSDValue?) -> Bool? { if case .boolean(let flag)? = value { return flag }; return nil }
  private static func choice(_ value: PSDValue?) -> String? { if case .enumerated(_, let id)? = value { return id.text }; return nil }
  private static func number(_ value: PSDValue?, unit: String) -> Double? {
    guard case .unit(let key, let bits)? = value, key == Data(unit.utf8) else { return nil }
    let result = Double(bitPattern: bits)
    return result.isFinite ? result : nil
  }
  private static func unit(_ name: String, _ value: Double) -> PSDValue { .unit(Data(name.utf8), value.bitPattern) }
  private static func enumeration(_ key: String, _ value: String) -> PSDValue { .enumerated(PSDID(key), PSDID(value)) }
}
