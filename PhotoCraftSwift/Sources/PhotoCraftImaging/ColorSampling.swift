import Foundation
import PhotoCraftCore

public enum ColorSampling {
  public static func sample(_ document:CraftDocument,x:Double,y:Double,settings:ColorSampleSettings,layerID:UUID? = nil)throws->ColorSampleResult {
    try settings.validate();try Task.checkCancellation()
    let area=try ColorAveraging.region(x:x,y:y,width:document.width,height:document.height,size:settings.size)
    let sourceID=layerID ?? document.activeLayerID
    if settings.source == .current {
      guard let sourceID,let layer=document.layers.first(where:{$0.id==sourceID})else {throw CraftError.invalid("Choose a source layer.")}
      if case .group=layer.content {
        var probe=document;let keep=Set(document.ancestors(of:sourceID).map(\.id)+Array(document.subtreeIDs(sourceID))+[sourceID])
        for i in probe.layers.indices {if !keep.contains(probe.layers[i].id){probe.layers[i].visible=false}}
        let image=try Renderer.composite(probe,region:area)
        return try ColorAveraging.sample(region:area,depth:document.depth){image.pixel(x:$0,y:$1)}
      }
      let source=try Renderer.cloneSample(in:document,layerID:sourceID,sampling:.current)
      let inverse=try source.transform.inverted()
      return try ColorAveraging.sample(region:area,depth:document.depth){x,y in
        let p=inverse.point(Double(x)+0.5,Double(y)+0.5)
        return ClonePainter.sample(source.surface,x:p.x,y:p.y,nearest:p.x-0.5 == floor(p.x-0.5) && p.y-0.5 == floor(p.y-0.5),linear:document.depth == .f32,outside:source.outside,grayscale:false)
      }
    }
    var probe=document
    let below=settings.source == .currentAndBelow || settings.source == .currentAndBelowNoAdjustments
    let ignore=settings.source == .allNoAdjustments || settings.source == .currentAndBelowNoAdjustments
    if below {
      guard let sourceID,let index=probe.layers.firstIndex(where:{$0.id==sourceID})else {throw CraftError.invalid("Choose a current sampling layer.")}
      let ancestors=Set(document.ancestors(of:sourceID).map(\.id))
      for i in probe.layers.indices where i>index && !ancestors.contains(probe.layers[i].id) {probe.layers[i].visible=false}
    }
    if ignore {for i in probe.layers.indices {if case .adjustment=probe.layers[i].content {probe.layers[i].visible=false}}}
    let image=try Renderer.composite(probe,region:area)
    return try ColorAveraging.sample(region:area,depth:document.depth){image.pixel(x:$0,y:$1)}
  }
}
