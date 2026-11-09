import Foundation

/// Retains only canonical grayscale brush coverage. The source, target, settings and
/// command are fixed; callers cannot inject pixels or an unchecked prepared result.
public final class DocumentMaskStrokeSession {
  private struct Grid: Equatable {
    let width: Int, height: Int
    let depth: PixelDepth
    let encoding: SurfaceColorEncoding
    let matrix: [UInt64]
    let implicit: [UInt32]
    init(_ surface: Surface, _ transform: Transform2D) {
      width = surface.width; height = surface.height; depth = surface.depth; encoding = surface.colorEncoding
      matrix = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].map(\.bitPattern)
      let p = surface.defaultPixel; implicit = [p.r, p.g, p.b, p.a].map(\.bitPattern)
    }
  }
  private let original: CraftDocument
  private let template: CraftDocument
  private let index: Int
  private let metadata: Command
  private let brush: Brush
  private let boundsBrush: Brush
  private var worker: BrushStrokeSession?
  private var grid: Grid?
  private var points: [StrokePoint] = []
  private var finished = false
  private var failed = false
  public var sampleCount: Int { points.count }
  public var layerID: UUID { template.layers[index].id }

  public static func supports(document: CraftDocument, command: Command) -> Bool {
    guard document.animation == nil, document.videoTimeline == nil, document.variables == nil,
      document.modeDescriptor == nil, document.restrictedMode == nil, document.inkMode == nil else { return false }
    switch command {
    case .maskStroke(let id, _, let brush):
      return BrushStrokeSession.supports(brush) && document.layers.contains { $0.id == id && $0.mask != nil }
    case .adjustmentBrush(let request):
      var brush = request.brush; brush.settings = brush.settings ?? .init()
      guard request.objectMask == nil, BrushStrokeSession.supports(brush) else { return false }
      if let id = request.layerID {
        return document.layers.contains { layer in
          guard layer.id == id, layer.mask != nil, layer.smartObject == nil else { return false }
          if case .adjustment = layer.content { return true }; return false
        }
      }
      return !request.subtract
    default: return false
    }
  }
  public init(document: CraftDocument, command: Command) throws {
    guard Self.supports(document: document, command: command) else {
      throw CraftError.unsupported("This target uses complete mask stroke preparation.")
    }
    try document.validate(); try Task.checkCancellation()
    let prepared: CraftDocument, target: Int, paint: Brush, bounds: Brush
    switch command {
    case .maskStroke(let id, _, let value):
      var checked = document; try Command.maskStroke(id, [], value).apply(to: &checked)
      guard checked == document, let i = checked.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.unsupported("This mask stroke requires document reconciliation.")
      }
      prepared = checked; target = i; paint = try MaskStrokePreparation.normalized(value); bounds = value
    case .adjustmentBrush(let request):
      try request.validate()
      let (d,i,value) = try request.preparedMaskTarget(in: document)
      try d.validate()
      prepared = d; target = i; paint = value; bounds = value
    default: throw CraftError.unsupported("This command has no retained mask stroke.")
    }
    original = document; template = prepared; index = target; brush = paint; boundsBrush = bounds; metadata = command
  }
  public func hasInputPrefix(_ samples: [StrokePoint]) -> Bool {
    samples.count >= points.count && points.elementsEqual(samples.prefix(points.count))
  }
  public func append(_ samples: [StrokePoint], includingReleaseTail: Bool = true) throws -> CraftDocument {
    guard !finished, !failed else { throw CraftError.invalid("The finished, cancelled or failed mask stroke must be restarted.") }
    do { return try update(samples, includingReleaseTail: includingReleaseTail) }
    catch { failed = true; throw error }
  }
  private func update(_ samples: [StrokePoint], includingReleaseTail: Bool) throws -> CraftDocument {
    try Task.checkCancellation()
    guard samples.count <= 100_000 - points.count else { throw CraftError.invalid("Invalid brush input count.") }
    let all = points + samples
    var layer = template.layers[index], geometry = boundsBrush
    if !includingReleaseTail { geometry.settings?.smoothing.catchUpOnEnd = false }
    // Always derive canonical bounds from the unpainted source. A provisional tail
    // may change them; do not retain accidental expansion from an older prefix.
    try layer.expandMask(for: all, brush: geometry, clipping: original.selection)
    guard let base = layer.mask else { throw CraftError.invalid("This layer has no mask.") }
    let transform = layer.maskCoordinateTransform, nextGrid = Grid(base, transform)
    let pixels: Surface
    if worker == nil || nextGrid != grid {
      let next = try BrushStrokeSession(surface: base, brush: brush, selection: original.selection,
        selectionMask: original.selectionMask, transform: transform, grayscaleMask: true)
      pixels = try next.append(all, includingReleaseTail: includingReleaseTail)
      worker = next; grid = nextGrid
    } else { pixels = try worker!.append(samples, includingReleaseTail: includingReleaseTail) }
    layer.mask = pixels; points = all
    guard !all.isEmpty else { return original }
    var result = template
    if case .adjustmentBrush(let request) = metadata {
      if request.layerID == nil && layer.mask == template.layers[index].mask { return original }
      layer.content = .adjustment(request.adjustment); result.activeLayerID = layer.id
    }
    result.layers[index] = layer
    try result.validate(); try Task.checkCancellation()
    return result
  }
  public func prepareEdit(points samples: [StrokePoint]) throws -> PreparedEdit {
    guard hasInputPrefix(samples) else { throw CraftError.invalid("The mask stroke input changed during painting.") }
    let result = try append(Array(samples.dropFirst(points.count)), includingReleaseTail: true)
    try result.validate(); try Task.checkCancellation()
    let command: Command
    switch metadata {
    case .maskStroke(let id, _, let value): command = .maskStroke(id, points, value)
    case .adjustmentBrush(var request): request.points = points; command = .adjustmentBrush(request)
    default: throw CraftError.unsupported("This command has no retained mask stroke.")
    }
    finished = true
    return PreparedEdit(retainedStrokeOriginal: original, result: result, command: command)
  }
}
