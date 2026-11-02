import Foundation

public struct ChannelTransformRequest:Codable,Equatable,Sendable{
  public var target:ChannelPlaneTarget
  public var matrix:ProjectiveTransform
  public var interpolation:Resampling
  /// Editing gray, matching channel Fill and the native background swatch; inverted display is applied once.
  public var backgroundValue:Float
  public var copy:Bool
  public init(target:ChannelPlaneTarget,matrix:ProjectiveTransform,interpolation:Resampling = .bicubic,backgroundValue:Float = 1,copy:Bool = false){self.target=target;self.matrix=matrix;self.interpolation=interpolation;self.backgroundValue=backgroundValue;self.copy=copy}
}
public enum ChannelTransform{
  public static func available(_ document:CraftDocument,target:ChannelPlaneTarget)->Bool{
    !document.colorMode.isRestricted && document.animation==nil && document.videoTimeline==nil && (try? document.channel(target)) != nil
  }
  public static func apply(_ request:ChannelTransformRequest,to document:inout CraftDocument)throws{
    try Task.checkCancellation();try request.matrix.validate();guard request.backgroundValue.isFinite,(0...1).contains(request.backgroundValue) else{throw CraftError.invalid("Channel backgroundValue must be a finite editing gray from0to1.")}
    guard available(document,target:request.target) else{throw CraftError.unsupported("Choose an existing auxiliary channel or Quick Mask in a static unrestricted document.")}
    if try request.matrix.affineValue() == .identity{return}
    var value=try document.channel(request.target);let selection=try document.coverageSelection(),storedBackground=value.display(request.backgroundValue),width=document.width,height=document.height,depth=document.depth
    var movedSelection:SelectionMask?
    func mapped(_ source:Surface,fill:Float)throws->Surface{
      if selection != nil || request.copy{
        // The shared opaque selected-content compositor also supplies numeric scalar cut/fill/overlap.
        // Coverage surfaces are sRGB-tagged numeric samples, so no gamma operation is performed.
        var proxy=try CraftDocument(width:width,height:height,depth:depth);let numeric=try source.mappedStoredSamples{Pixel($0.r,$0.r,$0.r)}.retaggedCoverageStorage(depth:depth);proxy.layers[0].content = .raster(numeric);proxy.layers[0].background=true
        if let selection{proxy.setCoverageSelection(selection)}else{proxy.selection = .init(x:0,y:0,width:width,height:height)}
        try SelectedPixelTransform.apply(.init(layerID:proxy.layers[0].id,matrix:request.matrix,interpolation:request.interpolation,backgroundColor:Pixel(fill,fill,fill),copy:request.copy),to:&proxy)
        if selection != nil{movedSelection=try proxy.coverageSelection()}
        guard case .raster(let output)=proxy.layers[0].content else{throw CraftError.invalid("Missing transformed scalar output.")};return output
      }
      return try ScalarPlaneProjection.render(source,placement:request.matrix,bounds:.init(x:0,y:0,width:width,height:height),exterior:fill,interpolation:request.interpolation)
    }
    value.pixels=try mapped(value.pixels,fill:storedBackground)
    if let gray=value.psdSpotGray{value.psdSpotGray=try mapped(gray,fill:1-storedBackground)}
    var candidate=document;try candidate.setChannel(value,at:request.target);if selection != nil{candidate.setCoverageSelection(movedSelection)};try candidate.validate();try Task.checkCancellation();document=candidate
  }
}
/// Portable channel identity for Actions; duplicate names resolve by ordinal, not document UUID.
public enum ActionChannelTarget:Codable,Equatable,Sendable{
  case named(String,occurrence:Int),quickMask
  public init(_ target:ChannelPlaneTarget,in document:CraftDocument){
    switch target{case .quickMask:self = .quickMask;case .alpha(let id):
      guard let channels=document.alphaChannels,let index=channels.firstIndex(where:{$0.id==id}) else{self = .named("",occurrence:-1);return}
      let name=channels[index].name;self = .named(name,occurrence:channels[..<index].filter{$0.name==name}.count)
    }
  }
  public func resolve(in document:CraftDocument)throws->ChannelPlaneTarget{
    switch self{case .quickMask:guard document.quickMask != nil else{throw CraftError.invalid("Quick Mask is no longer active.")};return .quickMask
    case .named(let name,let occurrence):let matches=(document.alphaChannels ?? []).filter{$0.name==name};guard matches.indices.contains(occurrence) else{throw CraftError.invalid("Action channel ‘\(name)’ was not found.")};return .alpha(matches[occurrence].id)}
  }
}
