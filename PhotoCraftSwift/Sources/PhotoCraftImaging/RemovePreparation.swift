import Foundation
import PhotoCraftCore

public enum RemovePreparation {
  public static let maximumCanvasPixels = ContentAwareInput.maximumCanvasPixels
  package static var maximumGenerativeRegions: Int { RemoveGenerativeRegions.maximumPredictions }
  public static func supportsLocalProcessing(_ document: CraftDocument) -> Bool {
    LocalGenerativeFill.supportsDocument(document)
  }

  public static func markCoverage(_ request: RemoveRequest, in document: CraftDocument) throws -> SelectionMask {
    try request.validate()
    guard document.width > 0, document.height > 0,
      document.width <= Surface.maxDimension, document.height <= Surface.maxDimension else {
      throw CraftError.invalid("Invalid Remove canvas dimensions.")
    }
    var combined = request.initialCoverage
    for area in ([request.initialCoverage].compactMap { $0 } + request.categoryCoverages) {
      guard area.width == document.width, area.height == document.height else {
        throw CraftError.invalid("Detected removal coverage dimensions differ from the canvas.")
      }
    }
    for area in request.categoryCoverages { combined = try area.combined(with: combined, mode: .add) }
    var mask = try combined ?? SelectionMask.empty(width: document.width, height: document.height)
    for stroke in request.strokes { try Task.checkCancellation(); mask = try stroke.applying(to:mask) }
    return mask
  }
  public static func coverage(_ request: RemoveRequest, in document: CraftDocument) throws -> SelectionMask {
    if request.settings.mode == .generativeOff, document.height > 0, document.width > maximumCanvasPixels / document.height {
      throw CraftError.unsupported("Traditional Remove supports canvases up to 16 megapixels.")
    }
    var mask = try markCoverage(request, in: document)
    if let bounds = mask.bounds, document.selection != nil || document.selectionMask != nil {
      if mask.isPaged {
        let marked = mask
        let regions = try RemoveGenerativeRegions.support(of: marked)
        mask = try SelectionMask.sampledCoverage(width: document.width, height: document.height, regions: regions) { x, y in
          UInt8((Float(marked.byte(at: y * document.width + x)) * document.selectionCoverage(x: x, y: y)).rounded())
        }
      } else {
        var bytes = try mask.bytes
        for y in bounds.y..<(bounds.y + bounds.height) {
          try Task.checkCancellation()
          for x in bounds.x..<(bounds.x + bounds.width) {
            let i = y * document.width + x
            if bytes[i] != 0 { bytes[i] = UInt8((Float(bytes[i]) * document.selectionCoverage(x: x, y: y)).rounded()) }
          }
        }
        mask = try SelectionMask(width: document.width, height: document.height, bytes: bytes)
      }
    }
    guard mask.bounds != nil else { throw CraftError.invalid("Add an area to remove inside the current selection.") }
    return mask
  }
  public static func prepare(_ request: RemoveRequest, document: CraftDocument) throws -> RegionRetouchEdit {
    guard request.settings.mode != .generativeOn else { throw CraftError.unavailable("Generative AI on requires an on-device model.") }
    guard document.height > 0, document.width <= maximumCanvasPixels / document.height else {
      throw CraftError.unsupported("Traditional Remove supports canvases up to 16 megapixels.")
    }
    let (_, input, _) = try guides(request, document: document)
    return try prepareTraditional(request, source: document, input: input)
  }

  package static func prepareGenerative(_ request: RemoveRequest, document: CraftDocument,
    model: URL) throws -> RegionRetouchEdit {
    if request.settings.mode == .generativeOff { return try prepare(request, document: document) }
    let prepared = try generativeGuides(request, document: document)
    return try LocalGenerativeFill.withContextModel(model) { predict in
      try prepareGenerative(request, source: document, prepared: prepared, predict: predict)
    }
  }

  package static func generativeGuides(_ request: RemoveRequest, document: CraftDocument) throws -> (Layer, CraftDocument, SelectionMask) {
    guard supportsLocalProcessing(document), !request.settings.createNewLayer || document.layers.count < LayerLimits.maximumLayers else {
      throw CraftError.unavailable("Generative Remove requires an eligible still RGB document and space for the chosen output.")
    }
    let prepared = try guides(request, document: document)
    guard try !prepared.2.isFullCoverage else { throw CraftError.invalid("Leave some surrounding pixels outside the removal marks.") }
    return prepared
  }

  package static func prepareGenerative(_ request: RemoveRequest, source: CraftDocument,
    prepared: (Layer, CraftDocument, SelectionMask), predict: ([Float], [Float]) throws -> Surface) throws -> RegionRetouchEdit {
    let (layer, input, mask) = prepared
    guard let bounds = mask.bounds else { throw CraftError.invalid("Mark an area to remove.") }
    if max(bounds.width, bounds.height) <= RemoveGenerativeRegions.maximumSingleSide,
      source.width <= maximumCanvasPixels / source.height,
      case .raster(let raster) = layer.content, raster.width <= maximumCanvasPixels / raster.height {
      return try prepareLocalReview(request, source: source, input: input, layer: layer, mask: mask, predict: predict)
    }
    return try RemoveGenerativeRegions.prepare(request, source: source, marked: input, layer: layer, mask: mask, predict: predict)
  }

  static func prepareLocalReview(_ request: RemoveRequest, source: CraftDocument, input: CraftDocument,
    layer: Layer, mask: SelectionMask, predict: ([Float], [Float]) throws -> Surface) throws -> RegionRetouchEdit {
    let sampling = request.settings.sampleAllLayers ? nil : ContentAwareInput.samplingLayer(layer)
    let (recipe, _) = try LocalGenerativeFill.capture(input, samplingLayer: sampling, selectionBounds: mask.bounds)
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
