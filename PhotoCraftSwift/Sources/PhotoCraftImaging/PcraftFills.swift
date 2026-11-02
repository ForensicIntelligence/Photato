import Foundation
import PhotoCraftCore

/// Translates licensed PhotoCraft Fill data to the existing editable native models.
/// Source controls that the current models cannot retain reject the whole import.
enum PcraftFills {
  static func color(_ node:PcraftNode)throws->Pixel {
    try node.keys("mode c alpha")
    let mode=try node.field("mode").string(),components=try node.field("c").array().map{try $0.float()}
    guard components.count==4 else{throw node.invalid}
    let alpha=try node.field("alpha").float();guard (0...1).contains(alpha)else{throw node.invalid}
    switch mode {
    case "Rgb":
      guard components[3]==0 else{throw node.unsupported("Unused RGB color components must be zero.")}
      return Pixel(components[0],components[1],components[2],alpha)
    case "Grayscale":
      guard components.dropFirst().allSatisfy({$0==0})else{throw node.unsupported("Unused grayscale components must be zero.")}
      return Pixel(components[0],components[0],components[0],alpha)
    default:throw node.unsupported("This fill color model needs a source color-management mapping.")
    }
  }
  static func content(_ node:PcraftNode,patterns:[RasterPattern])throws->LayerContent {
    guard case .object(let fields)=node.value,fields.count==1,let key=fields.keys.first else{throw node.invalid}
    let body=try node.field(key)
    switch key {
    case "Solid":return .fill(try color(body))
    case "Gradient":return .gradientFill(try gradient(body))
    case "Pattern":return .patternFill(try pattern(body,patterns:patterns))
    default:throw node.unsupported("Unknown fill kind '\(key)'.")
    }
  }
  static func gradient(_ node:PcraftNode)throws->GradientFill {
    try node.keys("stops angle scale style reverse opacity_stops midpoints offset dither align")
    let input=try node.field("stops").array()
    guard !input.isEmpty,input.count<=GradientDefinition.maxStops else{throw node.unsupported("The gradient stop count is not representable.")}
    let colors=try input.map{item -> (Float,Pixel) in
      let pair=try item.array();guard pair.count==2 else{throw item.invalid}
      return(try pair[0].float(),try color(pair[1]))
    }.sorted{$0.0<$1.0}
    let mids=try node.optional("midpoints")?.array().map{try $0.float()} ?? []
    guard mids.count<colors.count else{throw node.unsupported("Unused gradient midpoints cannot be discarded.")}
    var stops:[GradientColorStop]=[],alpha:[GradientOpacityStop]=[]
    for (i,entry)in colors.enumerated() {
      let midpoint=i>0 && i-1<mids.count ? mids[i-1]:0.5
      stops.append(.init(entry.0,.rgb(Pixel(entry.1.r,entry.1.g,entry.1.b)),midpoint:midpoint))
      alpha.append(.init(entry.0,entry.1.a,midpoint:midpoint))
    }
    let opacity=try (node.optional("opacity_stops")?.array() ?? []).map{item -> GradientOpacityStop in
      let pair=try item.array();guard pair.count==2 else{throw item.invalid}
      return .init(try pair[0].float(),try pair[1].float())
    }
    guard opacity.isEmpty || colors.allSatisfy({$0.1.a==1}) else {
      throw node.unsupported("Independent color alpha and opacity curves require a native dual-alpha gradient model.")
    }
    var placement=GradientPlacement()
    let style=try node.field("style").string();guard let native=GradientStyle(rawValue:style)else{throw node.unsupported("Unknown gradient style.")}
    placement.style=native;placement.angle=try node.field("angle").float();placement.scale=try node.field("scale").float();placement.reverse=try node.field("reverse").boolean()
    if let offset=node.optional("offset") {let pair=try offset.array();guard pair.count==2 else{throw offset.invalid};placement.offsetX=try pair[0].float();placement.offsetY=try pair[1].float()}
    // Rust fill ramps use piecewise linear encoded RGB, independently of tool ramps.
    let definition=GradientDefinition(name:"Imported PhotoCraft gradient",colors:stops,
      opacity:opacity.isEmpty ? (colors.allSatisfy{$0.1.a==1} ? []:alpha):opacity,
      smoothness:0,method:.classic)
    let fill=GradientFill(gradient:definition,placement:placement,aligned:try node.optional("align")?.boolean() ?? true,dither:try node.optional("dither")?.boolean() ?? false)
    try fill.validate();return fill
  }
  static func pattern(_ node:PcraftNode,patterns:[RasterPattern])throws->PatternFill {
    try node.keys("name scale id angle link phase")
    let name=try node.field("name").string(),id=try node.optional("id")?.string() ?? ""
    let selected=(!id.isEmpty ? patterns.first{$0.id==id}:nil) ?? patterns.first{$0.name==name}
      ?? (!name.isEmpty ? patterns.first{ascii(display($0.name))==ascii(display(name))}:nil)
    guard let selected else{throw node.unsupported("The source pattern cannot be resolved without substituting artwork.")}
    var placement=PatternPlacement();placement.scale=try node.field("scale").float()*100;placement.angle=try node.optional("angle")?.float() ?? 0
    if let phase=node.optional("phase") {let pair=try phase.array();guard pair.count==2 else{throw phase.invalid};placement.phaseX=try pair[0].float();placement.phaseY=try pair[1].float()}
    let fill=PatternFill(patternID:selected.id,placement:placement,linked:try node.optional("link")?.boolean() ?? true)
    try fill.validate();return fill
  }
  private static func display(_ name:String)->String {
    let text=String(name.reversed().drop(while:{$0=="\0"}).reversed())
    return text.hasPrefix("$$$/") ? String(text.split(separator:"=",maxSplits:1).last ?? Substring(text)):text
  }
  private static func ascii(_ name:String)->[UInt8] {name.utf8.map{(65...90).contains($0) ? $0+32:$0}}
}
