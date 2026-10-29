import Foundation

public struct GalleryParameter:Sendable {
  public let key:String,minimum:Double,maximum:Double,defaultValue:Double,choices:[String],boolean:Bool
  public init(_ key:String,_ min:Double=0,_ max:Double=1,_ value:Double=0,choices:[String]=[],boolean:Bool=false){self.key=key;minimum=min;maximum=choices.isEmpty ? max:Double(choices.count-1);defaultValue=value;self.choices=choices;self.boolean=boolean}
  public var title:String{key.replacingOccurrences(of:"([a-z])([A-Z])",with:"$1 $2",options:.regularExpression).capitalized}
  public var schema:[String:Any]{["type":"integer","minimum":minimum,"maximum":maximum,"default":defaultValue]}
}
public struct GalleryEffect:Codable,Equatable,Sendable {
  public var filter:GalleryFilter
  public var visible=true
  public var values:[String:Double]=[:]
  public var foreground=Pixel.black,background=Pixel.white,glowColor=Pixel(0,0.62,1)
  public init(_ filter:GalleryFilter){self.filter=filter;values=Dictionary(uniqueKeysWithValues:filter.parameters.map{($0.key,$0.defaultValue)})}
  public func get(_ key:String)->Float{Float(values[key] ?? filter.parameters.first{$0.key==key}?.defaultValue ?? 0)}
  public func choice(_ key:String)->String{guard let p=filter.parameters.first(where:{$0.key==key}),!p.choices.isEmpty else{return ""};return p.choices[min(p.choices.count-1,max(0,Int(get(key))))]}
  public func flag(_ key:String)->Bool{get(key) != 0}
  public func validate()throws{
    guard values.count<=32,Set(values.keys).isSubset(of:Set(filter.parameters.map(\.key))) else{throw CraftError.invalid("Unknown Filter Gallery parameter.")}
    for p in filter.parameters{let value=values[p.key] ?? p.defaultValue;guard value.isFinite,value.rounded()==value,(p.minimum...p.maximum).contains(value) else{throw CraftError.invalid("Invalid \(p.title) for \(filter.title).")}}
    for color in [foreground,background,glowColor]{guard color.isFinite,[color.r,color.g,color.b,color.a].allSatisfy({(0...1).contains($0)}) else{throw CraftError.invalid("Gallery colors must be finite sRGB values in0...1.")}}
  }
}
public struct ArtisticGallerySettings:Codable,Equatable,Sendable {
  public var effects:[GalleryEffect]=[.init(.coloredPencil)]
  public init(){}
  public var isIdentity:Bool{!effects.contains(where: \.visible)}
  public func validate()throws{guard effects.count<=32 else{throw CraftError.invalid("Filter Gallery supports up to32 effects per stack.")};for effect in effects{try effect.validate()}}
  public static func decodeJSON(_ data:Data)throws->Self {
    guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(root.keys).isSubset(of:["effects"]) else{throw CraftError.invalid("Unknown Filter Gallery setting.")}
    guard let raw=root["effects"] else{return Self()}
    guard let entries=raw as? [[String:Any]],entries.count<=32 else{throw CraftError.invalid("Invalid Filter Gallery stack.")}
    var result=Self();result.effects=try entries.map{entry in
      guard Set(entry.keys).isSubset(of:["filter","visible","values","foreground","background","glowColor"]),let name=entry["filter"] as? String,let kind=GalleryFilter(rawValue:name) else{throw CraftError.invalid("Unknown Filter Gallery effect.")}
      var e=GalleryEffect(kind)
      if let v=entry["visible"]{guard let n=v as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else{throw CraftError.invalid("Effect visibility must be Boolean.")};e.visible=n.boolValue}
      if let v=entry["values"]{guard let fields=v as? [String:Any] else{throw CraftError.invalid("Invalid gallery controls.")};for(k,v)in fields{guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID() else{throw CraftError.invalid("Gallery values use numeric controls/choice indices.")};e.values[k]=n.doubleValue}}
      for key in ["foreground","background","glowColor"]{if let v=entry[key]{guard let color=v as? [String:Any],Set(color.keys)==["r","g","b","a"],color.values.allSatisfy({v in guard let n=v as? NSNumber else{return false};return CFGetTypeID(n) != CFBooleanGetTypeID()}) else{throw CraftError.invalid("Invalid gallery color.")};let decoded=try JSONDecoder().decode(Pixel.self,from:JSONSerialization.data(withJSONObject:color));if key=="foreground"{e.foreground=decoded}else if key=="background"{e.background=decoded}else{e.glowColor=decoded}}}
      try e.validate();return e
    };try result.validate();return result
  }
  public static var apiSchema:[String:Any]{
    let color:[String:Any]=["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,["type":"number","minimum":0,"maximum":1] as [String:Any])})]
    let options=GalleryFilter.allCases.map{kind->[String:Any] in ["type":"object","additionalProperties":false,"required":["filter"],"properties":["filter":["const":kind.rawValue],"visible":["type":"boolean","default":true],"values":["type":"object","additionalProperties":false,"properties":Dictionary(uniqueKeysWithValues:kind.parameters.map{($0.key,$0.schema)})],"foreground":color,"background":color,"glowColor":color]]}
    return ["type":"object","additionalProperties":false,"properties":["effects":["type":"array","maxItems":32,"items":["oneOf":options]]]]
  }
  public static var apiCapabilities:[String:Any]{["schema":apiSchema,"categories":GalleryFilter.categories,"filters":GalleryFilter.allCases.map{f in ["key":f.rawValue,"name":f.title,"category":f.category,"controls":f.parameters.map{p in ["key":p.key,"title":p.title,"minimum":p.minimum,"maximum":p.maximum,"default":p.defaultValue,"choices":p.choices,"boolean":p.boolean] as [String:Any]}] as [String:Any]},"stackOrder":"First array effect runs first (bottom to top in the native stack list). Hidden effects remain editable but do not render.","parameters":"Numeric integer controls; choice values are zero-based indices exposed in controls. Boolean controls use0/1. Colors are captured straight sRGB. Defaults come from the original PhotoCraft catalogue.","persistence":"Native36 retains Gallery Smart Filters; Actions8 records them. Editable PSD is unsupported until independently qualified.","limits":["effects":32,"pixels":8388608,"effectPixels":67108864],"qualification":"47 native Swift effects ported from original clean-room Rust approximations. Full Photoshop pixels, loaded texture files, advanced defaults and live/platform qualification remain open. RGB32 is processed in encoded sRGB then stored linearly; Gallery output is bounded0...1."]}
}
