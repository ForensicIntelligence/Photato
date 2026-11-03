import Foundation
import PhotoCraftCore

public enum LayerMergePreparation {
  public static func command(_ source:CraftDocument,layerIDs:Set<UUID>,operation:LayerMergeOperation)throws->Command {
    .preparedLayerMerge(try prepare(source,layerIDs:layerIDs,operation:operation))
  }
  public static func prepare(_ source:CraftDocument,layerIDs:Set<UUID>,operation:LayerMergeOperation)throws->PreparedLayerMerge {
    try source.validate();try Task.checkCancellation()
    let plan=try LayerMergePlan(operation,layerIDs:layerIDs,in:source)
    // Keep the established Photoshop pixel vectors, including hidden RGB and the
    // integer-depth arithmetic, unchanged whenever the old primitive applies.
    let hasPreparedSources=source.layers.contains{plan.removedIDs.contains($0.id) && ($0.smartFilters != nil || $0.warp != nil || $0.sourceProjection != nil || $0.importedSmartAppearance != nil)}
    if !plan.includesBackground,!hasPreparedSources,
      let allocation=try? LayerMerge.outputBounds(operation,layerIDs:layerIDs,in:source),allocation.width<=4_194_304/allocation.height {
      var result=source
      do {try LayerMerge.apply(operation,layerIDs:layerIDs,to:&result)
        return .init(source:source,result:result,layerIDs:layerIDs,operation:operation)
      } catch CraftError.unsupported(let reason) where reason == "Merging entirely transparent layers is not available yet." {
        // Transparent output is representable as an ordinary empty pixel layer.
      }
    }
    var isolated=source
    isolated.layers=source.layers.filter{plan.removedIDs.contains($0.id)}
    for i in isolated.layers.indices where plan.rootIDs.contains(isolated.layers[i].id) {isolated.layers[i].parentID=nil}
    isolated.activeLayerID=isolated.layers.first(where:{$0.id==plan.base.id})?.id ?? isolated.layers.last?.id
    isolated.setCoverageSelection(nil)
    // Auxiliary/retained document state does not influence layer composition.
    isolated.alphaChannels=nil;isolated.quickMask=nil;isolated.layerComps=nil;isolated.variables=nil
    let canvas=IntRect(x:0,y:0,width:source.width,height:source.height)
    var boxes=[canvas]
    if operation != .visible && !plan.includesBackground {
      for layer in isolated.layers where !layer.isGroup && !layer.isCanvasFill {
        if let box=try Renderer.layoutBounds(layer,in:source,stored:true){boxes.append(box)}
      }
      let margin=isolated.layers.compactMap(\.style).filter(\.enabled).map { style in
        (style.effects.filter(\.enabled).map{($0.size*2+abs($0.distance))*style.scale/100}.max() ?? 0)+8
      }.max() ?? 0
      if margin>0,let bounds=try LayerLayout.union(boxes) {
        let pad=Int(ceil(margin));boxes.append(.init(x:bounds.x-pad,y:bounds.y-pad,width:bounds.width+pad*2,height:bounds.height+pad*2))
      }
    }
    let bounds=try LayerLayout.union(boxes) ?? canvas
    isolated=try CanvasFrameGeometry.reframed(isolated,bounds:bounds)
    var pixels=try Renderer.compositePaged(isolated).quantizedStoredDepth(source.depth)
    var origin=(bounds.x,bounds.y)
    if plan.includesBackground {
      pixels=try BackgroundLayer.opaque(pixels,over:.white).quantizedStoredDepth(source.depth)
    } else if let nonempty=try pixels.contentBounds() {
      pixels=try pixels.cropped(to:nonempty);origin=(bounds.x+nonempty.x,bounds.y+nonempty.y)
    } else {
      pixels=try Surface(width:1,height:1,depth:source.depth,colorEncoding:source.depth == .f32 ? .linearRGB:.sRGB);origin=(0,0)
    }
    var merged=Layer(name:plan.includesBackground ? "Background":plan.base.name,content:.raster(pixels))
    let background=source.layers.first{$0.isBackground && plan.removedIDs.contains($0.id)}
    merged.id=background?.id ?? plan.base.id;merged.parentID=plan.parentID
    merged.x=origin.0;merged.y=origin.1
    if plan.includesBackground {merged.background=true;merged.sourceTags=["lyid":Data(repeating:0,count:4)]}
    merged.colorLabel=plan.base.colorLabel
    var result=source
    let insertionID=background?.id ?? plan.base.id
    result.layers=[]
    for layer in source.layers {
      if layer.id==insertionID {result.layers.append(merged)}
      if !plan.removedIDs.contains(layer.id){result.layers.append(layer)}
    }
    result.activeLayerID=merged.id
    try result.validate();try Task.checkCancellation()
    return .init(source:source,result:result,layerIDs:layerIDs,operation:operation)
  }
}
