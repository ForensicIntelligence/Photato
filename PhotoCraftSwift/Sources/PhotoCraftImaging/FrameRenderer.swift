import AppKit
import CoreGraphics
import PhotoCraftCore

public enum FrameRenderer {
  static func coverage(_ path: CGPath, region: IntRect) throws -> SelectionMask {
    guard let context = CGContext(data: nil, width: region.width, height: region.height, bitsPerComponent: 8, bytesPerRow: region.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = context.data else { throw CraftError.invalid("Could not rasterize the frame.") }
    context.translateBy(x: 0, y: Double(region.height)); context.scaleBy(x: 1, y: -1)
    context.translateBy(x: -Double(region.x), y: -Double(region.y)); context.setShouldAntialias(true)
    context.setFillColor(gray: 1, alpha: 1); context.addPath(path); context.fillPath()
    return try SelectionMask(width: region.width, height: region.height, bytes: Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: region.width * region.height)))
  }
  static func render(_ source: Surface, frame: Layer, document: CraftDocument, region: IntRect) throws -> Surface {
    guard let definition = frame.frame, let vector = try frame.framePath(), region.width > 0, region.height > 0 else { return source }
    let path = try VectorRasterizer.filledPath(vector), mask = try coverage(path, region: region)
    let stroke: SelectionMask?
    if definition.strokeWidth > 0, definition.strokeColor.a > 0 {
      let width = definition.strokeWidth * (definition.strokeAlignment == .center ? 1 : 2)
      var outline = path.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
      if definition.strokeAlignment == .inside { outline = outline.intersection(path) }
      if definition.strokeAlignment == .outside { outline = outline.subtracting(path) }
      stroke = try coverage(outline, region: region)
    } else { stroke = nil }
    var result = source
    try result.mapPixels(in: region) { x, y, pixel in
      let offset = (y - region.y) * region.width + x - region.x
      var p = pixel; p.a *= Float(mask.byte(at:offset)) / 255
      if let stroke {
        var color = definition.strokeColor; color.a *= Float(stroke.byte(at:offset)) / 255
        p = Renderer.compositePixel(.normal, backdrop: p, source: color, opacity: 1, depth: document.depth, x: x, y: y)
      }
      return p.a > 0 ? p : .clear
    }
    return result
  }
  public static func normalized(_ path: CGPath) throws -> (VectorPath, IntRect) {
    let box = path.boundingBoxOfPath
    guard !box.isNull, !box.isInfinite, box.width > 0, box.height > 0 else { throw CraftError.invalid("The outline has no frame area.") }
    let rect = IntRect(x: Int(floor(box.minX)), y: Int(floor(box.minY)), width: Int(ceil(box.maxX)) - Int(floor(box.minX)), height: Int(ceil(box.maxY)) - Int(floor(box.minY)))
    guard rect.width <= 32768, rect.height <= 32768, abs(rect.x) <= 1_000_000, abs(rect.y) <= 1_000_000 else { throw CraftError.invalid("Frame outline exceeds supported bounds.") }
    var components: [PathComponent] = [], knots: [PathKnot] = []
    func point(_ p: CGPoint) -> PathPoint { .init((p.x - Double(rect.x)) / Double(rect.width), (p.y - Double(rect.y)) / Double(rect.height)) }
    func finish(_ closed: Bool) {
      if knots.count > 1 {
        if closed, knots.last!.anchor == knots.first!.anchor { let last = knots.removeLast(); knots[0].incoming = last.incoming }
        components.append(.init(knots: knots, closed: closed, operation: .join))
      }
      knots = []
    }
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      switch element.type {
      case .moveToPoint: finish(false); knots = [.init(point(element.points[0]))]
      case .addLineToPoint: knots.append(.init(point(element.points[0])))
      case .addCurveToPoint:
        if !knots.isEmpty { knots[knots.count - 1].outgoing = point(element.points[0]) }
        knots.append(.init(point(element.points[2]), incoming: point(element.points[1])))
      case .addQuadCurveToPoint:
        let control = point(element.points[0]), end = point(element.points[1])
        if let start = knots.last?.anchor { knots[knots.count - 1].outgoing = start.interpolated(to: control, at: 2.0/3.0) }
        knots.append(.init(end, incoming: end.interpolated(to: control, at: 2.0/3.0)))
      case .closeSubpath: finish(true)
      @unknown default: break
      }
    }
    finish(false)
    let result = VectorPath(components: components)
    try result.validate()
    guard !result.isEmpty, result.components.allSatisfy(\.closed) else { throw CraftError.invalid("A custom frame requires closed outlines.") }
    return (result, rect)
  }
  public static func conversion(_ id: UUID, in document: CraftDocument) throws -> Command {
    guard let layer = document.layers.first(where: { $0.id == id }) else { throw CraftError.invalid("Layer not found.") }
    switch layer.content {
    case .shape(let shape):
      if let definition=shape.definition {
        let matrix=try layer.coordinateTransform.inverted() * layer.shapeTransform()
        var cg=CGAffineTransform(a:matrix.a,b:matrix.b,c:matrix.c,d:matrix.d,tx:matrix.tx,ty:matrix.ty)
        let (path,bounds)=try normalized(ShapeRenderer.outline(definition).copy(using:&cg)!)
        return .frame(.convert(id,.init(width:bounds.width,height:bounds.height,shape:.custom,customPath:path),offset:.init(Double(bounds.x),Double(bounds.y))))
      }
      return .frame(.convert(id, .init(width: shape.width, height: shape.height, shape: shape.kind == .ellipse ? .ellipse : .rectangle)))
    case .text(let text):
      let (path, bounds) = try normalized(NativeTextLayout.outline(text, dpi: document.pixelsPerInch))
      return .frame(.convert(id, .init(width: bounds.width, height: bounds.height, shape: .custom, customPath: path), offset: .init(Double(bounds.x), Double(bounds.y))))
    default: throw CraftError.invalid("Select a shape or type layer to convert to a frame.")
    }
  }
  public static func fromLayers(_ ids: [UUID], name: String, in document: CraftDocument) throws -> Command {
    guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ id in document.layers.contains { $0.id == id } }) else { throw CraftError.invalid("Select layers to frame.") }
    let roots = try LayerLayout.roots(Set(ids), in: document)
    let bounds = try LayerLayout.union(roots.compactMap { try Renderer.layoutBounds($0, in: document, stored: false) }) ?? IntRect(x: 0, y: 0, width: document.width, height: document.height)
    return .frame(.create(name: name, bounds: bounds, definition: .init(width: bounds.width, height: bounds.height), children: ids))
  }
}
