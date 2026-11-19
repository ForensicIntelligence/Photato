import Foundation
import PhotoCraftCore

public enum LayerMergePreparation {
  public static func command(_ source:CraftDocument,layerIDs:Set<UUID>,operation:LayerMergeOperation)throws->Command {
    .preparedLayerMerge(try prepare(source,layerIDs:layerIDs,operation:operation))
  }
  public static func prepare(
    _ source: CraftDocument, layerIDs: Set<UUID>, operation: LayerMergeOperation
  ) throws -> PreparedLayerMerge {
    try source.validate()
    try Task.checkCancellation()
    let plan = try LayerMergePlan(operation, layerIDs: layerIDs, in: source)
    let result: CraftDocument
    if let underlying = operation.inPlaceMergeOperation {
      result = try stampInPlace(source, layerIDs: layerIDs, plan: plan, underlying: underlying)
    } else {
      result = try mergedDocument(source, layerIDs: layerIDs, operation: operation, plan: plan)
    }
    try result.validate()
    try Task.checkCancellation()
    return .init(source: source, result: result,
      layerIDs: operation == .stampVisible ? [] : layerIDs, operation: operation)
  }

  private static func stampInPlace(
    _ source: CraftDocument, layerIDs: Set<UUID>, plan: LayerMergePlan, underlying: LayerMergeOperation
  ) throws -> CraftDocument {
    var preparedSource = source
    guard let index = source.layers.firstIndex(where: { $0.id == plan.base.id }) else {
      throw CraftError.invalid("The stamp destination is missing.")
    }
    if underlying == .down {
      // The destination blend mode remains external to the baked pixels.
      preparedSource.layers[index].blendMode = .normal
    }
    let bakingPlan = try LayerMergePlan(underlying, layerIDs: layerIDs, in: preparedSource)
    let rendered = try mergedDocument(preparedSource, layerIDs: layerIDs, operation: underlying,
      plan: bakingPlan)
    guard var baked = rendered.layers.first(where: { $0.id == plan.base.id }) else {
      throw CraftError.invalid("The stamp did not produce a destination layer.")
    }
    baked.blendMode = plan.base.blendMode
    var result = source
    result.layers[index] = baked
    result.activeLayerID = layerIDs.first
    return result
  }

  private static func mergedDocument(
    _ source: CraftDocument, layerIDs: Set<UUID>, operation: LayerMergeOperation, plan: LayerMergePlan
  ) throws -> CraftDocument {
    let clippingLayers = source.layers.filter { $0.id != plan.base.id && plan.sourceIDs.contains($0.id) }
    let mergesOneClip = operation == .down && clippingLayers.count == 1
      && clippingLayers[0].isClipped && !plan.base.isClipped
      && LayerMergePlan.supportsClippingRaster(plan.base)
      && LayerMergePlan.supportsClippedRaster(clippingLayers[0], depth: source.depth)
    var clippedDestination: Layer?
    if operation == .clippingMask || mergesOneClip {
      var merged = plan.base
      merged.content = .raster(try ClippingMaskRasterMerge.render(base: merged, clips: clippingLayers, document: source))
      clippedDestination = merged
    } else if plan.mergesAdjacentClips {
      guard let upper = clippingLayers.first else { throw CraftError.invalid("The upper clipped layer is missing.") }
      clippedDestination = try mergeAdjacentClips(lower: plan.base, upper: upper, in: source)
    }
    if let merged = clippedDestination {
      var result = source
      result.layers = source.layers.compactMap { layer in
        if layer.id == merged.id { return merged }
        return plan.removedIDs.contains(layer.id) ? nil : layer
      }
      result.activeLayerID = merged.id
      return result
    }
    return try mergeOrdinary(source, layerIDs: layerIDs, operation: operation, plan: plan)
  }

  private static func mergeOrdinary(
    _ source: CraftDocument, layerIDs: Set<UUID>, operation: LayerMergeOperation, plan: LayerMergePlan
  ) throws -> CraftDocument {
    var isolated=source
    if operation != .stampVisible {
      isolated.layers=source.layers.filter{plan.sourceIDs.contains($0.id)}
      for index in isolated.layers.indices where plan.rootIDs.contains(isolated.layers[index].id) {
        isolated.layers[index].parentID = nil
      }
    }
    isolated.activeLayerID=isolated.layers.first(where:{$0.id==plan.base.id})?.id ?? isolated.layers.last?.id
    isolated.setCoverageSelection(nil)
    // Auxiliary/retained document state does not influence layer composition.
    isolated.alphaChannels=nil;isolated.quickMask=nil;isolated.layerComps=nil;isolated.variables=nil
    let writesRGB32Layer = RGB32NormalRenderer.supportsLayerOutput(isolated)
    let hasPreparedSources = isolated.layers.contains {
      $0.smartFilters != nil || $0.warp != nil || $0.sourceProjection != nil || $0.importedSmartAppearance != nil
    }
    if !operation.preservesSources, !plan.includesBackground, !writesRGB32Layer, !hasPreparedSources,
      let allocation = try? LayerMerge.outputBounds(operation, layerIDs: layerIDs, in: source),
      allocation.width <= 4_194_304 / allocation.height {
      var result = source
      do {
        try LayerMerge.apply(operation, layerIDs: layerIDs, to: &result)
        return result
      } catch CraftError.unsupported(let reason) where reason == "Merging entirely transparent layers is not available yet." {
        // Transparent output is representable as an ordinary empty pixel layer.
      }
    }
    let output = try renderLayerOutput(isolated, in: source, operation: operation,
      includesBackground: plan.includesBackground, forLayerOutput: operation.preservesSources || writesRGB32Layer)
    let pixels = output.pixels
    let origin = (output.x, output.y)
    if operation.preservesSources {
      guard let insertion = source.layers.firstIndex(where: { $0.id == plan.base.id }) else {
        throw CraftError.invalid("The stamp's insertion layer no longer exists.")
      }
      let name = operation == .stampVisible ? nextLayerName(in: source) : "\(plan.base.name) (merged)"
      var stamp = Layer(name: name, content: .raster(pixels))
      stamp.parentID = plan.parentID
      stamp.x = origin.0; stamp.y = origin.1
      var result = source
      result.layers.insert(stamp, at: insertion + 1)
      result.activeLayerID = stamp.id
      return result
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
    return result
  }

  private static func renderLayerOutput(
    _ input: CraftDocument, in source: CraftDocument, operation: LayerMergeOperation,
    includesBackground: Bool, forLayerOutput: Bool
  ) throws -> (pixels: Surface, x: Int, y: Int) {
    var isolated = input
    let canvas=IntRect(x:0,y:0,width:source.width,height:source.height)
    var boxes=[canvas]
    if operation != .visible && operation != .stampVisible && !includesBackground {
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
    var pixels = try Renderer.compositePaged(isolated,
      forLayerOutput: forLayerOutput).quantizedStoredDepth(source.depth)
    var origin=(bounds.x,bounds.y)
    if includesBackground && !operation.preservesSources {
      pixels=try BackgroundLayer.opaque(pixels,over:.white).quantizedStoredDepth(source.depth)
    } else if let nonempty=try pixels.contentBounds() {
      pixels=try pixels.cropped(to:nonempty);origin=(bounds.x+nonempty.x,bounds.y+nonempty.y)
    } else {
      pixels=try Surface(width:1,height:1,depth:source.depth,colorEncoding:source.depth == .f32 ? .linearRGB:.sRGB);origin=(0,0)
    }
    return (pixels, origin.0, origin.1)
  }

  private static func mergeAdjacentClips(lower: Layer, upper: Layer, in source: CraftDocument) throws -> Layer {
    var result = lower
    result.opacity = 1
    if source.depth == .f32 {
      // The measured RGB32 pair uses the ordinary HDR layer-output kernel.
      var isolated = source
      isolated.layers = [lower, upper]
      for index in isolated.layers.indices {
        isolated.layers[index].parentID = nil
        isolated.layers[index].clipped = nil
      }
      isolated.activeLayerID = lower.id
      isolated.setCoverageSelection(nil)
      isolated.alphaChannels = nil
      isolated.quickMask = nil
      isolated.layerComps = nil
      isolated.variables = nil
      let merged = try renderLayerOutput(isolated, in: source, operation: .down,
        includesBackground: false, forLayerOutput: RGB32NormalRenderer.supportsLayerOutput(isolated))
      result.content = .raster(merged.pixels)
      result.x = merged.x
      result.y = merged.y
    } else {
      let merged = try ClippingMaskRasterMerge.renderAdjacent(lower: lower, upper: upper, depth: source.depth)
      result.content = .raster(merged.pixels)
      result.x = merged.x
      result.y = merged.y
    }
    return result
  }

  private static func nextLayerName(in document: CraftDocument) -> String {
    let prefix = "Layer "
    let numbers = Set(document.layers.compactMap { layer -> Int? in
      guard layer.name.hasPrefix(prefix) else { return nil }
      let suffix = layer.name.dropFirst(prefix.count)
      guard let number = Int(suffix), number > 0, String(number) == suffix else { return nil }
      return number
    })
    let maximum = numbers.max() ?? 0
    if maximum < Int.max { return "\(prefix)\(maximum + 1)" }
    var available = 1
    while numbers.contains(available) { available += 1 }
    return "\(prefix)\(available)"
  }
}
