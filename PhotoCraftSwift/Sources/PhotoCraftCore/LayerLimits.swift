/// Common document admission limits, independent of raster/decoder/transfer budgets.
/// 8,000 is a development capacity target, not a qualified Photoshop 2026 ceiling.
public enum LayerLimits {
  public static let maximumLayers = 8_000
  /// Each group also emits a section-divider record in PSD/PSB's signed Int16 count.
  public static let maximumPhotoshopRecords = maximumLayers * 2
}
