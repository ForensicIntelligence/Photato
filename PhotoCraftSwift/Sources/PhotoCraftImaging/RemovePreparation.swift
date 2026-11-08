import Foundation
import PhotoCraftCore

public enum RemovePreparation {
  public static let maximumCanvasPixels = ContentAwareInput.maximumCanvasPixels
  public static func coverage(_ request: RemoveRequest, in document: CraftDocument) throws -> SelectionMask {
    try request.validate()
    guard document.width > 0, document.height > 0,
      document.width <= Surface.maxDimension, document.height <= Surface.maxDimension else {
      throw CraftError.invalid("Invalid Remove canvas dimensions.")
    }
    guard document.width <= maximumCanvasPixels/document.height else {
      throw CraftError.unsupported("Native Remove currently supports canvases up to 16 megapixels. Larger Remove preparation is not implemented yet.")
    }
    var mask = try SelectionMask(width:document.width,height:document.height,
      bytes:Array(repeating:0,count:document.width*document.height))
    for stroke in request.strokes { try Task.checkCancellation(); mask = try stroke.applying(to:mask) }
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
    var settings = ContentAwareSettings(); settings.sampleAllLayers = request.settings.sampleAllLayers
    let prepared = try ContentAwareInput.prepare(input,layerID:request.layerID)
      .edit(settings:settings,output:request.settings.createNewLayer ? .new:.current)
    var result = try prepared.applied(to:input)
    // The removal region is transient tool state, never the user's selection.
    result.selection = document.selection; result.selectionMask = document.selectionMask
    if request.settings.createNewLayer, let id = result.activeLayerID,
      let index = result.layers.firstIndex(where: { $0.id == id }) { result.layers[index].name = "Remove" }
    try result.validate(); try Task.checkCancellation()
    return RegionRetouchEdit(source:document,result:result,label:"Remove")
  }
}
