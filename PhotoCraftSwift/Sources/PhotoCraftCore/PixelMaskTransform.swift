import Foundation

/// Maps the stored unlinked grayscale mask in document coordinates. Layer samples stay intact.
public struct PixelMaskTransformRequest:Codable,Equatable,Sendable {
  public var layerID:UUID
  public var matrix:ProjectiveTransform
  public var interpolation:Resampling
  public init(layerID:UUID,matrix:ProjectiveTransform,interpolation:Resampling = .bicubic){self.layerID=layerID;self.matrix=matrix;self.interpolation=interpolation}
}
public enum PixelMaskTransform {
  public static func available(_ document:CraftDocument,layerID:UUID)->Bool {
    guard document.selection==nil,document.animation==nil,document.videoTimeline==nil,
      !document.isImageLocked(layerID),!document.isPositionLocked(layerID),
      let layer=document.layers.first(where:{$0.id==layerID}),layer.mask != nil,!layer.effectiveMaskProperties.linked else{return false}
    return true
  }
  public static func bounds(_ document:CraftDocument,layerID:UUID)throws->IntRect {
    guard let layer=document.layers.first(where:{$0.id==layerID}),let mask=layer.mask else{throw CraftError.invalid("The layer has no pixel mask.")}
    return try layer.maskCoordinateTransform.bounds(width:mask.width,height:mask.height)
  }
  public static func apply(_ request:PixelMaskTransformRequest,to document:inout CraftDocument)throws {
    try Task.checkCancellation();try request.matrix.validate()
    guard available(document,layerID:request.layerID),let index=document.layers.firstIndex(where:{$0.id==request.layerID}),let source=document.layers[index].mask else{throw CraftError.unsupported("Select one unlocked unlinked pixel mask without a selection. Linked/selected/channel/animation mask transforms need separate workflows.")}
    if try request.matrix.affineValue() == .identity{return}
    let layer=document.layers[index],placement=try request.matrix.preceded(by:layer.maskCoordinateTransform),bounds=try placement.bounds(width:source.width,height:source.height)
    var properties=layer.effectiveMaskProperties
    let output=try ScalarPlaneProjection.render(source,placement:placement,bounds:bounds,exterior:properties.outside,interpolation:request.interpolation);properties.transform=try layer.coordinateTransform.inverted() * .translation(Double(bounds.x),Double(bounds.y));try properties.validate();try Task.checkCancellation()
    document.layers[index].mask=output;document.layers[index].maskProperties=properties
  }
}
