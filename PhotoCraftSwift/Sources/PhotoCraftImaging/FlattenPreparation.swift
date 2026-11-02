import Foundation
import PhotoCraftCore

public enum FlattenPreparation {
  public static func command(_ document: CraftDocument) throws -> Command {
    .flattenImage(try prepare(document))
  }
  public static func prepare(_ document: CraftDocument) throws -> FlattenImageEdit {
    try document.validate(); try Task.checkCancellation()
    if let reason = FlattenImageEdit.unavailableReason(document) { throw CraftError.unsupported(reason) }
    var result = document
    let layer: Layer
    if document.modeDescriptor != nil {
      var retained = document.layers[0]
      guard case .raster(let pixels) = retained.content,
        pixels.width == document.width, pixels.height == document.height,
        try pixels.isOpaque() else { throw CraftError.unsupported("Transparent native components need numerical paper compositing; no color conversion or source change was performed.") }
      retained.name = "Background"; retained.background = true; retained.protection = []
      retained.linkID = nil; retained.linkDisabled = nil
      retained.sourceTags = ["lyid": Data(repeating:0,count:4)]
      layer = retained
    } else {
      let composite = try Renderer.compositePaged(document)
      var background = Layer(name:"Background",content:.raster(try BackgroundLayer.opaque(composite,over:.white).quantizedStoredDepth(document.depth)))
      background.id = document.layers.first(where: \.isBackground)?.id
        ?? (document.layers.count == 1 ? document.layers[0].id : UUID())
      background.background = true
      background.sourceTags = ["lyid": Data(repeating:0,count:4)]
      layer = background
    }
    result.layers = [layer]; result.activeLayerID = layer.id; result.artboardOrigin = nil
    // Channels, guides, paths, working profiles, comps, metadata and libraries stay
    // document-owned. Removed layer references remain observable through their APIs.
    try result.validate(); try Task.checkCancellation()
    return FlattenImageEdit(source:document,result:result)
  }
}
