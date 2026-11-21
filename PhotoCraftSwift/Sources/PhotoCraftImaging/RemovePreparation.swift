import Foundation
import PhotoCraftCore

public enum RemovePreparation {
  public static let maximumCanvasPixels = ContentAwareInput.maximumCanvasPixels
  public static func markCoverage(_ request: RemoveRequest, in document: CraftDocument) throws -> SelectionMask {
    try request.validate()
    guard document.width > 0, document.height > 0,
      document.width <= Surface.maxDimension, document.height <= Surface.maxDimension else {
      throw CraftError.invalid("Invalid Remove canvas dimensions.")
    }
    guard document.width <= maximumCanvasPixels/document.height else {
      throw CraftError.unsupported("Native Remove currently supports canvases up to 16 megapixels. Larger Remove preparation is not implemented yet.")
    }
    var combined = request.initialCoverage
    for area in ([request.initialCoverage].compactMap { $0 } + request.categoryCoverages) {
      guard area.width == document.width, area.height == document.height else {
        throw CraftError.invalid("Detected removal coverage dimensions differ from the canvas.")
      }
    }
    for area in request.categoryCoverages { combined = try area.combined(with: combined, mode: .add) }
    var mask = try combined ?? SelectionMask(width:document.width,height:document.height,
      bytes:Array(repeating:0,count:document.width*document.height))
    for stroke in request.strokes { try Task.checkCancellation(); mask = try stroke.applying(to:mask) }
    return mask
  }
  public static func coverage(_ request: RemoveRequest, in document: CraftDocument) throws -> SelectionMask {
    var mask = try markCoverage(request, in: document)
    if document.selection != nil || document.selectionMask != nil {
      var bytes = try mask.bytes
      for y in 0..<document.height {
        try Task.checkCancellation()
        for x in 0..<document.width {
          let i = y*document.width+x
          bytes[i] = UInt8((Float(bytes[i])*document.selectionCoverage(x:x,y:y)).rounded())
        }
      }
      mask = try SelectionMask(width:document.width,height:document.height,bytes:bytes)
    }
    guard mask.bounds != nil else { throw CraftError.invalid("Add an area to remove inside the current selection.") }
    return mask
  }
  public static func prepare(_ request: RemoveRequest, document: CraftDocument) throws -> RegionRetouchEdit {
    let (_, input, _) = try guides(request, document: document)
    return try prepareTraditional(request, source: document, input: input)
  }

  package static func prepareReview(_ request: RemoveRequest, document: CraftDocument,
    model: URL) throws -> RegionRetouchEdit {
    let (layer, input, mask) = try guides(request, document: document)
    guard LocalGenerativeFill.selection(in: input) != nil else {
      return try prepareTraditional(request, source: document, input: input)
    }
    return try LocalGenerativeFill.withContextModel(model) { predict in
      try prepareLocalReview(request, source: document, input: input, layer: layer, mask: mask, predict: predict)
    }
  }

  static func prepareLocalReview(_ request: RemoveRequest, source: CraftDocument, input: CraftDocument,
    layer: Layer, mask: SelectionMask, predict: ([Float], [Float]) throws -> Surface) throws -> RegionRetouchEdit {
    let sampling = request.settings.sampleAllLayers ? nil : ContentAwareInput.samplingLayer(layer)
    let (recipe, _) = try LocalGenerativeFill.capture(input, samplingLayer: sampling)
    guard let pixels = try recipe.patches(in: input, predict: { image, mask in [try predict(image, mask)] }).first else {
      throw CraftError.invalid("The local model returned no Remove result.")
    }
    let edit = ContentAwareEdit(layerID: layer.id, output: request.settings.createNewLayer ? .new : .current,
      window: recipe.selection, pixels: pixels, selection: mask)
    return try finish(edit, request: request, source: source, input: input)
  }

  static func guides(_ request: RemoveRequest, document: CraftDocument) throws -> (Layer, CraftDocument, SelectionMask) {
    try request.validate(); try document.validate(); try Task.checkCancellation()
    guard document.colorMode == .rgb,
      let layer = document.layers.first(where: { $0.id == request.layerID }),
      case .raster = layer.content, layer.smartObject == nil, layer.sourceProjection == nil,
      !document.ancestors(of:layer.id).contains(where: { $0.protection.fullyLocks }),
      request.settings.createNewLayer || !document.isImageLocked(layer.id) else {
      throw CraftError.invalid("Remove requires an ordinary RGB raster layer. Unlock image pixels or choose Create New Layer.")
    }
    let mask = try coverage(request,in:document)
    var input = document; input.setCoverageSelection(mask)
    return (layer, input, mask)
  }

  private static func prepareTraditional(_ request: RemoveRequest, source: CraftDocument,
    input: CraftDocument) throws -> RegionRetouchEdit {
    var settings = ContentAwareSettings(); settings.sampleAllLayers = request.settings.sampleAllLayers
    let prepared = try ContentAwareInput.prepare(input,layerID:request.layerID)
      .edit(settings:settings,output:request.settings.createNewLayer ? .new:.current)
    return try finish(prepared, request: request, source: source, input: input)
  }

  private static func finish(_ edit: ContentAwareEdit, request: RemoveRequest, source: CraftDocument,
    input: CraftDocument) throws -> RegionRetouchEdit {
    var result = try edit.applied(to:input)
    // The removal region is transient tool state, never the user's selection.
    result.selection = source.selection; result.selectionMask = source.selectionMask
    if request.settings.createNewLayer, let id = result.activeLayerID,
      let index = result.layers.firstIndex(where: { $0.id == id }) { result.layers[index].name = "Remove" }
    try result.validate(); try Task.checkCancellation()
    return RegionRetouchEdit(source:source,result:result,label:"Remove")
  }
}
