import Foundation
import PhotoCraftCore

public enum PaintingPreparation {
  public static func prepare(_ request:PaintToolRequest,in document:CraftDocument)throws->PaintingEdit {
    try request.validate()
    let sample=try request.options.sampleAllLayers ? Renderer.composite(document):nil
    return try PaintingEdit.prepare(request,in:document,sample:sample)
  }
  public static func loadMixer(in document:CraftDocument,layerID:UUID,point:PathPoint,size:Double,allLayers:Bool,solid:Bool)throws->MixerPaint {
    guard point.x.isFinite,point.y.isFinite,abs(point.x)<=1_000_000,abs(point.y)<=1_000_000,size.isFinite,(0.5...2048).contains(size),let layer=document.layers.first(where:{$0.id==layerID}) else { throw CraftError.invalid("Invalid Mixer Brush source or size.") }
    let source=try allLayers ? Renderer.composite(document):Renderer.layerSurface(layer,in:document)
    let inverse=try (allLayers ? Transform2D.identity:layer.coordinateTransform).inverted()
    let n=solid ? 1:min(256,max(1,Int(ceil(size))))
    var tip=try Surface(width:n,height:n,depth:document.depth),sum=SIMD3<Float>.zero,alpha:Float=0
    for y in 0..<n {try Task.checkCancellation();for x in 0..<n {
      let dx=(Double(x)+0.5)/Double(n)-0.5,dy=(Double(y)+0.5)/Double(n)-0.5
      let p=inverse.point(point.x+dx*size,point.y+dy*size)
      let c=ClonePainter.sample(source,x:p.x,y:p.y,nearest:false,linear:false,outside:.clear,grayscale:false)
      tip.setPixel(x:x,y:y,c);sum += SIMD3(c.r,c.g,c.b)*c.a;alpha += c.a
    }}
    var state=MixerPaint();if alpha>0 {let c=sum/alpha;state.load(Pixel(c.x,c.y,c.z),tip:solid ? nil:tip)}
    return state
  }
}
