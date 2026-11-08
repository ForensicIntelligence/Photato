import Foundation

/// Scalar coverage preparation around the existing eight basic raster kernels.
/// Display indication and spot-color metadata do not change stored filter input.
public enum AuxiliaryChannelFiltering {
  public static var kinds:[RasterFilter.Kind] {RasterFilterEngine.pagedFilterKinds}
  public static let legacyBoundedAPIKinds:[RasterFilter.Kind] = [.liquify]
  public static func available(_ document:CraftDocument,target:ChannelPlaneTarget,kind:RasterFilter.Kind?=nil)->Bool {
    guard (try? document.channel(target)) != nil else{return false}
    return kind.map{kinds.contains($0)} ?? true
  }
  public static func apply(_ filter:RasterFilter,to target:ChannelPlaneTarget,in document:inout CraftDocument)throws {
    try Task.checkCancellation();try filter.validate()
    guard kinds.contains(filter.kind) || legacyBoundedAPIKinds.contains(filter.kind) else {throw CraftError.unsupported("This filter requires an RGB image target.")}
    if !kinds.contains(filter.kind),document.width>RasterFilterEngine.maximumPixels/document.height {throw CraftError.unsupported("This legacy channel filter retains its 8,388,608-pixel preparation limit.")}
    var value=try document.channel(target)
    let depth=document.depth,encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
    // Stored channel samples are numeric sRGB-tagged coverage. The float proxy
    // marks the same numbers linear, matching the prior dense preparation.
    let mapped=try value.pixels.mappedStoredSamples(encoding:encoding){p in
      let v=unit(p.r);return Pixel(v,v,v).quantized(depth)
    }
    let numeric=try mapped.retaggedCoverageStorage(depth:depth,encoding:encoding)
    var proxy=try CraftDocument(width:document.width,height:document.height,depth:depth)
    proxy.layers[0].content = .raster(numeric);proxy.selection=document.selection;proxy.selectionMask=document.selectionMask
    try RasterFilterEngine.apply(filter,to:proxy.layers[0].id,in:&proxy)
    guard case .raster(let rendered)=proxy.layers[0].content else {throw CraftError.invalid("Invalid filtered channel.")}
    // The kernel's float samples are numeric gray, so retag without a transfer
    // conversion. As before, normalize every stored result to opaque grayscale.
    let output=try rendered.mappedStoredSamples(encoding:.sRGB){p in
      let v=unit(p.r);return Pixel(v,v,v).quantized(depth)
    }.retaggedCoverageStorage(depth:depth)
    try Task.checkCancellation();value.pixels=output
    try document.setChannel(value,at:target)
  }
}
