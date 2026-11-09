import Foundation

/// A nonrecursive identity for a document-space source cache. Layer masks,
/// blending, visibility and effects remain outside the Smart Object program.
public struct SmartAppearanceReference:Codable,Equatable,Sendable {
  public var source:SmartObject
  public var sourcePixels:Surface
  public var transform:Transform2D
  public var projection:ProjectiveTransform?
  public var warp:WarpDefinition?
  public var filters:SmartFilterStack?
  public init(_ layer:Layer)throws {
    guard let source=layer.smartObject,case .raster(let pixels)=layer.content else{throw CraftError.invalid("Source appearance requires a Smart Object and editable source pixels.")}
    self.source=source;sourcePixels=pixels;transform=layer.coordinateTransform
    projection=layer.sourceProjection;warp=layer.warp;filters=layer.smartFilters
  }
  public func matches(_ layer:Layer)->Bool {
    guard let source=layer.smartObject,case .raster(let pixels)=layer.content else{return false}
    return self.source.matchesAppearanceIdentity(source) && sourcePixels==pixels && transform==layer.coordinateTransform
      && projection==layer.sourceProjection && warp==layer.warp && filters==layer.smartFilters
  }
  public var estimatedBytes:Int {1024+source.data.count+sourcePixels.allocatedBytes+(filters?.mask?.allocatedBytes ?? 0)+(filters?.programBytes ?? 0)}
  public func validate(depth:PixelDepth)throws {
    try source.validate();try sourcePixels.validated();try transform.validated();try projection?.validate();try warp?.validate();try filters?.validate()
    guard sourcePixels.depth==depth,sourcePixels.width==source.width,sourcePixels.height==source.height else{throw CraftError.invalid("Imported Smart Object reference dimensions/depth differ.")}
    if let projection{_ = try projection.followed(by:transform).bounds(width:source.width,height:source.height)}
  }
}
public final class ImportedSmartAppearance:Codable,Equatable,Sendable {
  public let reference:SmartAppearanceReference
  public let pixels:Surface?
  public let x:Int,y:Int
  public let placedRecord:Data?
  public init(layer:Layer,pixels:Surface?=nil,x:Int=0,y:Int=0,placedRecord:Data?=nil)throws {
    reference=try .init(layer);self.pixels=pixels;self.x=x;self.y=y;self.placedRecord=placedRecord
  }
  public static func ==(a:ImportedSmartAppearance,b:ImportedSmartAppearance)->Bool {
    a === b || (a.reference==b.reference && a.pixels==b.pixels && a.x==b.x && a.y==b.y && a.placedRecord==b.placedRecord)
  }
  public var estimatedBytes:Int {reference.estimatedBytes+(pixels?.allocatedBytes ?? 0)+(placedRecord?.count ?? 0)}
  public func validate(depth:PixelDepth)throws {
    try reference.validate(depth:depth)
    guard abs(Double(x))<=1_000_000,abs(Double(y))<=1_000_000,(placedRecord?.count ?? 0)<=16_777_216 else{throw CraftError.invalid("Invalid imported Smart Object appearance.")}
    if let pixels{try pixels.validated();guard pixels.depth==depth else{throw CraftError.invalid("Imported Smart Object cache depth differs.")}}
  }
  /// Reframe a document-space cache and its captured program together. Rebuild
  /// from the captured reference so an already stale cache cannot become fresh.
  func translatedCanvas(x:Int,y:Int) throws -> ImportedSmartAppearance {
    let delta = Transform2D.translation(Double(x),Double(y))
    var captured = Layer(name:"",content:.raster(reference.sourcePixels))
    captured.smartObject = reference.source;captured.affine = delta * reference.transform
    captured.sourceProjection = reference.projection;captured.warp = reference.warp
    captured.smartFilters = reference.filters
    captured.smartFilters?.transformPuppetPins(delta);captured.smartFilters?.transformPerspectivePlanes(delta)
    if let filters = reference.filters { captured.smartFilters?.maskProperties.transform = delta * filters.maskProperties.transform }
    return try .init(layer:captured,pixels:pixels,x:self.x+x,y:self.y+y,placedRecord:placedRecord)
  }
}
extension Layer {
  public var pristineSmartAppearance:ImportedSmartAppearance? {
    guard let importedSmartAppearance,importedSmartAppearance.reference.matches(self) else{return nil};return importedSmartAppearance
  }
  /// Cached data is already transformed/warped/filtered. Preserve document-space
  /// masks while presenting it as a derived raster; never change the live source.
  public func originalSmartAppearanceLayer()throws->Layer? {
    guard let appearance=pristineSmartAppearance,let pixels=appearance.pixels else{return nil}
    let maskWorld=maskCoordinateTransform
    var result=self;result.content = .raster(pixels);result.x=appearance.x;result.y=appearance.y
    result.affine=nil;result.sourceProjection=nil;result.warp=nil;result.smartFilters=nil
    result.smartObject=nil;result.importedSmartAppearance=nil
    if mask != nil{var properties=effectiveMaskProperties;properties.transform=try result.coordinateTransform.inverted()*maskWorld;result.maskProperties=properties}
    return result
  }
  public var requiresSourceSmartArchive:Bool {
    sourceProjection != nil || importedSmartAppearance != nil || warp?.sourceBounds != nil || smartObject?.mediaType=="application/vnd.photocraft.project"
  }
}
extension CraftDocument {
  var requiresSourceSmartArchive:Bool {
    func payload(_ value:AnimationLayerPayload)->Bool{value.sourceProjection != nil || value.importedSmartAppearance != nil}
    func layer(_ value:Layer)->Bool{value.requiresSourceSmartArchive || value.videoKeyframes?.contains(where:{$0.content.map(payload) ?? false}) == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.payload.map(payload) ?? false})}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])}
    return false
  }
}
