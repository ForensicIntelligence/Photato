import Foundation
import PhotoCraftCore

public enum DocumentModeInput {
  public static func needsMerge(_ document: CraftDocument) -> Bool {
    document.layers.contains {
      if $0.smartObject != nil || $0.smartFilters != nil { return true }
      switch $0.content { case .raster, .group: return false; default: return true }
    }
  }
  public static func command(_ request: DocumentModeRequest, in document: CraftDocument) throws -> Command {
    try document.validate(); try Task.checkCancellation()
    guard document.width <= NativeModeRaster.maximumDocumentPixels / document.height else {
      throw CraftError.unsupported("Color conversion exceeds the native canvas dimension limits.")
    }
    guard !document.layers.isEmpty || document.inkMode != nil else { throw CraftError.invalid("Open a document with layers first.") }
    if document.depth == .f32, request.conversion.depth != .f32, !request.clipHDR {
      throw CraftError.unsupported("Reducing 32-bit precision clips HDR values. Enable Clip HDR to proceed, or cancel and tone the image first.")
    }
    if needsMerge(document), !request.mergeVisible {
      throw CraftError.unsupported("This conversion requires Merge Visible Layers for type, shapes, fills, adjustments and Smart Objects/Filters.")
    }
    var input = document
    if request.mergeVisible && document.inkMode == nil {
      guard !document.hasArtboards, !document.hasFrames else {
        throw CraftError.unsupported("Convert a rendered copy of artboards or frames before changing color mode.")
      }
      let composite = try Renderer.composite(document)
      var layer = Layer(name: "Merged", content: .raster(composite))
      // Stable identity binds preview/API/commit to the same prepared operation.
      layer.id = document.activeLayerID ?? document.id
      input.layers = [layer]; input.activeLayerID = layer.id
      input.modeDescriptor = nil
      input.restrictedMode = nil
    }
    let result = try input.convertingMode(request.conversion)
    return .preparedDocumentMode(.init(source: document, result: result, recording: .documentMode(request)))
  }
}
