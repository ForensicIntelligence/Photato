import Foundation
import PhotoCraftCore

/// One canvas-space row or column. Pointer drags clamp to the document edge;
/// explicit API coordinates are validated before using the same geometry.
enum SinglePixelMarquee {
  case row, column

  func rectangle(at coordinate: Double, width: Int, height: Int) -> IntRect? {
    guard coordinate.isFinite, width > 0, height > 0 else { return nil }
    let limit = self == .row ? height : width
    let index = Int(min(Double(limit - 1), max(0, floor(coordinate))))
    return self == .row
      ? IntRect(x: 0, y: index, width: width, height: 1)
      : IntRect(x: index, y: 0, width: 1, height: height)
  }
}

extension EditorTool {
  var singlePixelMarquee: SinglePixelMarquee? {
    switch self {
    case .rowMarquee: .row
    case .columnMarquee: .column
    default: nil
    }
  }
}
