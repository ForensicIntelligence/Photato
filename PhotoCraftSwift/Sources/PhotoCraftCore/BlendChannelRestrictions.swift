import Foundation

/// RGB channel exclusion. Alpha/transparent and special-mode Photoshop fidelity
/// still needs independent fixtures; unrestricted paths retain their old math.
public enum BlendChannelRestrictions {
  public static func validate(_ channels:[Int]?,in document:CraftDocument?=nil)throws {
    guard let channels else{return}
    guard channels.count<=3,Set(channels).count==channels.count,channels.allSatisfy({(0...2).contains($0)})else{throw CraftError.invalid("Choose distinct RGB channel numbers0,1and2.")}
    if let document,document.colorMode != .rgb || document.inkMode != nil || document.restrictedMode != nil {throw CraftError.unsupported("Channel exclusion for this color mode is not implemented yet.")}
  }
  public static func applying(_ channels:[Int]?,after:Pixel,before:Pixel)->Pixel {
    guard let channels,!channels.isEmpty else{return after}
    if channels.count==3{return before}
    return Pixel(channels.contains(0) ? before.r:after.r,channels.contains(1) ? before.g:after.g,channels.contains(2) ? before.b:after.b,after.a)
  }
}
extension LayerStyle {
  /// Explicit channel-only styles do not allocate effect maps or lower document capacity.
  public var isChannelBlendingOnly:Bool {restrictedChannels != nil && effects.isEmpty && fillOpacity==1 && referenceOffset==nil && sourcePSDData==nil}
}
extension CraftDocument {
  public var requiresChannelBlendingArchive:Bool {
    func layer(_ value:Layer)->Bool {value.style?.restrictedChannels != nil || value.videoKeyframes?.contains(where:{$0.style?.restrictedChannels != nil})==true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.style?.restrictedChannels != nil})})==true{return true}
    if layerComps?.comps.contains(where:{$0.layers.contains(where:{$0.appearance?.style?.restrictedChannels != nil})})==true{return true}
    if layerComps?.lastDocumentState?.contains(where:{$0.appearance?.style?.restrictedChannels != nil})==true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])}
    return false
  }
}
