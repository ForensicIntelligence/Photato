import Foundation
import PhotoCraftCore

/// Strict translation of licensed PhotoCraft doc/effects.rs records. Unknown
/// fields fail the import; missing pattern hints remain inert until explicitly bound.
enum PcraftEffects {
  static func blend(_ node:PcraftNode)throws->BlendMode {
    let name=try node.string()
    guard let value=BlendMode.allCases.first(where:{$0.rawValue.replacingOccurrences(of:" ",with:"")==name}) else {throw node.unsupported("Unknown effect blend mode.")};return value
  }
  static func pair(_ node:PcraftNode)throws->[Float] {let a=try node.array();guard a.count==2 else{throw node.invalid};return try a.map{try $0.float()}}
  static func contour(_ node:PcraftNode)throws->EffectContour {
    if case .string("Linear")=node.value{return .init()}
    try node.keys("Custom");let c=try node.field("Custom");try c.keys("name points")
    let points=try c.field("points").array().map{p -> [Float] in try p.keys("input output");return [try p.field("input").float(),try p.field("output").float()]}
    let result=EffectContour(name:try c.field("name").string(),points:points);try result.validate();return result
  }
  static func gradient(_ node:PcraftNode)throws->EffectGradient {
    try node.keys("stops opacity_stops style angle scale reverse align offset")
    let stops=try node.field("stops").array().map{p -> EffectGradientStop in let a=try p.array();guard a.count==2 else{throw p.invalid};return EffectGradientStop(try a[0].float(),try PcraftFills.color(a[1]))}
    let opacity=try node.field("opacity_stops").array().map{try pair($0)}
    var placement=GradientPlacement();guard let style=GradientStyle(rawValue:try node.field("style").string()) else{throw node.unsupported("Unknown effect gradient geometry.")}
    placement.style=style;placement.angle=try node.field("angle").float();placement.scale=try node.field("scale").float();placement.reverse=try node.field("reverse").boolean();let offset=try pair(node.field("offset"));placement.offsetX=offset[0];placement.offsetY=offset[1]
    let result=EffectGradient(stops:stops,opacityStops:opacity,placement:placement,aligned:try node.field("align").boolean());try result.validate();return result
  }
  static func pattern(_ node:PcraftNode,patterns:[RasterPattern],placement:Bool)throws->EffectPattern {
    try node.keys(placement ? "name id scale angle link phase":"name id scale")
    let name=try node.field("name").string(),id=try node.field("id").string()
    func folded(_ value:String)->[UInt8] {value.utf8.map{(65...90).contains($0) ? $0+32:$0}}
    func display(_ value:String)->String {let s=String(value.reversed().drop(while:{$0=="\0"}).reversed());return s.hasPrefix("$$$/") ? String(s.split(separator:"=",maxSplits:1).last ?? Substring(s)):s}
    let bound=(!id.isEmpty ? patterns.first{$0.id==id}:nil) ?? patterns.first{$0.name==name} ?? (!name.isEmpty ? patterns.first{folded(display($0.name))==folded(display(name))}:nil)
    var result=EffectPattern(patternID:bound?.id,sourceName:name,sourceID:id,scale:try node.field("scale").float())
    if placement {result.angle=try node.optional("angle")?.float() ?? 0;result.linked=try node.optional("link")?.boolean() ?? true;if let phase=node.optional("phase"){let p=try pair(phase);result.phase=PathPoint(Double(p[0]),Double(p[1]))}}
    try result.validate();return result
  }
  static func paint(_ node:PcraftNode,effect:inout LayerEffect,advanced:inout LayerEffectAdvanced,patterns:[RasterPattern])throws {
    guard case .object(let fields)=node.value,fields.count==1,let key=fields.keys.first else{throw node.invalid};let body=try node.field(key)
    switch key {
    case "Color":effect.color=try PcraftFills.color(body);advanced.paint=EffectPaint(.color)
    case "Gradient":advanced.paint=EffectPaint(.gradient,gradient:try gradient(body))
    case "Pattern":advanced.paint=EffectPaint(.pattern,pattern:try pattern(body,patterns:patterns,placement:false))
    default:throw node.unsupported("Unknown effect paint.")
    }
  }
  static func common(_ node:PcraftNode,_ effect:inout LayerEffect)throws {
    try node.keys("enabled blend opacity");effect.enabled=try node.field("enabled").boolean();effect.blendMode=try blend(node.field("blend"));effect.opacity=try node.field("opacity").float()
  }
  static func effect(_ node:PcraftNode,patterns:[RasterPattern])throws->LayerEffect {
    guard case .object(let fields)=node.value,fields.count==1,let key=fields.keys.first else{throw node.invalid}
    let keys:[String:LayerEffect.Kind]=["DropShadow":.dropShadow,"InnerShadow":.innerShadow,"OuterGlow":.outerGlow,"InnerGlow":.innerGlow,"Stroke":.stroke,"ColorOverlay":.colorOverlay,"GradientOverlay":.gradientOverlay,"PatternOverlay":.patternOverlay,"Satin":.satin,"BevelEmboss":.bevelEmboss]
    guard let kind=keys[key]else{throw node.unsupported("Unknown layer effect.")};let body=try node.field(key);var e=LayerEffect(kind),a=LayerEffectAdvanced()
    if kind != .bevelEmboss {try common(body.field("common"),&e)}
    switch kind {
    case .dropShadow,.innerShadow:
      try body.keys("common color angle use_global_light distance spread size contour anti_alias noise knocks_out");e.color=try PcraftFills.color(body.field("color"));e.angle=Double(try body.field("angle").float());e.useGlobalLight=try body.field("use_global_light").boolean();e.distance=Double(try body.field("distance").float());e.spread=Double(try body.field("spread").float())*100;e.size=Double(try body.field("size").float());a.contour=try contour(body.field("contour"));a.antiAlias=try body.field("anti_alias").boolean();a.noise=try body.field("noise").float();a.knocksOut=try body.field("knocks_out").boolean()
    case .outerGlow,.innerGlow:
      try body.keys("common paint technique spread size contour anti_alias range jitter noise source");try paint(body.field("paint"),effect:&e,advanced:&a,patterns:patterns);let technique=try body.field("technique").string(),source=try body.field("source").string()
      guard ["Softer","Precise"].contains(technique),["Center","Edge"].contains(source) else{throw body.invalid};a.glowTechnique=technique=="Softer" ? .softer:.precise;a.glowSource=source=="Center" ? .center:.edge;e.spread=Double(try body.field("spread").float())*100;e.size=Double(try body.field("size").float());a.contour=try contour(body.field("contour"));a.antiAlias=try body.field("anti_alias").boolean();a.range=try body.field("range").float();a.jitter=try body.field("jitter").float();a.noise=try body.field("noise").float()
    case .stroke:
      try body.keys("common size position paint");e.size=Double(try body.field("size").float());guard let position=LayerEffect.StrokePosition(rawValue:try body.field("position").string().lowercased()) else{throw body.invalid};e.position=position;try paint(body.field("paint"),effect:&e,advanced:&a,patterns:patterns)
    case .colorOverlay:try body.keys("common color");e.color=try PcraftFills.color(body.field("color"))
    case .gradientOverlay:try body.keys("common gradient dither");var g=try gradient(body.field("gradient"));g.dither=try body.field("dither").boolean();a.paint=EffectPaint(.gradient,gradient:g)
    case .patternOverlay:try body.keys("common name id scale angle link phase")
      // The overlay shares its placement fields with Pattern paint, plus common.
      guard case .object(var object)=body.value else{throw body.invalid};object.removeValue(forKey:"common");a.paint=EffectPaint(.pattern,pattern:try pattern(PcraftNode(.object(object),path:body.path),patterns:patterns,placement:true))
    case .satin:
      try body.keys("common color angle distance size contour anti_alias invert");e.color=try PcraftFills.color(body.field("color"));e.angle=Double(try body.field("angle").float());e.distance=Double(try body.field("distance").float());e.size=Double(try body.field("size").float());a.contour=try contour(body.field("contour"));a.antiAlias=try body.field("anti_alias").boolean();a.satinInverted=try body.field("invert").boolean();e.useGlobalLight=false
    case .bevelEmboss:
      try body.keys("enabled style technique depth up size soften angle altitude use_global_light gloss_contour highlight highlight_color shadow shadow_color contour texture");e.enabled=try body.field("enabled").boolean();e.opacity=1
      let style=try body.field("style").string(),technique=try body.field("technique").string();guard let bs=LayerEffectAdvanced.BevelStyle.allCases.first(where:{$0.rawValue.lowercased()==style.lowercased()}),let bt=LayerEffectAdvanced.BevelTechnique.allCases.first(where:{$0.rawValue.lowercased()==technique.lowercased()})else{throw body.invalid};a.bevelStyle=bs;a.bevelTechnique=bt;e.depth=Double(try body.field("depth").float())*100;a.directionUp=try body.field("up").boolean();e.size=Double(try body.field("size").float());e.soften=Double(try body.field("soften").float());e.angle=Double(try body.field("angle").float());a.altitude=try body.field("altitude").float();e.useGlobalLight=try body.field("use_global_light").boolean();a.glossContour=try contour(body.field("gloss_contour"));var hi=LayerEffect(.colorOverlay),sh=hi;try common(body.field("highlight"),&hi);try common(body.field("shadow"),&sh);a.highlightBlendMode=hi.blendMode;a.shadowBlendMode=sh.blendMode;a.highlightEnabled=hi.enabled;a.shadowEnabled=sh.enabled;e.highlightOpacity=hi.opacity;e.shadowOpacity=sh.opacity;e.highlightColor=try PcraftFills.color(body.field("highlight_color"));e.shadowColor=try PcraftFills.color(body.field("shadow_color"))
      if let c=body.optional("contour"){try c.keys("contour range anti_alias");a.bevelContour=EffectBevelContour(contour:try contour(c.field("contour")),range:try c.field("range").float(),antiAlias:try c.field("anti_alias").boolean())}
      if let t=body.optional("texture") {
        try t.keys("name id scale depth invert link phase");guard case .object(var fields)=t.value else{throw t.invalid};fields.removeValue(forKey:"depth");fields.removeValue(forKey:"invert");let p=try pattern(PcraftNode(.object(fields),path:t.path),patterns:patterns,placement:true);a.texture=EffectBevelTexture(pattern:p,depth:try t.field("depth").float(),inverted:try t.field("invert").boolean())
      }
    }
    e.advanced=a;try e.validate();return e
  }
  static func read(_ node:PcraftNode,fillOpacity:Float,layer:Layer,document:CraftDocument,project:PcraftProject,budget:inout Int)throws->LayerStyle? {
    try node.keys("enabled items psd_raw reference");let items=try node.field("items").array();guard items.count<=32 else{throw node.unsupported("At most32 effects can currently be retained per layer.")}
    var style=LayerStyle(effects:try items.map{try effect($0,patterns:document.patterns ?? [])});style.fillOpacity=fillOpacity;style.enabled=try node.field("enabled").boolean();style.lightAngle=document.globalLight?.angle ?? 120;style.lightAltitude=document.globalLight?.altitude ?? 30
    if let p=node.optional("reference") {let values=try p.array();guard values.count==2 else{throw p.invalid};let point=try layer.coordinateTransform.inverted().point(values[0].double(),values[1].double());style.referenceOffset=PathPoint(point.x,point.y)}
    if let raw=node.optional("psd_raw") {let key=try raw.string();guard let bytes=project.blobs[key],bytes.count<=1024*1024,bytes.count<=budget else{throw raw.unsupported("Retained PSD effects data exceeds its1MiB/source budget.")};budget-=bytes.count;style.sourcePSDData=bytes}
    if case .adjustment=layer.content,!style.effects.isEmpty {throw node.unsupported("Effects on adjustment layers require a separate backdrop-aware style mapping.")}
    try style.validate(in:document)
    return style.effects.isEmpty && style.sourcePSDData==nil && style.referenceOffset==nil && fillOpacity==1 ? nil:style
  }
}
