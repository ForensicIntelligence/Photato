import Foundation

public enum EraserMode: String, Codable, CaseIterable, Sendable {
  case brush, pencil, block
  public var title: String { rawValue.capitalized }
}

/// Resolve once, then replay the ordinary captured brush. Existing brush-mode
/// kernels, masks, component targets and incremental/paged storage stay authoritative.
public enum EraserBrush {
  public static let blockScreenSize = 16
  public static func resolve(_ original: Brush, mode: EraserMode, zoom: Double) throws -> Brush? {
    guard zoom.isFinite, (0.01...64).contains(zoom) else { throw CraftError.invalid("Eraser zoom must be between1% and6400%.") }
    try BrushPainter.validate(original, points: [])
    guard mode != .brush else { return original }
    var value = original
    value.settings = value.settings ?? .init()
    if mode == .pencil {
      value.hardness = 1; value.settings!.aliased = true
      value.settings!.flow = 1; value.settings!.buildUp = false
    } else {
      let diameter = Int((Double(blockScreenSize) / zoom).rounded(.down))
      guard diameter > 0 else { return nil }
      var settings = BrushSettings()
      settings.tip = .init(width: 16, height: 16, bytes: Data(repeating: 255, count: 256))
      settings.aliased = true; settings.spacing = 0.01
      settings.smoothing = value.settings!.smoothing
      settings.seed = value.settings!.seed; settings.zoom = zoom
      value.size = Double(diameter); value.hardness = 1; value.opacity = 1
      value.settings = settings
    }
    try BrushPainter.validate(value, points: [])
    return value
  }
}
