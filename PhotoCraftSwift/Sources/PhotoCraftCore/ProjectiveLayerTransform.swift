import Foundation

/// Common document-space placement; each selected subtree member is mapped once.
public enum ProjectiveLayerTransform {
  public static func members(_ document:CraftDocument,layerIDs:[UUID])throws->Set<UUID> {
    let ids=try LayerCollectionTransform.members(document,layerIDs:layerIDs)
    guard document.colorMode == .rgb else{throw CraftError.unsupported("Projective layer transforms in other color modes need their native component workflow.")}
    for layer in document.layers where ids.contains(layer.id) {
      guard !document.isImageLocked(layer.id),layer.nativeMode==nil,layer.video==nil,!layer.hasGeometryKeyframes,
        layer.group?.artboard==nil,layer.vectorMask==nil,!(layer.warp?.isIdentity == false && layer.mask != nil && layer.effectiveMaskProperties.linked) else{throw CraftError.unsupported("Unlock image content. Projective artboard, linked vector-mask, native-mode and temporal targets are not implemented yet.")}
      if layer.isGroup{continue}
      guard case .raster=layer.content,!layer.isBackground,
        layer.smartObject != nil || !document.isTransparencyLocked(layer.id),try layer.linkedSmartObjectPreview()==nil else{throw CraftError.unsupported("Projective whole-layer editing currently supports ordinary RGB pixel layers, resolved Smart Objects and their groups. Editable type/shapes and unresolved linked caches require separate support; no content is flattened.")}
      if let stack=layer.smartFilters {
        guard !stack.filters.contains(where:{$0.filter.puppet != nil || $0.filter.perspective != nil}) else{throw CraftError.unsupported("Projective placement of spatial Puppet/Perspective Smart Filter controls is not implemented yet.")}
      }
    }
    return ids
  }
  public static func available(_ document:CraftDocument,layerIDs:[UUID])->Bool{(try? members(document,layerIDs:layerIDs)) != nil}
  public static func apply(layerIDs:[UUID],matrix:ProjectiveTransform,interpolation:Resampling,to document:inout CraftDocument)throws {
    try Task.checkCancellation();try matrix.validate()
    if let affine=try matrix.affineValue(){try LayerCollectionTransform.apply(.init(layerIDs:layerIDs,matrix:affine,interpolation:interpolation),to:&document);return}
    let ids=try members(document,layerIDs:layerIDs)
    // Native quad controls cannot cross infinity across their shared bounds.
    // Apply the same guard to explicit API/Action targets, including empty gaps.
    let boxes=try document.layers.filter{ids.contains($0.id)}.compactMap{layer->IntRect? in
      guard case .raster(let source)=layer.content else{return nil}
      return try (layer.sourceProjection ?? .identity).followed(by:layer.coordinateTransform).bounds(width:source.width,height:source.height)
    }
    if let first=boxes.first {
      let left=boxes.reduce(first.x){min($0,$1.x)},top=boxes.reduce(first.y){min($0,$1.y)},right=boxes.reduce(first.x+first.width){max($0,$1.x+$1.width)},bottom=boxes.reduce(first.y+first.height){max($0,$1.y+$1.height)}
      let scale=matrix.values.map{abs($0)}.max()!,m=matrix.values.map{$0/scale},corners=[(left,top),(right,top),(right,bottom),(left,bottom)]
      let weights=corners.map{m[6]*Double($0.0)+m[7]*Double($0.1)+m[8]},epsilon=max(Double.leastNormalMagnitude,(weights.map{abs($0)}.max() ?? 1)*1e-12)
      guard weights.allSatisfy({$0>epsilon}) || weights.allSatisfy({$0 < -epsilon}) else{throw CraftError.invalid("The projective horizon crosses the shared transform bounds.")}
    }
    var candidate=document
    for index in candidate.layers.indices where ids.contains(candidate.layers[index].id) {
      try Task.checkCancellation();let original=document.layers[index];var layer=original
      if case .raster(let source)=original.content {
        let placed=try (original.sourceProjection ?? .identity).followed(by:original.coordinateTransform).followed(by:matrix)
        let bounds=try placed.bounds(width:source.width,height:source.height)
        if original.smartObject != nil {
          // The original source/cache, warp and filter stack remain editable.
          layer.x=0;layer.y=0;layer.affine=nil;layer.sourceProjection=placed;layer.importedSmartAppearance=nil
          layer.warp=original.warp ?? WarpDefinition();layer.warp?.interpolation=interpolation
        }else{
          layer.content = .raster(try ProjectiveRaster.renderPaged(source,placement:placed,bounds:bounds,method:interpolation))
          layer.x=bounds.x;layer.y=bounds.y;layer.affine=nil
        }
      }else {layer.x=0;layer.y=0;layer.affine=nil}
      if let source=original.mask {
        var properties=original.effectiveMaskProperties
        if properties.linked {
          let placement=try matrix.preceded(by:original.maskCoordinateTransform),bounds=try placement.bounds(width:source.width,height:source.height)
          layer.mask=try ScalarPlaneProjection.render(source,placement:placement,bounds:bounds,exterior:properties.outside,interpolation:interpolation)
          properties.transform=try layer.coordinateTransform.inverted() * .translation(Double(bounds.x),Double(bounds.y))
        }else{properties.transform=try layer.coordinateTransform.inverted()*original.maskCoordinateTransform}
        layer.maskProperties=properties
      }
      if let stack=original.smartFilters,let source=stack.mask,stack.maskProperties.linked {
        let placement=ProjectiveTransform(stack.maskProperties.transform),full=try placement.followed(by:matrix),bounds=try full.bounds(width:source.width,height:source.height)
        layer.smartFilters?.mask=try ScalarPlaneProjection.render(source,placement:full,bounds:bounds,exterior:stack.maskProperties.outside,interpolation:interpolation)
        layer.smartFilters?.maskProperties.transform = .translation(Double(bounds.x),Double(bounds.y))
      }
      candidate.layers[index]=layer
    }
    try candidate.validate();try Task.checkCancellation();document=candidate
  }
}
