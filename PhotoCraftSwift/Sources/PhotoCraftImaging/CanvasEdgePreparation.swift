import Foundation
import PhotoCraftCore

public enum CanvasEdgePreparation {
  public static func unavailableReason(_ source:CraftDocument,operation:CanvasEdgeOperation)->String? {
    if source.animation != nil || source.videoTimeline != nil {return "Temporal canvas edges need frame and Timeline source rebasing."}
    if source.inkMode != nil {return "Ink-mode edges need numerical plate comparison and canvas rebasing."}
    if case .trim=operation,source.modeDescriptor != nil,!hasFlatNative(source) {return "Layered native component Trim needs numerical composition; display RGB would lose component distinctions."}
    return nil
  }
  private static func hasFlatNative(_ source:CraftDocument)->Bool {
    guard source.layers.count==1,let layer=source.layers.first,layer.nativeMode != nil else{return false}
    return layer.x==0 && layer.y==0 && layer.affine==nil && layer.visible && layer.opacity==1 && layer.blendMode == .normal && layer.mask==nil && layer.vectorMask==nil && layer.style==nil && layer.smartObject==nil && layer.smartFilters==nil && layer.warp==nil && layer.sourceProjection==nil
  }
  public static func command(_ source:CraftDocument,operation:CanvasEdgeOperation,background:Pixel = .white)throws->Command {
    .canvasEdges(try prepare(source,operation:operation,background:background))
  }
  public static func prepare(_ source:CraftDocument,operation:CanvasEdgeOperation,background:Pixel = .white)throws->CanvasEdgesEdit {
    try source.validate();try Task.checkCancellation()
    if let reason=unavailableReason(source,operation:operation){throw CraftError.unsupported(reason)}
    var result:CraftDocument
    switch operation {
    case .trim(let options):
      if !options.hasEdges{return CanvasEdgesEdit(source:source,result:source,operation:operation,background:background)}
      if hasFlatNative(source),let native=source.layers[0].nativeMode {
        let box=try native.trimBounds(options)
        result=try CanvasFrameGeometry.reframed(source,bounds:box,background:background)
        if box != IntRect(x:0,y:0,width:source.width,height:source.height) {
          let pixels=try native.reframedExactly(bounds:box)
          result.layers[0].nativeMode=pixels;result.layers[0].content = .raster(try pixels.surface());result.layers[0].x=0;result.layers[0].y=0;result.layers[0].affine=nil
          // Rebase from the actual final stored origin, not a temporary layer offset.
          result.layerComps=source.layerComps;CanvasFrameGeometry.rebaseComps(from:source,in:&result)
          result.setCoverageSelection(nil)
        }
      } else {
        let pixels=try source.restrictedMode?.surface() ?? Renderer.compositePaged(source)
        let box=try options.bounds(in:pixels)
        if box == IntRect(x:0,y:0,width:source.width,height:source.height){return CanvasEdgesEdit(source:source,result:source,operation:operation,background:background)}
        let crop=CropRequest(x:box.x,y:box.y,width:box.width,height:box.height)
        result=try CropGeometry.applying(crop,to:source)
        CanvasFrameGeometry.rebaseComps(from:source,in:&result)
      }
    case .revealAll:
      let canvas=IntRect(x:0,y:0,width:source.width,height:source.height)
      if source.restrictedMode != nil {return CanvasEdgesEdit(source:source,result:source,operation:operation,background:background)}
      // Enumerate leaves once. Group eyes, selection and transparent storage padding
      // do not turn retained layer pixels into a smaller storage region.
      var boxes=[canvas]
      for layer in source.layers where !layer.isGroup && !layer.isCanvasFill {
        if let box=try Renderer.layoutBounds(layer,in:source,stored:false){boxes.append(box)}
      }
      let bounds=try LayerLayout.union(boxes) ?? canvas
      result=try CanvasFrameGeometry.reframed(source,bounds:bounds,background:background)
    }
    try result.validate();try Task.checkCancellation()
    return CanvasEdgesEdit(source:source,result:result,operation:operation,background:background)
  }
}
