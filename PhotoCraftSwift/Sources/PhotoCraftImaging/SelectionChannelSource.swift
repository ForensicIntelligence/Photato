import Foundation
import PhotoCraftCore

public enum SelectionChannelSource:Hashable,Sendable {
  case alpha(UUID),quickMask,composite,component(Int),transparency(UUID),layerMask(UUID),smartFilterMask(UUID),vectorMask(UUID),plate(UUID),duotone
  public func title(in document:CraftDocument)->String {
    func layer(_ id:UUID)->String {document.layers.first{$0.id==id}?.name ?? "Unavailable layer"}
    switch self {
    case .alpha(let id):return document.alphaChannels?.first{$0.id==id}?.name ?? "Unavailable channel"
    case .quickMask:return "Quick Mask"
    case .composite:return document.colorMode == .rgb ? "RGB":document.colorMode.title
    case .component(let n):return document.colorMode.componentNames.indices.contains(n) ? document.colorMode.componentNames[n]:"Unavailable component"
    case .transparency(let id):return layer(id)+" Transparency"
    case .layerMask(let id):return layer(id)+" Mask"
    case .smartFilterMask(let id):return layer(id)+" Filter Mask"
    case .vectorMask(let id):return layer(id)+" Vector Mask"
    case .plate(let id):if case .multichannel(let raster)=document.inkMode {return raster.plates.first{$0.id==id}?.name ?? "Unavailable plate"};return "Unavailable plate"
    case .duotone:return "Duotone"
    }
  }
  public static func choices(in document:CraftDocument,includingComponents:Bool=false)->[Self] {
    var result=(document.alphaChannels ?? []).map{Self.alpha($0.id)}
    if document.quickMask != nil {result.append(.quickMask)}
    if let layer=document.layers.first(where:{$0.id==document.activeLayerID}) {
      if !layer.isBackground {result.append(.transparency(layer.id))}
      if layer.mask != nil {result.append(.layerMask(layer.id))}
      if layer.smartFilters?.mask != nil {result.append(.smartFilterMask(layer.id))}
      if layer.vectorMask != nil {result.append(.vectorMask(layer.id))}
    }
    if includingComponents {
      if document.colorMode.componentCount>0 {result += [.composite]+document.colorMode.componentNames.indices.map{.component($0)}}
      if case .multichannel(let raster)=document.inkMode {result += raster.plates.map{.plate($0.id)}}
      if case .duotone=document.inkMode {result.append(.duotone)}
    }
    return result
  }
  public func selection(in document:CraftDocument,invert:Bool=false,colorSettings:ColorSettings = .init())throws->SelectionMask {
    try Task.checkCancellation()
    if case .alpha(let id)=self {
      let channel=try document.channel(.alpha(id))
      return try channel.selection(invert:(channel.spot != nil) != invert)
    }
    if case .quickMask=self {return try document.channel(.quickMask).selection(invert:invert)}
    if case .smartFilterMask(let id)=self {
      guard let index=document.layers.firstIndex(where:{$0.id==id}) else {throw CraftError.invalid("The source filter-mask owner is no longer available.")}
      var proxy=document
      proxy.layers[index]=try document.layers[index].filterMaskProjection()
      return try SelectionChannelSource.layerMask(id).selection(in:proxy,invert:invert,colorSettings:colorSettings)
    }
    var spec=ChannelArithmeticSource(documentID:document.id)
    switch self {
    case .composite:
      guard document.colorMode.componentCount>0 else{throw CraftError.invalid("This document has no composite color channel.")}
      let plane=try SelectionLuminosity.coverage(in:document,settings:colorSettings)
      return try AlphaChannel(name:"Composite Selection",pixels:plane).selection(invert:invert)
    case .component(let c):spec.channel = .component(c)
    case .transparency(let id):spec.layerID=id;spec.channel = .transparency
    case .layerMask(let id):spec.layerID=id;spec.channel = .layerMask
    case .vectorMask(let id):spec.layerID=id;spec.channel = .vectorMask
    case .plate(let id):spec.channel = .ink(.plate(id))
    case .duotone:spec.channel = .ink(.duotone)
    case .alpha,.quickMask,.smartFilterMask:preconditionFailure("Handled numeric channels")
    }
    if case .transparency(let id)=self,let index=document.layers.firstIndex(where:{$0.id==id}),document.layers[index].isGroup {
      var proxy=document;let ids=Set(document.subtreeIDs(id));proxy.layers=document.layers.filter{ids.contains($0.id)}
      let root=proxy.layers.firstIndex{$0.id==id}!
      proxy.layers[root].parentID=nil;proxy.layers[root].clipped=false;proxy.layers[root].opacity=1;proxy.layers[root].visible=true
      proxy.layers[root].mask=nil;proxy.layers[root].maskProperties=nil;proxy.layers[root].vectorMask=nil;proxy.layers[root].style=nil
      LayerLinks.prune(in:&proxy);proxy.activeLayerID=id
      let surface=try Renderer.composite(proxy).mappedStoredSamples {p in let v=invert ? 1-p.a:p.a;return Pixel(v,v,v)}
      return try SelectionMask(coverage:surface)
    }
    let plane=try ChannelArithmeticPreparation.input(spec,destination:document,sources:[]).samples
    return try AlphaChannel(name:"Loaded Selection",pixels:plane).selection(invert:invert)
  }
}
