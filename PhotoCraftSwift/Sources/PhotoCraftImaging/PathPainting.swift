import Foundation
import PhotoCraftCore

public enum PathPainting {
  public static func command(_ path:VectorPath,document:CraftDocument,layerID:UUID,brush:Brush,stroke:Bool,simulatePressure:Bool=false)throws->Command {
    try path.validate();try BrushPainter.validate(brush,points:[])
    guard !path.isEmpty,let layer=document.layers.first(where:{$0.id==layerID}),!document.isLocked(layerID),!document.isImageLocked(layerID),layer.smartObject==nil,case .raster(var pixels)=layer.content else{throw CraftError.invalid("Fill/Stroke Path requires a nonempty path and an unlocked raster layer.")}
    guard pixels.width*pixels.height<=16_777_216 else{throw CraftError.invalid("Path painting supports raster layers up to 16MP.")}
    if stroke {
      var prepared=document,total=0
      for part in path.components {
        let samples=try PathConstruction.flattened(part);total += samples.count;guard total<=PathConstruction.maxSamples else{throw CraftError.invalid("Path stroke exceeds 100,000 samples.")}
        var lengths=[Double](repeating:0,count:samples.count)
        if samples.count>1{for i in 1..<samples.count{lengths[i]=lengths[i-1]+hypot(samples[i].x-samples[i-1].x,samples[i].y-samples[i-1].y)}}
        let length=lengths.last ?? 0
        // Densify straight segments so simulated pressure follows arc length too.
        var points:[StrokePoint]=[]
        for i in samples.indices {
          let start=i>0 ? samples[i-1]:samples[i],end=samples[i],steps=i>0 ? max(1,Int(ceil(hypot(end.x-start.x,end.y-start.y)/max(0.5,min(4,brush.size/4))))):1
          guard points.count+steps<=PathConstruction.maxSamples else{throw CraftError.invalid("Path stroke exceeds its brush sample budget.")}
          for step in 1...steps{let t=Double(step)/Double(steps),p=start.interpolated(to:end,at:t),arc=i>0 ? lengths[i-1]+(lengths[i]-lengths[i-1])*t:0,pressure=simulatePressure && length>0 ? Float(max(0,sin(.pi*arc/length))):1;points.append(.init(x:p.x,y:p.y,pressure:pressure))}
        }
        var configured=brush;if simulatePressure{if configured.settings==nil{configured.settings = .init()};configured.settings!.pressureSize=true}
        try Command.stroke(layerID,points,configured).apply(to:&prepared)
      }
      return .replaceContent(layerID,prepared.layers.first{$0.id==layerID}!.content)
    }
    let coverage=try VectorRasterizer.coverage(path,width:document.width,height:document.height),transform=layer.coordinateTransform
    for y in 0..<pixels.height{try Task.checkCancellation();for x in 0..<pixels.width {
      let p=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(p.x)),dy=Int(floor(p.y)),old=pixels.pixel(x:x,y:y)
      let alpha=coverage.coverage(x:dx,y:dy)*document.selectionCoverage(x:dx,y:dy)
      var ink=brush.color;ink.a *= alpha*brush.opacity
      if document.isTransparencyLocked(layerID){ink.a *= old.a}
      var result=Renderer.compositePixel(.normal,backdrop:old,source:ink,opacity:1,depth:document.depth,x:x,y:y)
      if document.isTransparencyLocked(layerID){result.a=old.a};pixels.setPixel(x:x,y:y,result)
    }}
    return .replaceContent(layerID,.raster(pixels))
  }
}
