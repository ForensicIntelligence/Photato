import Foundation
import PhotoCraftCore

/// A presentation composite. Never use this surface as document pixels or export input.
public enum OnionSkinRenderer {
  public static func render(_ document:CraftDocument,base:Surface?=nil)throws->Surface {
    try document.validate();try Task.checkCancellation()
    if let base,base.width != document.width || base.height != document.height {throw CraftError.invalid("Onion-skin base dimensions differ from the document.")}
    var result=try base ?? Renderer.composite(document)
    guard let timeline=document.videoTimeline,let settings=timeline.onionSkin,settings.enabled else{return result}
    let samples=try settings.samples(currentFrame:timeline.currentFrame,durationFrames:timeline.durationFrames)
    guard document.width*document.height*max(1,samples.count)<=268_435_456 else{throw CraftError.unsupported("Reduce onion-skin counts or canvas size for this preview.")}
    for item in samples where item.opacity>0 {
      try Task.checkCancellation()
      let ghost=try Renderer.composite(document,videoTime:Double(item.frame)/timeline.frameRate)
      for y in 0..<document.height {
        try Task.checkCancellation()
        for x in 0..<document.width {
          let a=document.depth == .f32 ? result.linearPixel(x:x,y:y):result.pixel(x:x,y:y)
          let b=document.depth == .f32 ? ghost.linearPixel(x:x,y:y):ghost.pixel(x:x,y:y)
          let value=settings.blendMode.composite(backdrop:a,source:b,opacity:item.opacity,x:x,y:y)
          if document.depth == .f32{result.setLinearPixel(x:x,y:y,value)}else{result.setPixel(x:x,y:y,value)}
        }
      }
    }
    return result
  }
}
