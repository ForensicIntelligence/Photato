import Foundation
import PhotoCraftCore

/// Strict source schema translation; control values remain Float32, including
/// normalized tone points and channel coefficients. Original hints grant no IO.
enum PcraftAdjustments {
  static func read(_ node:PcraftNode)throws->SourceAdjustment {
    if node.value.string=="Invert" {return SourceAdjustment(.invert)}
    guard case .object(let fields)=node.value,fields.count==1,let key=fields.keys.first else {throw node.invalid}
    let n=try node.field(key)
    func vector(_ node:PcraftNode,_ count:Int)throws->[Float] {let a=try node.array();guard a.count==count else {throw node.invalid};return try a.map{try $0.float()}}
    func matrix(_ node:PcraftNode,_ rows:Int,_ columns:Int)throws->[[Float]] {let a=try node.array();guard a.count==rows else {throw node.invalid};return try a.map{try vector($0,columns)}}
    func parameter(_ keys:String)throws->[String:Float] {var r=[String:Float]();for k in keys.split(separator:" ").map(String.init){r[k]=try n.field(k).float()};return r}
    func option(_ key:String,_ fallback:Bool?=nil)throws->Bool {if let field=n.optional(key){return try field.boolean()};if let fallback{return fallback};throw n.invalid}
    func toneSpace()throws->SourceAdjustment.ToneSpace {let name=try n.optional("space")?.string() ?? "Rgb";guard let value=SourceAdjustment.ToneSpace(rawValue:name.lowercased()) else {throw n.invalid};return value}
    let result:SourceAdjustment
    switch key {
    case "BrightnessContrast":
      try n.keys("brightness contrast legacy");result = .init(.brightnessContrast,parameters:try parameter("brightness contrast"),options:["legacy":try option("legacy")])
    case "Levels":
      try n.keys("master per_channel space black")
      func channel(_ c:PcraftNode)throws->[Float] {try c.keys("in_black in_white gamma out_black out_white");return try ["in_black","in_white","gamma","out_black","out_white"].map{try c.field($0).float()}}
      let components=try n.field("per_channel").array();guard components.count==3 else {throw n.invalid}
      var channels=[try channel(n.field("master"))];channels += try components.map(channel);channels.append(try n.optional("black").map(channel) ?? [0,1,1,0,1])
      result = .init(.levels,records:["channels":channels],space:try toneSpace())
    case "Curves":
      try n.keys("master per_channel space black")
      func curve(_ c:PcraftNode)throws->[[Float]] {let points=try c.array();guard points.count<=256 else {throw c.invalid};return try points.map{p in try p.keys("input output");return try [p.field("input").float(),p.field("output").float()]}}
      let components=try n.field("per_channel").array();guard components.count==3 else {throw n.invalid}
      result = .init(.curves,records:["master":try curve(n.field("master")),"red":try curve(components[0]),"green":try curve(components[1]),"blue":try curve(components[2]),"black":try n.optional("black").map(curve) ?? []],space:try toneSpace())
    case "Exposure":try n.keys("exposure offset gamma");result = .init(.exposure,parameters:try parameter("exposure offset gamma"))
    case "Vibrance":try n.keys("vibrance saturation");result = .init(.vibrance,parameters:try parameter("vibrance saturation"))
    case "HueSaturation":
      try n.keys("hue saturation lightness colorize ranges")
      let ranges:[[Float]]
      if let rows=n.optional("ranges") {
        let a=try rows.array();guard a.count==6 else {throw rows.invalid}
        ranges=try a.map{r in try r.keys("hue saturation lightness bounds");return try [r.field("hue").float(),r.field("saturation").float(),r.field("lightness").float()]+vector(r.field("bounds"),4)}
      } else {ranges=(0..<6).map{i in let c=Float(i)*60;return [0,0,0,c-45,c-15,c+15,c+45]}}
      result = .init(.hueSaturation,parameters:try parameter("hue saturation lightness"),records:["ranges":ranges],options:["colorize":try option("colorize")])
    case "ColorBalance":
      try n.keys("shadows midtones highlights preserve_luminosity");var rows=[String:[[Float]]]();for key in ["shadows","midtones","highlights"]{rows[key]=[try vector(n.field(key),3)]}
      result = .init(.colorBalance,records:rows,options:["preserveLuminosity":try option("preserve_luminosity")])
    case "BlackWhite":
      try n.keys("weights tint");var rows=["weights":[try vector(n.field("weights"),6)]];if let tint=n.optional("tint"){rows["tint"]=[try vector(tint,3)]};result = .init(.blackWhite,records:rows)
    case "PhotoFilter":try n.keys("color density preserve_luminosity");result = .init(.photoFilter,parameters:try parameter("density"),records:["color":[try vector(n.field("color"),3)]],options:["preserveLuminosity":try option("preserve_luminosity")])
    case "ChannelMixer":try n.keys("matrix monochrome");result = .init(.channelMixer,records:["matrix":try matrix(n.field("matrix"),3,4)],options:["monochrome":try option("monochrome")])
    case "ColorLookup":
      try n.keys("name lut size tetrahedral dither");let size=try n.field("size").integer();guard (0...ColorLUT.maximumSize).contains(size) else {throw n.invalid};var rows=[String:[[Float]]]()
      if let table=n.optional("lut"){guard size>=2 else {throw table.invalid};rows["lut"]=[try vector(table,size*size*size*3)]}
      result = .init(.colorLookup,parameters:["size":Float(size)],records:rows,options:["tetrahedral":try option("tetrahedral",false),"dither":try option("dither",false)],name:try n.field("name").string())
    case "Posterize":try n.keys("levels");let count=try n.field("levels").unsigned();guard (2...255).contains(count) else {throw n.invalid};result = .init(.posterize,parameters:["levels":Float(count)])
    case "Threshold":try n.keys("level");result = .init(.threshold,parameters:try parameter("level"))
    case "GradientMap":
      try n.keys("stops reverse dither");let stops=try n.field("stops").array();guard stops.count<=4096 else {throw n.invalid}
      let rows=try stops.map{s in let a=try s.array();guard a.count==2 else {throw s.invalid};return try [a[0].float()]+vector(a[1],3)}
      result = .init(.gradientMap,records:["stops":rows],options:["reverse":try option("reverse"),"dither":try option("dither",false)])
    case "SelectiveColor":try n.keys("relative adjustments");result = .init(.selectiveColor,records:["adjustments":try matrix(n.field("adjustments"),9,4)],options:["relative":try option("relative")])
    case "Unsupported":
      try n.keys("psd_key raw");let bytes=try n.field("raw").array();guard bytes.count<=SourceAdjustment.maximumOpaqueBytes else {throw n.invalid}
      let raw=try bytes.map{p -> UInt8 in guard let x=UInt8(exactly:try p.unsigned()) else {throw p.invalid};return x}
      result = .init(.unsupported,opaqueKey:try n.field("psd_key").string(),opaqueData:Data(raw))
    default:throw node.unsupported("Unknown original adjustment '\(key)'.")
    }
    try result.validate();return result
  }
}
