import Foundation

/// Owns validated fixed-grid retouch pixels from preview through commitment.
/// The prepared result can only come from this owner's original command and input.
public final class DocumentRetouchStrokeSession {
  private enum Worker {
    case clone(CloneStrokeSession), toning(ToningStrokeSession), focus(FocusStrokeSession)
    func append(_ points: [StrokePoint]) throws -> Surface {
      switch self {
      case .clone(let value): return try value.append(points)
      case .toning(let value): return try value.append(points)
      case .focus(let value): return try value.append(points)
      }
    }
  }
  private let original: CraftDocument
  private let index: Int
  private let mask: Bool
  private let metadata: Command
  private let worker: Worker
  private var points: [StrokePoint]
  private var finished = false
  public var sampleCount: Int { points.count }

  private static func input(_ command: Command) -> (id: UUID, mask: Bool, points: [StrokePoint], toning: Bool)? {
    switch command {
    case .cloneStamp(let id, let value): return (id, value.mask, value.points, false)
    case .toning(let id, let value): return (id, value.mask, value.points, true)
    case .focus(let id, let value): return (id, value.mask, value.points, false)
    default: return nil
    }
  }
  public static func supports(document: CraftDocument, command: Command) -> Bool {
    guard document.animation == nil, document.videoTimeline == nil, document.variables == nil,
      document.modeDescriptor == nil, document.restrictedMode == nil, document.inkMode == nil,
      let input = input(command), let layer = document.layers.first(where: { $0.id == input.id })
    else { return false }
    let pixels: Surface, transform: Transform2D
    if input.mask {
      guard let value = layer.mask else { return false }
      pixels = value; transform = layer.maskCoordinateTransform
    } else {
      guard layer.smartObject == nil, case .raster(let value) = layer.content else { return false }
      pixels = value; transform = layer.coordinateTransform
      // Toning and transparency-locked edits never expand raster storage.
      if input.toning || document.isTransparencyLocked(input.id) { return true }
    }
    guard let bounds = try? transform.inverted().bounds(width: document.width, height: document.height) else { return false }
    return bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= pixels.width
      && bounds.y + bounds.height <= pixels.height
  }
  public init(document: CraftDocument, command: Command) throws {
    guard Self.supports(document: document, command: command), let input = Self.input(command),
      let index = document.layers.firstIndex(where: { $0.id == input.id })
    else { throw CraftError.unsupported("This retouching target uses complete stroke preparation.") }
    let admission: Command
    switch command {
    case .cloneStamp(let id, var value): value.brush.opacity = 0; admission = .cloneStamp(id, value)
    case .toning(let id, var value): value.brush.opacity = 0; admission = .toning(id, value)
    case .focus(let id, var value): value.brush.opacity = 0; admission = .focus(id, value)
    default: throw CraftError.unsupported("This command has no retained retouching session.")
    }
    var checked = document; try admission.apply(to: &checked)
    guard checked == document else { throw CraftError.unsupported("This document requires complete command reconciliation.") }
    let layer = checked.layers[index], pixels: Surface
    if input.mask { pixels = layer.mask! }
    else { guard case .raster(let value) = layer.content else { throw CraftError.unsupported("Rasterize the target first.") }; pixels = value }
    let clipping = (checked.selection ?? IntRect(x: 0, y: 0, width: checked.width, height: checked.height))
      .clipped(toWidth: checked.width, height: checked.height)
    let transform = input.mask ? layer.maskCoordinateTransform : layer.coordinateTransform
    switch command {
    case .cloneStamp(_, let stroke):
      worker = .clone(try CloneStrokeSession(surface: pixels, stroke: stroke, transform: transform,
        selection: clipping, selectionMask: checked.selectionMask,
        preserveTransparency: !input.mask && checked.isTransparencyLocked(input.id)))
    case .toning(_, let stroke):
      worker = .toning(try ToningStrokeSession(surface: pixels, stroke: stroke, transform: transform,
        clipping: clipping, selectionMask: checked.selectionMask))
    case .focus(_, let stroke):
      worker = .focus(try FocusStrokeSession(layer: layer, stroke: stroke,
        canvasWidth: checked.width, canvasHeight: checked.height, selection: clipping,
        selectionMask: checked.selectionMask,
        preserveTransparency: !input.mask && checked.isTransparencyLocked(input.id)))
    default: throw CraftError.unsupported("This command has no retained retouching session.")
    }
    original = checked; self.index = index; mask = input.mask; metadata = command; points = input.points
  }
  public func hasInputPrefix(_ samples: [StrokePoint]) -> Bool {
    samples.count >= points.count && points.elementsEqual(samples.prefix(points.count))
  }
  public func append(_ samples: [StrokePoint]) throws -> CraftDocument {
    guard !finished else { throw CraftError.invalid("The retouching stroke has already finished.") }
    let pixels = try worker.append(samples)
    var document = original
    if mask { document.layers[index].mask = pixels } else { document.layers[index].content = .raster(pixels) }
    points.append(contentsOf: samples)
    return document
  }
  public func prepareEdit(points samples: [StrokePoint]) throws -> PreparedEdit {
    guard hasInputPrefix(samples) else { throw CraftError.invalid("The retouching input changed during painting.") }
    let result = try append(Array(samples.dropFirst(points.count)))
    try result.validate(); try Task.checkCancellation()
    let command: Command
    switch metadata {
    case .cloneStamp(let id, var value): value.points = points; command = .cloneStamp(id, value)
    case .toning(let id, var value): value.points = points; command = .toning(id, value)
    case .focus(let id, var value): value.points = points; command = .focus(id, value)
    default: throw CraftError.unsupported("This command has no retained retouching session.")
    }
    finished = true
    return PreparedEdit(retainedStrokeOriginal: original, result: result, command: command)
  }
}
