import Foundation

/// Capacity admission is distinct from an invalid archive. Callers can preserve
/// the input and retry with an appropriate budget without calling it damaged.
public enum NativeArchiveMemoryLimit: Error, LocalizedError, Equatable, Sendable {
  case metadata(requiredBytes: Int, limitBytes: Int)
  case raster(requiredBytes: Int, limitBytes: Int)

  public var errorDescription: String? {
    switch self {
    case .metadata: "Native archive metadata exceeds the read memory budget."
    case .raster: "Native raster data exceeds the document memory budget."
    }
  }
}
