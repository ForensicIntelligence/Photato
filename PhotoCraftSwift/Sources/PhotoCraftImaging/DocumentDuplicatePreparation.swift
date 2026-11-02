import Foundation
import PhotoCraftCore

public enum DocumentDuplicatePreparation {
  public static func copy(_ source: CraftDocument, name: String, merged: Bool = false) throws -> CraftDocument {
    var result = try DocumentDuplication.copy(source, name: name)
    guard merged else { return result }
    if let reason = DocumentDuplication.mergedUnavailableReason(source) { throw CraftError.unsupported(reason) }
    let pixels = try Renderer.compositePaged(source).quantizedStoredDepth(source.depth)
    let visible = Set(source.layers.map(\.id)).subtracting(FlattenImageEdit.hiddenLayerIDs(in:source))
    let background = source.layers.contains { $0.isBackground && visible.contains($0.id) }
    var layer = Layer(name:background ? "Background" : "Layer 1", content:.raster(pixels))
    layer.background = background
    if background { layer.sourceTags = ["lyid":Data(repeating:0,count:4)] }
    result.layers = [layer]; result.activeLayerID = layer.id; result.artboardOrigin = nil
    try result.validate(); try Task.checkCancellation(); return result
  }
}
