import Foundation

/// A value copy keeps document-local references intact; its NSDocument owns a new lifecycle.
public enum DocumentDuplication {
  public static func copy(_ source: CraftDocument, name: String) throws -> CraftDocument {
    try Task.checkCancellation(); try LayerDuplication.validateName(name); try source.validate()
    var result = source
    result.id = UUID(); result.name = name
    try result.validate(); try Task.checkCancellation(); return result
  }
  public static func mergedUnavailableReason(_ source: CraftDocument) -> String? {
    if source.animation != nil || source.videoTimeline != nil {
      return "Merged duplication needs temporal composition. Duplicate all layers to preserve the animation or Timeline."
    }
    if source.modeDescriptor != nil || source.restrictedMode != nil || source.inkMode != nil {
      return "Merged duplication needs native component, palette or plate composition. Duplicate all layers to preserve original samples."
    }
    return nil
  }
}
