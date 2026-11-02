import Foundation
import PhotoCraftCore

enum PcraftFilterBlurGallery {
  @inline(never) static func convert(_ command:String,_ p:PcraftFilterParameters)throws->RasterFilter {
    let name=String(command.split(separator:".").last ?? "")
    let mode:BlurGallerySettings.Mode = name=="fieldBlur" ? .field:name=="irisBlur" ? .iris:name=="spinBlur" ? .spin:name=="pathBlur" ? .path:.tiltShift
    var s=BlurGallerySettings();s.enabled=[mode]
    if mode == .path {
      if let values=p.field("paths"),!(try values.array()).isEmpty {
        s.paths=try values.array().map{node in
          let q=try PcraftFilterParameters(node);var path=BlurGallerySettings.MotionPath();path.curved=false
          path.points=try node.field("points").array().map{point in let a=try point.array();guard a.count==2 else{throw point.invalid};return try .init(Double(a[0].float()),Double(a[1].float()))};_ = q.field("points")
          path.speed=try q.number("speed",50);path.taper=try q.number("taper",0);try q.finish();return path
        }
      }else{var path=BlurGallerySettings.MotionPath();path.curved=false;path.points=try [.init(p.number("startX",0.2),p.number("startY",0.5)),.init(p.number("endX",0.8),p.number("endY",0.5))];path.speed=try p.number("speed",50,0...500);path.taper=try p.number("taper",0,0...100);s.paths=[path]}
    }else if mode != .tiltShift,let values=p.field("pins"),!(try values.array()).isEmpty {
      let pins=try values.array().map{try explicitPin($0,mode:mode)};s.setPins(pins,for:mode)
    }else {
      var pin=BlurGallerySettings.Pin();pin.x=try p.number("centerX",0.5);pin.y=try p.number("centerY",0.5)
      if mode == .tiltShift{pin.blur=try p.number("blur",15,0...500);pin.angle=try p.number("angle",0);pin.focus=try p.number("focus",0.1,0...2);pin.transition=try p.number("transition",0.15,0.001...2)}
      if mode == .field{pin.blur=try p.number("blur",15,0...500)}
      if mode == .iris || mode == .spin {
        pin.radiusX=max(0.001,try p.number("radiusX",mode == .spin ? 0.3:0.35));pin.radiusY=max(0.001,try p.number("radiusY",mode == .spin ? 0.3:0.25));pin.angle=try p.number("angle",0)
        if mode == .iris{pin.roundness=try p.number("roundness",0,0...100);pin.feather=try p.number("feather",0.5,0...0.99);pin.blur=try p.number("blur",15,0...500)}
        else{pin.blurAngle=try p.number("blurAngle",15,0...360);pin.feather=0.85}
      };s.setPins([pin],for:mode)
    }
    try s.validate();var f=RasterFilter(.blurGallery);f.gallery=s;return f
  }
  private static func explicitPin(_ node:PcraftNode,mode:BlurGallerySettings.Mode)throws->BlurGallerySettings.Pin {
    let keys=mode == .field ? "x y blur":mode == .iris ? "x y radius_x radius_y angle roundness feather blur":"x y radius_x radius_y angle blur_angle"
    try node.keys(keys);for key in keys.split(separator:" "){_ = try node.field(String(key))}
    var pin=BlurGallerySettings.Pin();pin.x=Double(try node.field("x").float());pin.y=Double(try node.field("y").float())
    if mode == .field || mode == .iris{pin.blur=Double(try node.field("blur").float())}
    if mode != .field{pin.radiusX=Double(try node.field("radius_x").float());pin.radiusY=Double(try node.field("radius_y").float());pin.angle=Double(try node.field("angle").float())}
    if mode == .iris{pin.roundness=Double(try node.field("roundness").float());pin.feather=Double(try node.field("feather").float())}
    if mode == .spin{pin.blurAngle=Double(try node.field("blur_angle").float());pin.feather=0.85}
    return pin
  }
}
