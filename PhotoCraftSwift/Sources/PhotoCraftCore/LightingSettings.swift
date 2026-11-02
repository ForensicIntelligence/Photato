import Foundation

/// Native multi-light parameters translated from licensed PhotoCraft sources.
public struct LightingSettings:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable {case spot,point,infinite
    public var title:String{switch self{case .spot:"Spot";case .point:"Point";case .infinite:"Infinite"}}
  }
  public enum Texture:String,Codable,CaseIterable,Sendable {case none,red,green,blue,alpha,luminance,alphaChannel
    public var title:String{switch self{case .none:"None";case .red:"Red";case .green:"Green";case .blue:"Blue";case .alpha:"Layer Alpha";case .luminance:"Luminance";case .alphaChannel:"Saved Alpha Channel"}}
  }
  public struct Light:Codable,Equatable,Sendable {
    public var kind:Kind = .spot
    public var enabled=true
    public var color:[Float]=[1,1,1]
    public var x=0.25
    public var y=0.2
    public var z=0.6
    public var targetX=0.5
    public var targetY=0.55
    public var angle=135.0
    public var elevation=45.0
    public var intensity=75.0
    public var cone=45.0
    public var hotspot=50.0
    public var radius=0.8
    public init(kind:Kind = .spot){self.kind=kind}
    public func validate()throws {
      guard color.count==3,color.allSatisfy({$0.isFinite && (0...1).contains($0)}),[x,y,z,targetX,targetY,angle,radius].allSatisfy({$0.isFinite && Float($0).isFinite}) else{throw CraftError.invalid("Invalid Lighting Effects position or RGB light color.")}
      try DetailSettingsJSON.validate([elevation,intensity,cone,hotspot],Self.controls)
    }
    public static let controls=[DetailControl("elevation","Elevation (degrees)",0...90,45),DetailControl("intensity","Intensity (%)",-100...100,75),DetailControl("cone","Cone (degrees)",1...89,45),DetailControl("hotspot","Hotspot (%)",0...100,50)]
    static let positionKeys=["x","y","z","targetX","targetY","angle","radius"]
    static func decode(_ value:Any)throws->Self {
      let keys=Set(positionKeys+controls.map(\.key)+["kind","enabled","color"])
      let d=try DetailSettingsJSON.object(value,keys:keys)
      var full=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
      for (key,value) in d{full[key]=value}
      let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:full));try result.validate();return result
    }
    public static var apiSchema:[String:Any] {
      var properties=DetailSettingsJSON.properties(controls)
      for key in positionKeys{properties[key]=["type":"number"]}
      properties["kind"]=["type":"string","enum":Kind.allCases.map(\.rawValue),"default":"spot"]
      properties["enabled"]=["type":"boolean","default":true]
      properties["color"]=["type":"array","minItems":3,"maxItems":3,"items":["type":"number","minimum":0,"maximum":1],"default":[1,1,1]]
      return DetailSettingsJSON.schema(properties)
    }
  }
  public enum Preset:String,CaseIterable,Sendable {case standard,point,infinite,threeLights
    public var title:String{switch self{case .standard:"Default Spot";case .point:"Point";case .infinite:"Infinite";case .threeLights:"Three Lights"}}
    public var settings:LightingSettings {
      var s=LightingSettings()
      switch self {
      case .standard:break
      case .point:var l=Light(kind:.point);l.x=0.5;l.y=0.5;l.radius=1;s.lights=[l]
      case .infinite:var l=Light(kind:.infinite);l.angle=135;l.elevation=45;s.lights=[l]
      case .threeLights:var a=Light(),b=Light(kind:.point),c=Light(kind:.infinite);a.color=[1,0.8,0.6];b.x=0.8;b.y=0.4;b.color=[0.3,0.6,1];b.intensity=40;c.angle = -45;c.intensity=20;s.lights=[a,b,c]
      };return s
    }
  }
  public static let maximumLights=64
  public static let maximumPresetBytes=262_144
  private struct Values:Codable,Equatable,Sendable {
    var lights=[Light()]
    var gloss=0.0
    var metallic=0.0
    var exposure=0.0
    var ambience=8.0
    var height=50.0
    var texture:Texture = .none
    var textureChannelID:UUID?
    var whiteIsHigh=true
  }
  private indirect enum Storage:Equatable,Sendable {case value(Values)}
  private var storage:Storage = .value(Values())
  private var values:Values{get{switch storage{case .value(let v):return v}}set{storage = .value(newValue)}}
  public init(){}
  public init(from decoder:Decoder)throws{storage = .value(try Values(from:decoder))}
  public func encode(to encoder:Encoder)throws{try values.encode(to:encoder)}
  public var lights:[Light]{get{values.lights}set{var v=values;v.lights=newValue;values=v}}
  public var gloss:Double{get{values.gloss}set{var v=values;v.gloss=newValue;values=v}}
  public var metallic:Double{get{values.metallic}set{var v=values;v.metallic=newValue;values=v}}
  public var exposure:Double{get{values.exposure}set{var v=values;v.exposure=newValue;values=v}}
  public var ambience:Double{get{values.ambience}set{var v=values;v.ambience=newValue;values=v}}
  public var height:Double{get{values.height}set{var v=values;v.height=newValue;values=v}}
  public var texture:Texture{get{values.texture}set{var v=values;v.texture=newValue;values=v}}
  public var textureChannelID:UUID?{get{values.textureChannelID}set{var v=values;v.textureChannelID=newValue;values=v}}
  public var whiteIsHigh:Bool{get{values.whiteIsHigh}set{var v=values;v.whiteIsHigh=newValue;values=v}}
  public static let controls=[DetailControl("gloss","Gloss",-100...100,0),DetailControl("metallic","Metallic",-100...100,0),DetailControl("exposure","Exposure",-100...100,0),DetailControl("ambience","Ambience",-100...100,8),DetailControl("height","Texture Height",0...100,50)]
  public func validate()throws {
    try DetailSettingsJSON.validate([gloss,metallic,exposure,ambience,height],Self.controls)
    guard lights.count<=Self.maximumLights,(texture == .alphaChannel)==(textureChannelID != nil) else{throw CraftError.invalid("Lighting Effects supports up to64 lights; a saved alpha texture requires its channel identity.")}
    for light in lights{try light.validate()}
  }
  public func validateReferences(in document:CraftDocument)throws {
    try validate();if let id=textureChannelID,document.alphaChannels?.contains(where:{$0.id==id}) != true{throw CraftError.invalid("The Lighting Effects texture channel is missing.")}
  }
  public static func decodeJSON(_ data:Data)throws->Self {
    guard data.count<=maximumPresetBytes else{throw CraftError.invalid("Lighting preset exceeds256KiB.")}
    let d=try DetailSettingsJSON.object(JSONSerialization.jsonObject(with:data),keys:Set(controls.map(\.key)+["lights","texture","textureChannelID","whiteIsHigh"]))
    var s=Self()
    s.gloss=try DetailSettingsJSON.number(d,"gloss",s.gloss)
    s.metallic=try DetailSettingsJSON.number(d,"metallic",s.metallic)
    s.exposure=try DetailSettingsJSON.number(d,"exposure",s.exposure)
    s.ambience=try DetailSettingsJSON.number(d,"ambience",s.ambience)
    s.height=try DetailSettingsJSON.number(d,"height",s.height)
    if let value=d["lights"]{guard let array=value as? [Any],array.count<=maximumLights else{throw CraftError.invalid("Invalid Lighting Effects light list.")};s.lights=try array.map{try Light.decode($0)}}
    if let value=d["texture"]{guard let raw=value as? String,let texture=Texture(rawValue:raw) else{throw CraftError.invalid("Unknown lighting texture.")};s.texture=texture}
    if let value=d["textureChannelID"]{guard let raw=value as? String,let id=UUID(uuidString:raw) else{throw CraftError.invalid("Invalid texture channel identity.")};s.textureChannelID=id}
    if let value=d["whiteIsHigh"]{guard CFGetTypeID(value as CFTypeRef)==CFBooleanGetTypeID(),let flag=value as? Bool else{throw CraftError.invalid("White Is High requires a boolean.")};s.whiteIsHigh=flag}
    try s.validate();return s
  }
  public func presetData()throws->Data {try validate();let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];let data=try encoder.encode(self);guard data.count<=Self.maximumPresetBytes else{throw CraftError.invalid("Lighting preset exceeds256KiB.")};return data}
  public static var apiSchema:[String:Any] {
    var p=DetailSettingsJSON.properties(controls);p["lights"]=["type":"array","maxItems":maximumLights,"items":Light.apiSchema]
    p["texture"]=["type":"string","enum":Texture.allCases.map(\.rawValue),"default":"none"];p["textureChannelID"]=["type":"string","format":"uuid"];p["whiteIsHigh"]=["type":"boolean","default":true];return DetailSettingsJSON.schema(p)
  }
  public static var apiCapabilities:[String:Any] {[
    "schema":apiSchema,"maximumLights":maximumLights,"lightTypes":Kind.allCases.map(\.rawValue),"textures":Texture.allCases.map(\.rawValue),
    "builtInPresets":Preset.allCases.map{["id":$0.rawValue,"title":$0.title,"settings":(try? JSONSerialization.jsonObject(with:$0.settings.presetData())) ?? NSNull()] as [String:Any]},
    "presetJSON":["mediaType":"application/json","maximumBytes":maximumPresetBytes,"schema":apiSchema,"usage":"Load/Save use this same settings object; API clients apply it through filter.apply or smartFilter.set."],
    "processing":"Native Swift source-derived Blinn–Phong lighting; RGB8/16 encoded and RGB32 linear samples. Negative lights, bump normals and HDR output. Saved alpha texture is a Photato extension.",
    "savedAlphaReferences":"textureChannelID identifies the current document channel. Missing references reject atomically; preset/Action portability across unrelated channel identities remains unqualified.",
    "maximumLayerPixels":RasterFilterEngine.maximumPixels,"maximumPreviewSide":192,
    "persistence":"Native72 and Actions27. Adobe descriptors and editable PSD/PSB are unqualified and reject.",
    "reference":"Historical Lighting Effects/source workflow exposed in Photato's submenu. Current factory menu placement and Photoshop kernels remain unqualified.",
    "qualification":"Independent original-engine fixtures and native/API tests are required; full capacity/performance/native/platform/Photoshop acceptance remains open."
  ]}
}

extension CraftDocument {
  var requiresLightingArchive:Bool {
    func filters(_ stack:SmartFilterStack?)->Bool{stack?.filters.contains(where:{$0.filter.lighting != nil}) == true}
    func payload(_ p:AnimationLayerPayload)->Bool{filters(p.smartFilters)}
    func layer(_ l:Layer)->Bool{filters(l.smartFilters) || l.videoKeyframes?.contains(where:{$0.content.map(payload) ?? false}) == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.payload.map(payload) ?? false})}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])};return false
  }
}
