import Foundation

extension CraftDocument {
  /// Photoshop Save Selection > Document New is Multichannel with auxiliary
  /// channels only, without printing plates, a composite channel or image layers.
  public var isChannelOnly:Bool {channelOnly == true}
  public func selectionDocument(channelName:String? = nil)throws->CraftDocument {
    try validate();try Task.checkCancellation()
    guard quickMask == nil,let selection=try coverageSelection() else {
      throw CraftError.invalid("Make a selection outside Quick Mask before saving it.")
    }
    let requested=channelName?.trimmingCharacters(in:.whitespacesAndNewlines)
    let name=(requested?.isEmpty == false ? requested:nil) ?? "Alpha 1"
    let raw=try AlphaChannel.coverage(selection,width:width,height:height,depth:depth)
    let plane=try raw.mappedStoredSamples {p in
      let v=ChannelSelectionMath.coverage(0,p.r,mode:.replace,depth:depth)
      return Pixel(v,v,v)
    }.retaggedCoverageStorage(depth:depth)
    var result=try CraftDocument(width:width,height:height,depth:depth,name:"Untitled")
    result.layers=[];result.activeLayerID=nil;result.channelOnly=true
    result.alphaChannels=[AlphaChannel(name:name,pixels:plane)];result.resolution=resolution
    try result.validate();return result
  }
  func validateChannelOnly()throws {
    guard inkMode == nil,restrictedMode == nil,modeDescriptor == nil,workingICC == nil,
      layers.isEmpty,activeLayerID == nil,!hasArtboards,!hasFrames,
      !(alphaChannels ?? []).isEmpty,alphaChannels?.allSatisfy({$0.spot == nil})==true else {
      throw CraftError.invalid("A channel-only document contains auxiliary masks, with no image layers, printing inks or color-mode cache.")
    }
  }
}
