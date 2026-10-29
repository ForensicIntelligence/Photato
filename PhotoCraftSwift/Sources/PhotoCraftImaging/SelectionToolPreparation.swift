import Foundation
import CoreGraphics
import PhotoCraftCore

public enum SelectionToolPreparation {
  public static func input(_ document:CraftDocument,layerID:UUID?,allLayers:Bool)throws->Surface {
    guard document.width<=SelectionSegmentation.maximumPixels/max(1,document.height) else{throw CraftError.unsupported("Selection analysis supports at most16MP canvas pixels.")}
    let input:Surface
    if let layerID,document.layers.first(where:{$0.id==layerID})==nil {throw CraftError.invalid("Selection source layer no longer exists.")}
    if !allLayers,let id=layerID ?? document.activeLayerID,var layer=document.layers.first(where:{$0.id==id}),case .raster=layer.content {
      layer.visible=true;layer.style=nil;input=try Renderer.clippingCoverage(layer,in:document)
    }else{input=try Renderer.composite(document)}
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
  public static func overlay(_ mask:SelectionMask?,color:Pixel)throws->CGImage? {
    guard let mask else{return nil};var surface=try Surface(width:mask.width,height:mask.height)
    for y in 0..<mask.height {try Task.checkCancellation();for x in 0..<mask.width {let alpha=mask.coverage(x:x,y:y)*color.a;if alpha>0{surface.setPixel(x:x,y:y,Pixel(color.r,color.g,color.b,alpha))}}}
    return try RasterIO.displayImage(surface)
  }
}
