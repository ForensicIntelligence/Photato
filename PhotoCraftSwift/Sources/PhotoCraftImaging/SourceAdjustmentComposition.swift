import Foundation
import PhotoCraftCore

/// Original compose::composite_layer/composite_stack adjustment behavior.
/// Separate from native Photoshop adjustment paths: source blending always uses
/// b + (a-b)*coverage, then the document's original whole-level RGBA grid.
enum SourceAdjustmentComposition {
  static func composite(_ settings:SourceAdjustment,layer:Layer,document:CraftDocument,over input:Surface,region:IntRect,mask:LayerMaskSampler?)throws->Surface {
    let transfer=try SourceAdjustmentTransfer(settings,depth:document.depth)
    var output=input
    let quantum:Float?=document.depth == .u8 ? 255:document.depth == .u16 ? 32768:nil
    for y in region.y..<(region.y+region.height) {
      try Task.checkCancellation()
      for x in region.x..<(region.x+region.width) {
        let before=document.depth == .f32 ? input.linearPixel(x:x,y:y):input.pixel(x:x,y:y)
        let amount=layer.opacity*(mask?.coverage(x:Double(x)+0.5,y:Double(y)+0.5) ?? 1)
        var result=before
        if amount>0 {
          let adjusted=transfer.applySourceSample(before,x:x,y:y)
          let blended=layer.blendMode.rgb(before.rgb,adjusted.rgb)
          let rgb=before.rgb+(blended-before.rgb)*amount
          result=Pixel(rgb.x,rgb.y,rgb.z,before.a)
        }
        if let q=quantum {
          func sample(_ v:Float)->Float {floor(v*q+0.5)/q}
          result=Pixel(sample(result.r),sample(result.g),sample(result.b),sample(result.a))
        }
        guard result.isFinite else {throw CraftError.invalid("Original adjustment output is not finite.")}
        if document.depth == .f32 {output.setLinearPixel(x:x,y:y,result)} else {output.setPixel(x:x,y:y,result)}
      }
    }
    return output
  }
}
