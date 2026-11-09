import CoreGraphics
import Foundation
import PhotoCraftCore

public struct SkyReplacementInput:Sendable {
  public let original:CraftDocument,composite:Surface,guide:Surface
  /// Legacy canvases retain their full preview; large canvases use an overview plus bounded visible tiles.
  public static func display(_ surface:Surface,in document:CraftDocument,request:RasterPreviewRequest? = nil)throws->CGImage {
    try SkyRasterPreparation.display(surface,in:document,request:request)
  }
  public static func prepare(_ document:CraftDocument)throws->Self {
    try document.validate()
    let composite=try document.width>SkyReplacement.denseMaximumPixels/document.height ? Renderer.compositePaged(document):Renderer.composite(document)
    return Self(original:document,composite:composite,guide:try SkyRasterPreparation.converted(composite,from:document,to:CraftDocument(width:1,height:1)))
  }
  public static func selection(_ document:CraftDocument,layerID:UUID?,allLayers:Bool=true,settings:SkySelectionSettings = .init(),mode:SelectionMode = .replace)throws->Command {
    let image:Surface
    if document.width<=SelectionSegmentation.maximumPixels/document.height {image=try SelectionToolPreparation.input(document,layerID:layerID,allLayers:allLayers)}
    else {
      try document.validate()
      if let layerID,!document.layers.contains(where:{$0.id==layerID}){throw CraftError.invalid("Selection source layer no longer exists.")}
      let source:Surface
      if allLayers{source=try Renderer.compositePaged(document)}
      else {
        guard let id=layerID ?? document.activeLayerID,var layer=document.layers.first(where:{$0.id==id}) else{throw CraftError.invalid("Choose a source layer or enable Sample All Layers.")}
        switch layer.content{case .adjustment,.group:throw CraftError.unsupported("Enable Sample All Layers to analyze a group or adjustment layer.");default:break}
        layer.visible=true;layer.style=nil;source=try SkyRasterPreparation.placed(layer,in:document)
      }
      image=try SkyRasterPreparation.converted(source,from:document,to:CraftDocument(width:1,height:1))
    }
    guard let mask=try SkySelection.mask(image,settings:settings) else{throw CraftError.invalid("No sky was detected. The selection is unchanged.")}
    return .selectionCoverage(mask,mode)
  }
  public func edit(sky source:CraftDocument,name:String,settings p:SkyReplacementSettings,strokes:[SkyMaskStroke]=[],detected:SelectionMask?=nil)throws->(edit:SkyReplacementEdit,mask:SelectionMask) {
    try p.validate();try source.validate()
    guard let detected=try detected ?? SkySelection.mask(guide,settings:p.selection) else{throw CraftError.invalid("No sky was detected. Try another image or use a manually created mask.")}
    guard detected.width==original.width,detected.height==original.height else{throw CraftError.invalid("Sky mask dimensions differ.")}
    let mask=try SkyReplacement.refined(detected,settings:p,strokes:strokes)
    guard mask.bounds != nil else{throw CraftError.invalid("The sky mask is empty.")}
    let rendered=try source.width>SkyReplacement.denseMaximumPixels/source.height ? Renderer.compositePaged(source):Renderer.composite(source)
    let sky=try SkyRasterPreparation.converted(rendered,from:source,to:original),matrix=p.transform(sky:sky,width:original.width,height:original.height)
    guard original.layers.count+7<=LayerLimits.maximumLayers else{throw CraftError.invalid("Remove layers before creating Sky Replacement output.")}
    var result=original;let group=Layer(name:"Sky Replacement",content:.group(.init(passThrough:true)))
    func raster(_ coverage:SelectionMask,inverted:Bool=false)throws->Surface {
      if coverage.width>SkyReplacement.denseMaximumPixels/coverage.height{return try SkyRasterPreparation.mask(coverage,inverted:inverted)}
      var out=try Surface(width:coverage.width,height:coverage.height,fill:inverted ? .white:.black)
      for y in 0..<coverage.height{try Task.checkCancellation();for x in 0..<coverage.width {var v=coverage.coverage(x:x,y:y);if inverted{v=1-v};out.setPixel(x:x,y:y,Pixel(v,v,v))}}
      return out
    }
    var skyLayer=Layer(name:name.isEmpty ? "Sky":name,content:.raster(sky));skyLayer.parentID=group.id;skyLayer.affine=matrix;skyLayer.mask=try raster(mask)
    var mp=MaskProperties();mp.transform=try matrix.inverted();mp.linked=false;skyLayer.maskProperties=mp
    // Keep full imported pixels with an affine placement; refinements remain an editable canvas-space mask.
    let placed=try SkyRasterPreparation.placed(skyLayer,in:original)
    var oldMean=SIMD3<Double>.zero,newMean=oldMean,total=0.0
    if original.width>SkyReplacement.denseMaximumPixels/original.height {
      let values=try SkyRasterPreparation.statistics(original:composite,replacement:placed,mask:mask)
      oldMean=values.original;newMean=values.replacement;total=values.weight
    } else {
      for y in stride(from:0,to:original.height,by:2){try Task.checkCancellation();for x in stride(from:0,to:original.width,by:2){
        let a=Double(mask.coverage(x:x,y:y)),old=composite.pixel(x:x,y:y),new=placed.pixel(x:x,y:y),weight=a*Double(new.a)
        oldMean+=SIMD3(Double(old.r),Double(old.g),Double(old.b))*weight;newMean+=SIMD3(Double(new.r),Double(new.g),Double(new.b))*weight;total+=weight
      }}
    }
    guard total>1e-8 else{throw CraftError.invalid("Move or scale the replacement sky so it overlaps the selected sky.")};oldMean/=total;newMean/=total
    func luminance(_ v:SIMD3<Double>)->Double{v.x*0.2126+v.y*0.7152+v.z*0.0722}
    let exposure=Float(min(2,max(-2,log2(max(0.01,luminance(newMean))/max(0.01,luminance(oldMean))))))
    func adjustment(_ title:String,_ value:Adjustment,mask:Surface?,clipped:Bool=false)->Layer {
      var layer=Layer(name:title,content:.adjustment(value));layer.parentID=group.id;layer.mask=mask;layer.clipped=clipped;return layer
    }
    let foreground=try raster(mask,inverted:true)
    var lighting=adjustment("Foreground Lighting",.exposure(exposure),mask:foreground);lighting.opacity=Float(p.foregroundLighting/100);lighting.blendMode=p.lightingMode == .multiply ? .multiply:.screen
    let difference=newMean-oldMean
    let colors=ColorBalanceValues(cyanRed:Int(min(100,max(-100,difference.x*100))),magentaGreen:Int(min(100,max(-100,difference.y*100))),yellowBlue:Int(min(100,max(-100,difference.z*100))))
    var harmony=adjustment("Foreground Color",.colorBalance(.init(midtones:colors)),mask:foreground);harmony.opacity=Float(p.colorAdjustment/100)
    var edge=adjustment("Edge Lighting",.exposure(exposure),mask:try raster(SkyReplacement.edgeMask(mask)));edge.opacity=Float(p.edgeLighting/100)
    let brightness=adjustment("Sky Brightness",.brightnessContrast(Float(p.brightness/200),1),mask:nil,clipped:true)
    let temp=Int((p.temperature/2).rounded()),temperature=adjustment("Sky Temperature",.colorBalance(.init(midtones:.init(cyanRed:temp,yellowBlue:-temp))),mask:nil,clipped:true)
    result.layers += [lighting,harmony,edge,skyLayer,brightness,temperature,group];result.activeLayerID=group.id
    try result.validate()
    if p.output == .duplicate {
      let merged=try Renderer.composite(result);result=original;let layer=Layer(name:"Sky Replacement",content:.raster(merged));result.layers.append(layer);result.activeLayerID=layer.id
    }
    try Task.checkCancellation();return (.init(source:original,result:result),mask)
  }
}
