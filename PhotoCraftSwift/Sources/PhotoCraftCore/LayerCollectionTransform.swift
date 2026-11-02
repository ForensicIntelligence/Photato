import Foundation

public struct LayerCollectionTransformRequest:Codable,Equatable,Sendable{
  public var layerIDs:[UUID]
  public var projection:ProjectiveTransform?
  public var matrix:Transform2D
  public var interpolation:Resampling
  public init(layerIDs:[UUID],matrix:Transform2D,interpolation:Resampling = .bicubic){self.projection=nil;self.layerIDs=layerIDs;self.matrix=matrix;self.interpolation=interpolation}
  public init(layerIDs:[UUID],projection:ProjectiveTransform,interpolation:Resampling = .bicubic){self.layerIDs=layerIDs;self.projection=projection;self.matrix = .identity;self.interpolation=interpolation}
}
public enum LayerCollectionTransform{
  public static func roots(_ document:CraftDocument,layerIDs:[UUID])throws->[Layer]{
    guard !layerIDs.isEmpty,Set(layerIDs).count==layerIDs.count else{throw CraftError.invalid("Choose distinct layer IDs for Free Transform.")}
    return try LayerDuplication.roots(in:document,selected:LayerLinks.expanded(in:document,layerIDs:Set(layerIDs)))
  }
  public static func members(_ document:CraftDocument,layerIDs:[UUID])throws->Set<UUID>{
    let roots=try roots(document,layerIDs:layerIDs)
    guard !document.colorMode.isRestricted,document.inkMode==nil,document.animation==nil,document.videoTimeline==nil,document.selection==nil,roots.allSatisfy({$0.canTransform}) else{throw CraftError.unsupported("Choose whole editable pixel/type/shape layers or groups in a static component-mode document, without a pixel selection.")}
    let hierarchy=LayerHierarchyIndex(document)
    let ids=hierarchy.subtreeIDs(Set(roots.map(\.id)))
    guard ids.allSatisfy({!hierarchy.effectiveProtection($0).locksPosition}) else{throw CraftError.invalid("Unlock positions on all selected layers and descendants before transforming.")}
    return ids
  }
  public static func available(_ document:CraftDocument,layerIDs:[UUID])->Bool{(try? members(document,layerIDs:layerIDs)) != nil}
  public static func apply(_ request:LayerCollectionTransformRequest,to document:inout CraftDocument)throws{
    if let projection=request.projection{try ProjectiveLayerTransform.apply(layerIDs:request.layerIDs,matrix:projection,interpolation:request.interpolation,to:&document);return}
    try Task.checkCancellation();try request.matrix.validated();let ids=try members(document,layerIDs:request.layerIDs)
    if request.matrix == .identity{return}
    var candidate=document
    // Always sample the immutable common source. A selected parent+child is transformed once.
    for i in candidate.layers.indices where ids.contains(candidate.layers[i].id){try Task.checkCancellation();candidate.layers[i]=try DocumentGeometry.transformLayer(document.layers[i],by:request.matrix,in:document,method:request.interpolation)}
    try candidate.validate();try Task.checkCancellation();document=candidate
  }
}
