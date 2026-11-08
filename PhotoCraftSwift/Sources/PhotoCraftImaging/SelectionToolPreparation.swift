import Foundation
import CoreGraphics
import PhotoCraftCore

public enum SelectionToolPreparation {
  public static func canSample(_ document:CraftDocument,layerID:UUID?,allLayers:Bool)->Bool {
    if let layerID, !document.layers.contains(where:{$0.id==layerID}) {return false}
    if allLayers {return true}
    guard let id=layerID ?? document.activeLayerID,let layer=document.layers.first(where:{$0.id==id}) else{return false}
    switch layer.content {case .adjustment,.group:return false;default:return true}
  }
  public static func input(_ document:CraftDocument,layerID:UUID?,allLayers:Bool)throws->Surface {
    try Task.checkCancellation()
    guard document.width<=SelectionSegmentation.maximumPixels/max(1,document.height) else{throw CraftError.unsupported("Selection analysis supports at most16MP canvas pixels.")}
    let input:Surface
    if let layerID,document.layers.first(where:{$0.id==layerID})==nil {throw CraftError.invalid("Selection source layer no longer exists.")}
    if allLayers {input=try Renderer.composite(document)}
    else {
      guard let id=layerID ?? document.activeLayerID,var layer=document.layers.first(where:{$0.id==id}) else {
        throw CraftError.invalid("Choose a source layer or enable Sample All Layers.")
      }
      switch layer.content {
      case .adjustment,.group:
        throw CraftError.unsupported("Enable Sample All Layers to analyze a group or adjustment layer.")
      default:break
      }
      // Analysis reads the selected layer's rendered content, never unrelated
      // visible layers as an implicit fallback. Raster/Smart Object behavior is
      // unchanged; type, shapes and fills now respect the same source choice.
      layer.visible=true;layer.style=nil;input=try Renderer.clippingCoverage(layer,in:document)
    }
    return try ColorManagement.converted(input,from:document,to:CraftDocument(width:1,height:1))
  }
  public static func command(_ request:SelectionToolRequest,in document:CraftDocument,detector:any ObjectDetecting = VisionForegroundDetector())async throws->Command {
    try request.validate()
    if request.kind == .brush {return .selectionCoverage(try request.paintedSelection(in:document),.replace)}
    let image=try input(document,layerID:request.layerID,allLayers:request.sampleAllLayers)
    var mask:SelectionMask
    if request.kind == .quick {
      mask=try SelectionSegmentation.quick(image,points:request.points.map{.init($0.x,$0.y)},size:request.brush.size)
    } else if let shape=request.region {
      let region=try SelectionMask.make(shape,width:document.width,height:document.height,antiAlias:false)
      mask=try SelectionSegmentation.object(image,region:region)
    } else {
      let p=request.points[0];try ForegroundSelection.checkSize(document.width,document.height)
      guard p.x>=0,p.y>=0,p.x<Double(document.width),p.y<Double(document.height) else {throw CraftError.invalid("Click inside the image to select an object.")}
      mask=try await detector.mask(for:image,at:.init(p.x,p.y))
    }
    if request.enhanceEdge {
      var settings=SelectionRefinement();settings.radius=4;settings.smartRadius=true;settings.smooth=15;settings.contrast=25
      mask=try SelectionMatting.refine(mask,guide:image,settings:settings)
    }
    if request.kind == .object {mask=try ObjectFinderScene.coverage(mask,hardEdge:request.hardEdge)}
    try Task.checkCancellation();return .selectionCoverage(mask,request.mode)
  }
  public static func overlay(_ mask:SelectionMask?,color:Pixel,request:RasterPreviewRequest? = nil)throws->CGImage? {
    if let request, let mask {
      var surface = try request.reducing(mask.coverageSurface())
      try surface.mapPixels(in: .init(x: 0, y: 0, width: surface.width, height: surface.height)) { _,_,p in
        Pixel(color.r,color.g,color.b,unit(p.r)*color.a)
      }
      return try RasterIO.displayImage(surface)
    }
    guard let mask else{return nil};var surface=try Surface(width:mask.width,height:mask.height)
    for y in 0..<mask.height {try Task.checkCancellation();for x in 0..<mask.width {let alpha=mask.coverage(x:x,y:y)*color.a;if alpha>0{surface.setPixel(x:x,y:y,Pixel(color.r,color.g,color.b,alpha))}}}
    return try RasterIO.displayImage(surface)
  }
}
