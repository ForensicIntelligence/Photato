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
      input = try mergedSource(document)
    }
    let result = try input.convertingMode(request.conversion)
    return .preparedDocumentMode(.init(source: document, result: result, recording: .documentMode(request)))
  }

  static func mergedSource(_ document: CraftDocument) throws -> CraftDocument {
    var input = document
    let visible = document.layers.filter { $0.visible && $0.opacity > 0 }
    let plainStack = !visible.isEmpty &&
      !document.layers.contains { $0.isGroup || $0.parentID != nil || $0.isClipped } &&
      visible.allSatisfy {
        $0.nativeMode != nil && $0.blendMode == .normal && $0.style == nil && $0.affine == nil &&
          $0.warp == nil && $0.sourceProjection == nil && $0.smartObject == nil &&
          $0.smartFilters == nil && $0.video == nil
      }
    var retained: NativeModeRaster?
    let composite: Surface
    if plainStack, visible.count == 1, let layer = visible.first, let native = layer.nativeMode,
      layer.x == 0, layer.y == 0, native.width == document.width, native.height == document.height,
      layer.opacity == 1, layer.mask == nil, layer.vectorMask == nil, case .raster(let pixels) = layer.content {
      // The only visible layer already is the requested composite. Preserve
      // straight component and alpha words, including those outside display gamut.
      composite = pixels
      retained = native
    } else if plainStack, let descriptor = document.modeDescriptor, descriptor.mode == .rgb {
      var working = document
      let visibleIDs = Set(visible.map(\.id))
      for i in working.layers.indices {
        let layer = working.layers[i]
        if visibleIDs.contains(layer.id), let native = layer.nativeMode {
          working.layers[i].content = .raster(try native.retainedRGBSurface())
        }
        working.layers[i].nativeMode = nil
      }
      working.modeDescriptor = nil
      working.workingICC = descriptor.profile
      composite = try LayerMerge.integerModeComposite(working)
        ?? Renderer.composite(working).quantizedStoredDepth(document.depth)
      input.workingICC = descriptor.profile
    } else {
      composite = try Renderer.composite(document)
    }
    var layer = Layer(name: "Merged", content: .raster(composite))
    // Stable identity binds preview/API/commit to the same prepared operation.
    layer.id = document.activeLayerID ?? document.id
    layer.nativeMode = retained
    input.layers = [layer]
    input.activeLayerID = layer.id
    if retained == nil { input.modeDescriptor = nil }
    input.restrictedMode = nil
    return input
  }
}
