import Foundation

public enum MaskFilterTarget:String,CaseIterable,Codable,Sendable {
  case layerMask, smartFilterMask
}
public struct MaskFilterRequest:Sendable {
  public let layerID:UUID
  public let target:MaskFilterTarget
  public let filter:RasterFilter
  public init(layerID:UUID,target:MaskFilterTarget,filter:RasterFilter) {
    self.layerID=layerID;self.target=target;self.filter=filter
  }
}

/// A scalar adapter around the existing raster filter kernels. Mask display
/// properties and color-layer data are outside this operation.
public enum MaskFiltering {
  public static let kinds:[RasterFilter.Kind] = [.gaussianBlur,.boxBlur,.motionBlur,.highPass,.unsharpMask,.addNoise,.average,.mosaic]
  private static func source(_ document:CraftDocument,layerID:UUID,target:MaskFilterTarget)throws->(Surface,MaskProperties,Transform2D) {
    guard !document.isLocked(layerID),let layer=document.layers.first(where:{$0.id==layerID}) else {
      throw CraftError.invalid("Select an unlocked mask owner.")
    }
    if target == .smartFilterMask {
      guard layer.smartObject != nil,let stack=layer.smartFilters,let mask=stack.mask else {
        throw CraftError.invalid("The Smart Filter mask is unavailable.")
      }
      guard try layer.linkedSmartObjectPreview()==nil else {
        throw CraftError.unsupported("Resolve the linked source before changing its Smart Filter mask.")
      }
      return(mask,stack.maskProperties,stack.maskProperties.transform)
    }
    guard let mask=layer.mask else {throw CraftError.invalid("The layer mask is unavailable.")}
    return(mask,layer.effectiveMaskProperties,layer.maskCoordinateTransform)
  }
  public static func available(_ document:CraftDocument,layerID:UUID,target:MaskFilterTarget,kind:RasterFilter.Kind?=nil)->Bool {
    guard let value=try? source(document,layerID:layerID,target:target) else{return false}
    guard let kind else{return true}
    return kinds.contains(kind) && (value.0.width<=RasterFilterEngine.maximumPixels/value.0.height || RasterFilterEngine.pagedFilterKinds.contains(kind))
  }
  private static func sample(_ p:Pixel,encoding:SurfaceColorEncoding,properties:MaskProperties,depth:PixelDepth)->Float {
    let displayed=encoding == .linearRGB ? SRGBTransfer.encoded(p):p
    let v=unit(displayed.r),value=properties.inverted ? 1-v:v
    return Pixel(value,value,value).quantized(depth).r
  }
  public static func inputLayer(_ document:CraftDocument,layerID:UUID,target:MaskFilterTarget)throws->Layer {
    let (mask,properties,matrix)=try source(document,layerID:layerID,target:target)
    let mapped=try mask.mappedStoredSamples(encoding:mask.depth == .f32 ? .linearRGB:.sRGB) {p in
      let v=sample(p,encoding:mask.colorEncoding,properties:properties,depth:mask.depth)
      return Pixel(v,v,v)
    }
    let numeric=try mapped.quantizedStoredDepth(mask.depth)
    var layer=Layer(name:"Mask",content:.raster(numeric));layer.id=layerID;layer.affine=matrix
    return layer
  }
  public static func apply(_ request:MaskFilterRequest,to document:inout CraftDocument)throws {
    try Task.checkCancellation();try request.filter.validate()
    guard kinds.contains(request.filter.kind) else {throw CraftError.unsupported("This filter is not available for mask samples yet.")}
    let (mask,properties,_)=try source(document,layerID:request.layerID,target:request.target)
    let layer=try inputLayer(document,layerID:request.layerID,target:request.target)
    var proxy=try CraftDocument(width:document.width,height:document.height,depth:mask.depth)
    proxy.layers=[layer];proxy.activeLayerID=layer.id;proxy.selection=document.selection;proxy.selectionMask=document.selectionMask
    try RasterFilterEngine.apply(request.filter,to:layer.id,in:&proxy)
    guard case .raster(let filtered)=proxy.layers[0].content else {throw CraftError.invalid("Missing filtered mask samples.")}
    let scalar=try filtered.mappedStoredSamples(encoding:mask.colorEncoding){$0}
    let output=try mask.combiningStoredSamples(with:scalar) {before,after in
      let edited=unit(after.r)
      if edited==sample(before,encoding:mask.colorEncoding,properties:properties,depth:mask.depth) {return before}
      let value=properties.inverted ? 1-edited:edited
      let quantized=Pixel(value,value,value).quantized(mask.depth)
      let stored=mask.colorEncoding == .linearRGB ? SRGBTransfer.linear(quantized):quantized
      return Pixel(stored.r,stored.g,stored.b,before.a)
    }.retaggedCoverageStorage(depth:mask.depth,encoding:mask.colorEncoding)
    try Task.checkCancellation()
    guard let index=document.layers.firstIndex(where:{$0.id==request.layerID}) else {throw CraftError.invalid("The mask owner is unavailable.")}
    if request.target == .layerMask {document.layers[index].mask=output}
    else {document.layers[index].smartFilters?.mask=output}
  }
}
