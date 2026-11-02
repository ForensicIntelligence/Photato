import Foundation
import PhotoCraftCore

public struct ColorRangeInput: Sendable {
  public let original: CraftDocument
  public let guide: Surface
  public static func prepare(_ document:CraftDocument) throws -> Self {
    guard document.colorMode == .rgb else { throw CraftError.unsupported("Color Range currently requires an RGB document.") }
    let composite=try Renderer.composite(document)
    return try Self(original:document,guide:ColorManagement.converted(composite,from:document,to:CraftDocument(width:1,height:1)))
  }
  public func mask(_ settings:ColorRangeSettings) throws -> SelectionMask {
    let mask=try ColorRangeSelection.mask(guide,settings:settings)
    // Existing selections constrain the new range. Deselect first to target the whole image.
    if let old=try original.coverageSelection() { return try mask.combined(with:old,mode:.intersect) }
    return mask
  }
  public func command(_ settings:ColorRangeSettings) throws -> Command { .colorRange(try mask(settings)) }
}
