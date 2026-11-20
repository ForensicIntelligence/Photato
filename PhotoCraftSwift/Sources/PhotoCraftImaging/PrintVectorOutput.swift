import CoreGraphics
import Foundation
import PhotoCraftCore

/// Created only from an immutable copy of the path and an immutable CGColor.
struct PrintVectorMark: @unchecked Sendable {
  let path: CGPath
  let color: CGColor

  fileprivate init(path: CGPath, color: CGColor) {
    self.path = path
    self.color = color
  }
}

enum PrintVectorOutput {
  /// Only detach an uninterrupted top stack. Rendering anything over a
  /// dependent layer would change layer order, masks, or backdrop blending.
  static func split(_ source: CraftDocument, settings: PrintSettings, space: CGColorSpace) throws
    -> (raster: CraftDocument, marks: [PrintVectorMark]) {
    guard settings.includesVectorData, settings.content == .document, settings.colorHandling == .printerManages,
      source.colorMode == .rgb, source.modeDescriptor == nil, source.depth != .f32, space.model == .rgb,
      !source.hasArtboards, !source.hasFrames, source.artboardOrigin == nil,
      source.videoTimeline == nil, source.animation == nil else { return (source, []) }
    var overlays: [[PrintVectorMark]] = []
    var lifted = Set<UUID>()
    for layer in source.layers.reversed() where layer.visible {
      try Task.checkCancellation()
      guard layer.opacity == 1, layer.blendMode == .normal, layer.parentID == nil, !layer.isClipped,
        layer.mask == nil, layer.vectorMask == nil, layer.style == nil, layer.smartFilters == nil,
        layer.smartObject == nil, layer.importedSmartAppearance == nil, layer.sourceProjection == nil,
        layer.warp == nil, layer.video == nil else { break }
      guard let marks = try? marks(for: layer, document: source, space: space), !marks.isEmpty else { break }
      lifted.insert(layer.id)
      overlays.append(marks)
    }
    try Task.checkCancellation()
    guard !lifted.isEmpty else { return (source, []) }
    var raster = source
    raster.layers.removeAll { lifted.contains($0.id) }
    if raster.layers.isEmpty { raster.layers = [Layer(name: "Print backdrop", content: .fill(.clear))] }
    if let active = raster.activeLayerID, lifted.contains(active) { raster.activeLayerID = raster.layers.last?.id }
    return (raster, overlays.reversed().flatMap { $0 })
  }

  private static func marks(for layer: Layer, document: CraftDocument, space: CGColorSpace) throws -> [PrintVectorMark] {
    func mark(_ path: CGPath, _ color: Pixel, _ transform: Transform2D) -> PrintVectorMark? {
      guard !path.isEmpty, color.a == 1 else { return nil }
      let encoded = color.quantized(document.depth)
      var affine = CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d,
        tx: transform.tx, ty: transform.ty)
      guard let mapped = path.copy(using: &affine),
        let ink = CGColor(colorSpace: space, components: [CGFloat(unit(encoded.r)), CGFloat(unit(encoded.g)), CGFloat(unit(encoded.b)), 1]) else { return nil }
      return PrintVectorMark(path: mapped, color: ink)
    }
    switch layer.content {
    case .shape(let shape):
      guard shape.importedAppearance == nil else { return [] }
      if let definition = shape.definition {
        let fill = definition.fill, stroke = definition.stroke
        guard fill.kind == .none || (fill.kind == .solid && fill.color.a == 1),
          stroke.paint.kind == .none || (stroke.paint.kind == .solid && stroke.paint.color.a == 1 && (stroke.opacity ?? 1) == 1) else { return [] }
        let path = try ShapeRenderer.outline(definition), transform = try layer.shapeTransform()
        let fillMark = fill.kind == .solid ? mark(path, fill.color, transform) : nil
        let edge = try ShapeRenderer.strokeOutline(definition, fillPath: path)
        return [fillMark, edge.flatMap { mark($0, stroke.paint.color, transform) }].compactMap { $0 }
      }
      let bounds = CGRect(x: 0, y: 0, width: shape.width, height: shape.height)
      let path = shape.kind == .rectangle ? CGPath(rect: bounds, transform: nil) : CGPath(ellipseIn: bounds, transform: nil)
      return [mark(path, shape.color, layer.coordinateTransform)].compactMap { $0 }
    case .text(let text):
      guard text.pristineSourceAppearance == nil, let type = text.typography,
        type.writingOrientation != .vertical, type.geometry?.isActive != true,
        type.antialiasMode.map({ $0 != .none }) ?? true, type.antialias != false else { return [] }
      let styles = [type.defaultStyle] + type.runs.map(\.style)
      let color = type.defaultStyle.color
      guard styles.allSatisfy({
        $0.color == color && !$0.underline && !$0.strikethrough && $0.characterFormatting?.fauxBold != true
          && $0.horizontalScale == 1 && $0.verticalScale == 1
      }) else { return [] }
      let path = try NativeTextLayout.outline(text, dpi: document.pixelsPerInch, clipToLayout: true)
      return [mark(path, color, layer.coordinateTransform)].compactMap { $0 }
    default:
      return []
    }
  }
}
