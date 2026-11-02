import Foundation

/// First actual edit of a document-space cached type layer returns to its
/// logical baseline/box frame without baking the source transform into glyphs.
public struct ImportedTypeTransition:Sendable {
  public var layerID:UUID,content:TextContent,origin:PathPoint
  public init(layerID:UUID,content:TextContent,origin:PathPoint){self.layerID=layerID;self.content=content;self.origin=origin}
  func apply(to document:inout CraftDocument)throws {
    guard let i=document.layers.firstIndex(where:{$0.id==layerID}),!document.isLocked(layerID),!document.isImageLocked(layerID),origin.x.isFinite,origin.y.isFinite,abs(origin.x)<=1_000_000,abs(origin.y)<=1_000_000 else{throw CraftError.invalid("Choose unlocked imported type and a finite text frame.")}
    let previous=document.layers[i]
    guard let transform=try previous.sourceTypeTransform() else{throw CraftError.invalid("The original type cache changed before editing.")}
    var edited=content;edited.importedAppearance=nil;try edited.validate()
    let full=transform * .translation(origin.x,origin.y);try full.validated()
    document.layers[i].content = .text(edited);document.layers[i].x=Int(floor(full.tx));document.layers[i].y=Int(floor(full.ty))
    document.layers[i].affine = .translation(-Double(document.layers[i].x),-Double(document.layers[i].y))*full
    if document.layers[i].affine == .identity{document.layers[i].affine=nil}
    if previous.mask != nil{var properties=previous.effectiveMaskProperties;properties.transform=try full.inverted()*previous.maskCoordinateTransform;document.layers[i].maskProperties=properties}
  }
}
