import Foundation

public struct SeparatedChannelDescriptor:Sendable,Equatable {
  public enum Kind:String,Sendable {case component,alpha,duotone,plate}
  public let kind:Kind
  public let index:Int?
  public let channelID:UUID?
  public let name:String
  public let suffix:String
}
public struct SeparatedChannelDocument:Sendable {
  public let channel:SeparatedChannelDescriptor
  public let document:CraftDocument
}
public struct PreparedChannelSeparation:Sendable {
  public let source:CraftDocument
  public let outputs:[SeparatedChannelDocument]
}
public enum ChannelSeparation {
  public static func channels(_ document:CraftDocument)->[SeparatedChannelDescriptor] {
    var result=[SeparatedChannelDescriptor]()
    switch document.inkMode {
    case .duotone?:result.append(.init(kind:.duotone,index:nil,channelID:nil,name:"Gray",suffix:"Gray"))
    case .multichannel(let raster)?:result += raster.plates.map{.init(kind:.plate,index:nil,channelID:$0.id,name:$0.name,suffix:$0.name)}
    case nil:
      if !document.isChannelOnly {
        let suffixes:[String]
        switch document.colorMode {
        case .rgb:suffixes=["R","G","B"]
        case .cmyk:suffixes=["C","M","Y","K"]
        case .lab:suffixes=["L","a","b"]
        case .grayscale:suffixes=["Gray"]
        default:suffixes=[]
        }
        for (index,suffix) in suffixes.enumerated() {result.append(.init(kind:.component,index:index,channelID:nil,name:document.colorMode.componentNames[index],suffix:suffix))}
      }
    }
    result += (document.alphaChannels ?? []).map{.init(kind:.alpha,index:nil,channelID:$0.id,name:$0.name,suffix:$0.name)}
    return result
  }
  public static func unavailableReason(_ document:CraftDocument)->String? {
    if document.quickMask != nil{return "Exit Quick Mask before splitting channels."}
    if document.restrictedMode != nil{return "Convert Bitmap or Indexed Color before splitting channels."}
    if document.hasArtboards || document.hasFrames || document.animation != nil || document.videoTimeline != nil {return "Prepare a single static canvas before splitting channels."}
    guard channels(document).count>1 else{return "At least two channels are required."}
    if document.inkMode != nil || document.isChannelOnly{return nil}
    guard document.layers.count==1,let layer=document.layers.first,case .raster(let pixels)=layer.content,
      layer.x==0,layer.y==0,layer.affine==nil,layer.visible,layer.opacity==1,layer.blendMode == .normal,
      layer.parentID==nil,layer.clipped != true,layer.mask==nil,layer.vectorMask==nil,layer.style==nil,
      layer.smartObject==nil,layer.smartFilters==nil,layer.warp==nil,layer.sourceProjection==nil,
      pixels.width==document.width,pixels.height==document.height else{return "Flatten the image before splitting channels."}
    do {
      if let native=layer.nativeMode {if !native.isOpaque{return "Flatten transparency before splitting channels."}}
      else if try !pixels.isOpaque(){return "Flatten transparency before splitting channels."}
    }catch{return error.localizedDescription}
    return nil
  }
  public static func prepare(_ document:CraftDocument,grayProfile:Data?=nil)throws->PreparedChannelSeparation {
    try document.validate();try Task.checkCancellation()
    if let reason=unavailableReason(document){throw CraftError.unsupported(reason)}
    let descriptors=channels(document),depth=document.depth
    let native:NativeModeRaster?
    if document.inkMode==nil,!document.isChannelOnly,let layer=document.layers.first {native=try ModeComponentEdit.raster(layer,in:document)}else{native=nil}
    let profile=try grayProfile ?? NativeModeProfile.standard(.grayscale,depth:depth)
    try NativeModeProfile.validate(profile,mode:.grayscale,depth:depth)
    let opacity=try Surface(width:document.width,height:document.height,depth:depth,fill:.white)
    var outputs=[SeparatedChannelDocument]()
    for channel in descriptors {
      try Task.checkCancellation()
      let plane:Surface
      var outputProfile=profile
      switch channel.kind {
      case .component:
        guard let native,let index=channel.index else {throw CraftError.invalid("Missing component separation.")}
        let raw=try native.channel(index)
        if native.mode == .cmyk {plane=try raw.mappedStoredSamples {p in let v=1-p.r;return Pixel(v,v,v).quantized(depth)}.retaggedCoverageStorage(depth:depth)}else{plane=raw}
        if native.mode == .grayscale {outputProfile=native.profile}
      case .alpha:
        guard let id=channel.channelID else{throw CraftError.invalid("Missing auxiliary separation.")}
        let value=try document.channel(.alpha(id))
        if value.spot == nil {plane=value.pixels}
        else if let gray=value.psdSpotGray {
          plane=try value.pixels.combiningStoredSamples(with:gray){density,original in
            let v=(1-original.r).bitPattern==density.r.bitPattern ? original.r:1-density.r
            return Pixel(v,v,v).quantized(depth)
          }.retaggedCoverageStorage(depth:depth)
        }else{plane=try value.pixels.mappedStoredSamples{p in let v=1-p.r;return Pixel(v,v,v).quantized(depth)}.retaggedCoverageStorage(depth:depth)}
      case .duotone:
        guard case .duotone(let raster)=document.inkMode else{throw CraftError.invalid("Missing Duotone separation.")}
        plane=try raster.gray.surface()
      case .plate:
        guard case .multichannel(let raster)=document.inkMode,let value=raster.plates.first(where:{$0.id==channel.channelID})else{throw CraftError.invalid("Missing printing plate separation.")}
        plane=try value.samples.surface().mappedStoredSamples{p in let v=1-p.r;return Pixel(v,v,v).quantized(depth)}.retaggedCoverageStorage(depth:depth)
      }
      var gray=try NativeModeRaster(width:document.width,height:document.height,mode:.grayscale,depth:depth,profile:outputProfile)
      gray=try gray.replacingChannel(0,with:plane);gray=try gray.replacingOpacity(with:opacity)
      var result=try CraftDocument(width:document.width,height:document.height,depth:depth,name:document.name+"_"+channel.suffix)
      result.modeDescriptor=try .init(mode:.grayscale,depth:depth,profile:outputProfile)
      result.layers[0].nativeMode=gray;result.layers[0].content = .raster(try gray.surface());result.layers[0].background=true
      result.resolution=document.resolution;result.selection=document.selection;result.selectionMask=document.selectionMask
      result.paths=document.paths;result.guides=document.guides;result.sourceMetadata=document.sourceMetadata
      try result.validate();outputs.append(.init(channel:channel,document:result))
    }
    try Task.checkCancellation();return .init(source:document,outputs:outputs)
  }
}
