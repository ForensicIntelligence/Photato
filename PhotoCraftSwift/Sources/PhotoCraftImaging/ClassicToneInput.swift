import Foundation
import PhotoCraftCore

public enum ClassicToneInput {
  /// Exact existing composition, retained as sparse/paged pixels before display
  /// reduction. This never creates a whole-canvas resident preview buffer.
  public static func equalizeOverview(in document: CraftDocument) throws -> Surface {
    try document.validate()
    let request = try RasterPreviewRequest.overview(width: document.width, height: document.height)
    let composite: Surface
    if document.colorMode == .rgb, let sparse = try SparseCanvasRenderer.composite(document) {
      composite = sparse
    } else {
      composite = try Renderer.compositeValidated(document, preferPaged: true)
    }
    return try request.reducing(composite)
  }
  public static func statistics(in source:CraftDocument,layerID:UUID?=nil,useSelection:Bool=false)throws->ToneColorStatistics {
    guard source.width<=ClassicToneEngine.maximumPixels/source.height else{throw CraftError.unsupported("Statistics source exceeds8,388,608 pixels.")}
    var document=source
    if let id=layerID {
      guard let original=source.layers.first(where:{$0.id==id}) else{throw CraftError.invalid("Statistics source layer no longer exists.")}
      if case .adjustment=original.content{throw CraftError.unsupported("Choose a rendered layer or Merged for color statistics.")}
      let ids=Set(source.subtreeIDs(id));document.layers=source.layers.filter{ids.contains($0.id)};LayerLinks.prune(in:&document)
      guard let i=document.layers.firstIndex(where:{$0.id==id}) else{throw CraftError.invalid("Missing source layer.")}
      document.layers[i].parentID=nil;document.layers[i].clipped=false;document.layers[i].visible=true;document.activeLayerID=id
    }
    let pixels=try Renderer.composite(document)
    let mask:[Float]?=useSelection ? (0..<(source.width*source.height)).map{source.selectionCoverage(x:$0%source.width,y:$0/source.width)}:nil
    return try ClassicToneEngine.statistics(pixels,mask:mask)
  }
  public static func command(_ request:ClassicToneRequest,in document:CraftDocument)throws->Command {
    try request.validate()
    guard request.settings.kind == .hdrToning else{return .toneAdjustment(request)}
    guard document.width<=ClassicToneEngine.maximumPixels/document.height else{throw CraftError.unsupported("HDR Toning supports up to8,388,608 pixels.")}
    var composite=try Renderer.composite(document)
    for y in 0..<document.height{try Task.checkCancellation();for x in 0..<document.width{
      let p=document.depth == .f32 ? composite.linearPixel(x:x,y:y):composite.pixel(x:x,y:y),a=p.a,q=Pixel(p.r*a+1-a,p.g*a+1-a,p.b*a+1-a)
      if document.depth == .f32{composite.setLinearPixel(x:x,y:y,q)}else{composite.setPixel(x:x,y:y,q)}
    }}
    let result=try ClassicToneEngine.render(composite,settings:request.settings)
    var edited=document,layer=Layer(name:"Background",content:.raster(result))
    layer.protection = .transparency
    edited.layers=[layer];edited.activeLayerID=layer.id;edited.selection=nil;edited.selectionMask=nil;edited.artboardOrigin=nil
    if let mode = document.modeDescriptor {
      edited.modeDescriptor = nil
      edited = try edited.convertingMode(.init(mode: mode.mode, depth: document.depth, profile: mode.profile, intent: mode.intent))
    }
    try edited.validate();return .hdrToning(.init(source:document,result:edited))
  }
}
