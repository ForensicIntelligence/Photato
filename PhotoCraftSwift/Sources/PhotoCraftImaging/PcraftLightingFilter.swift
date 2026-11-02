import Foundation
import PhotoCraftCore

enum PcraftLightingFilter {
  static let legacy=["lightType","lightX","lightY","lightZ","targetX","targetY","angle","elevation","color","intensity","cone","hotspot","radius"]
  static func convert(_ p:PcraftFilterParameters)throws->RasterFilter {
    var s=LightingSettings()
    let list=p.field("lights");let entries=try list?.array()
    if let list,let rows=entries,!rows.isEmpty {guard rows.count<=LightingSettings.maximumLights else{throw list.unsupported("Lighting Effects exceeds the native64-light budget.")}
      s.lights=try rows.map{try light($0)}
      for key in legacy{_ = p.field(key)} // The original list bypasses these fallback fields.
    }else{
      var l=LightingSettings.Light();l.kind=try p.choice("lightType",LightingSettings.Kind.spot)
      l.x=try p.number("lightX",0.25);l.y=try p.number("lightY",0.2);l.z=try p.number("lightZ",0.6,0...10)
      l.targetX=try p.number("targetX",0.5);l.targetY=try p.number("targetY",0.55);l.angle=try p.number("angle",135);l.elevation=try p.number("elevation",45,0...90)
      let c=try p.color("color",.white);l.color=[c.r,c.g,c.b];l.intensity=try p.number("intensity",75,-100...100);l.cone=try p.number("cone",45,1...89);l.hotspot=try p.number("hotspot",50,0...100);l.radius=try p.number("radius",0.8,0.01...10);s.lights=[l]
    }
    s.gloss=try p.number("gloss",0,-100...100);s.metallic=try p.number("metallic",0,-100...100);s.exposure=try p.number("exposure",0,-100...100);s.ambience=try p.number("ambience",8,-100...100);s.height=try p.number("height",50,0...100)
    let raw=try p.string("texture","none");s.texture=["none","red","green","blue","alpha","luminance"].contains(raw) ? LightingSettings.Texture(rawValue:raw)!:.none
    s.whiteIsHigh=try p.flag("whiteIsHigh",true);try s.validate();var f=RasterFilter(.lightingEffects);f.lighting=s;return f
  }
  static func light(_ node:PcraftNode)throws->LightingSettings.Light {
    let p=try PcraftFilterParameters(node);var l=LightingSettings.Light()
    let raw=try p.string("kind","spot");guard let kind=LightingSettings.Kind(rawValue:raw) else{throw node.unsupported("Unknown source Lighting Effects light type.")};l.kind=kind
    l.x=try p.number("x",0.25);l.y=try p.number("y",0.2);l.z=try p.number("z",0.6);l.targetX=try p.number("targetX",0.5);l.targetY=try p.number("targetY",0.55);l.angle=try p.number("angle",135);l.elevation=try p.number("elevation",45,0...90)
    if let color=p.field("color"){let a=try color.array();guard a.count==3 else{throw color.invalid};l.color=try a.map{try $0.float()}}
    l.intensity=try p.number("intensity",75,-100...100);l.cone=try p.number("cone",45,1...89);l.hotspot=try p.number("hotspot",50,0...100);l.radius=try p.number("radius",0.8);try p.finish();try l.validate();return l
  }
}
