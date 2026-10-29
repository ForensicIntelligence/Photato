import Foundation
import PhotoCraftCore

struct VideoTransitionRenderContext {
  struct Active {
    let transition: VideoTransition
    let progress: Float
  }
  let active: [Active]
  static func prepare(_ document: CraftDocument, at time: Double? = nil) throws -> (CraftDocument, Self?) {
    var snapshot = try time.map { try document.videoCompositionSnapshot(at:$0) } ?? document.videoCompositionSnapshot()
    if let animation=document.animation,let states=animation.frames[animation.selectedIndex].transitions,!states.isEmpty {
      return(snapshot,Self(active:states.map{Active(transition:$0.transition,progress:$0.progress)}))
    }
    guard let timeline=document.videoTimeline else{return(snapshot,nil)}
    let seconds = time ?? timeline.seconds
    var active=(timeline.transitions ?? []).compactMap { transition -> Active? in
      guard let interval=transition.interval(in:document),interval.contains(seconds) else{return nil}
      return Active(transition:transition,progress:Float(min(1,max(0,(seconds-interval.startTime)/interval.duration))))
    }
    active += (timeline.frameTransitionKeys?.last(where:{$0.time<=seconds})?.states ?? []).map{Active(transition:$0.transition,progress:$0.progress)}
    guard !active.isEmpty else{return(snapshot,nil)}
    for item in active where item.transition.kind == .crossFade {
      for id in item.transition.participants {
        guard let i=document.layers.firstIndex(where:{$0.id==id}) else{continue}
        let layer=document.layers[i]
        snapshot.layers[i].visible=layer.visible
        if let clip=layer.video {snapshot.layers[i].content = .raster(clip.frames[clip.extendedSourceIndex(at:seconds)])}
      }
    }
    return(snapshot,Self(active:active))
  }
}
extension Renderer {
  static func mixTransition(_ a:Surface,_ b:Surface,progress:Float,in document:CraftDocument,region:IntRect)throws->Surface {
    if progress<=0{return a};if progress>=1{return b}
    var output=a
    for y in region.y..<region.y+region.height {
      try Task.checkCancellation()
      for x in region.x..<region.x+region.width {
        let first=document.depth == .f32 ? a.linearPixel(x:x,y:y):a.pixel(x:x,y:y)
        let last=document.depth == .f32 ? b.linearPixel(x:x,y:y):b.pixel(x:x,y:y)
        let alpha=first.a*(1-progress)+last.a*progress
        let value:Pixel
        if alpha<=0{value = .clear}else{
          let rgb=(first.rgb*first.a*(1-progress)+last.rgb*last.a*progress)/alpha
          value=Pixel(rgb.x,rgb.y,rgb.z,alpha)
        }
        if document.depth == .f32{output.setLinearPixel(x:x,y:y,value)}else{output.setPixel(x:x,y:y,value)}
      }
    }
    return output
  }
  static func fadeTransition(_ item:VideoTransitionRenderContext.Active,layer:Layer,clips:[Layer],
    before:Surface,after:Surface,in document:CraftDocument,cache:GroupRenderCache)throws->Surface {
    let amount=item.transition.edge == .start ? item.progress:1-item.progress
    var endpoint=before
    if let color=item.transition.fadeColor {
      var plain=layer;plain.opacity=1;plain.blendMode = .normal
      let isolated=try compositeStack([plain]+clips,in:document,over:emptyCanvas(document),cache:cache.suppressing(item.transition.id))
      var tint=isolated
      try tint.mapPixels(in:cache.bounds(document)){_,_,p in Pixel(color.r,color.g,color.b,p.a)}
      var blend=layer;blend.mask=nil;blend.maskProperties=nil;blend.vectorMask=nil;blend.style=nil
      endpoint=try blendCanvas(tint,over:before,layer:blend,in:document,region:cache.bounds(document))
    }
    return try mixTransition(endpoint,after,progress:amount,in:document,region:cache.bounds(document))
  }
}
