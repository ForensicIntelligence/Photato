import Foundation
import PhotoCraftCore

enum PcraftFilterGallery {
  @inline(never) static func convert(_ command:String,_ node:PcraftNode)throws->RasterFilter {
    let p=try PcraftFilterParameters(node);var settings=ArtisticGallerySettings()
    if command == "filter.filterGallery" {
      let foreground=try p.color("foreground",.black),background=try p.color("background",.white),glow=try p.color("glowColor",Pixel(0,0.62,1))
      settings.effects=try (p.field("effects")?.array() ?? []).map{entry in
        let meta=try PcraftFilterParameters(entry),name=try meta.string("filter","")
        guard let kind=GalleryFilter(rawValue:name) else{throw entry.unsupported("Unknown source gallery effect '\(name)'.")}
        let visible=try meta.flag("visible",true)
        let effect:GalleryEffect
        if let params=meta.field("params") {try meta.finish();effect=try Self.effect(kind,params,foreground:foreground,background:background,glow:glow)}
        else{effect=try Self.effect(kind,entry,foreground:foreground,background:background,glow:glow,inline:true)}
        var result=effect;result.visible=visible;return result
      }
      try p.finish()
    }else {
      let key=String(command.dropFirst("filter.gallery.".count))
      guard let kind=GalleryFilter(rawValue:key) else{throw node.unsupported("Unknown source gallery command.")}
      settings.effects=[try effect(kind,node,foreground:.black,background:.white,glow:Pixel(0,0.62,1))]
    }
    try settings.validate();var filter=RasterFilter(.filterGallery);filter.artistic=settings;try filter.validate();return filter
  }
  private static func effect(_ kind:GalleryFilter,_ node:PcraftNode,foreground:Pixel,background:Pixel,glow:Pixel,inline:Bool=false)throws->GalleryEffect {
    let p=try PcraftFilterParameters(node);var e=GalleryEffect(kind)
    if inline{_ = p.field("filter");_ = p.field("visible")}
    for control in kind.parameters {
      guard let field=p.field(control.key) else{continue}
      if !control.choices.isEmpty,let name=field.value.string {
        if let i=control.choices.firstIndex(where:{$0.caseInsensitiveCompare(name) == .orderedSame}){e.values[control.key]=Double(i)}
      }else {
        let x:Float
        if let flag=field.value.bool{x=flag ? 1:0}else{x=try field.float()}
        if control.boolean{e.values[control.key]=x==0 ? 0:1}
        else if !control.choices.isEmpty{e.values[control.key]=Double(min(Float(control.maximum),max(0,x.rounded())))}
        else{e.values[control.key]=Double(min(Float(control.maximum),max(Float(control.minimum),x)))}
      }
    }
    e.foreground=try p.color("foreground",foreground);e.background=try p.color("background",background);e.glowColor=try p.color("glowColor",glow)
    try p.finish();try e.validate();return e
  }
}
