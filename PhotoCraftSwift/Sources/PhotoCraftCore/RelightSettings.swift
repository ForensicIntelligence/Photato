import Foundation

/// Photato photographic lighting, translated from PhotoCraft's licensed renderer.
/// This is a deterministic local filter, separate from generative Harmonize.
public struct RelightSettings:Codable,Equatable,Sendable {
  private struct Values:Codable,Equatable,Sendable {var angle=45.0,elevation=40.0,intensity=40.0,ambient=55.0,warmth=0.0,softness=25.0}
  private indirect enum Storage:Equatable,Sendable {case value(Values)}
  private var storage:Storage = .value(Values())
  private var values:Values {get{switch storage{case .value(let v):return v}}set{storage = .value(newValue)}}
  public init(from decoder:Decoder)throws{storage = .value(try Values(from:decoder))}
  public func encode(to encoder:Encoder)throws{try values.encode(to:encoder)}
  public var angle:Double {get{values.angle}set{var v=values;v.angle=newValue;values=v}}
  public var elevation:Double {get{values.elevation}set{var v=values;v.elevation=newValue;values=v}}
  public var intensity:Double {get{values.intensity}set{var v=values;v.intensity=newValue;values=v}}
  public var ambient:Double {get{values.ambient}set{var v=values;v.ambient=newValue;values=v}}
  public var warmth:Double {get{values.warmth}set{var v=values;v.warmth=newValue;values=v}}
  public var softness:Double {get{values.softness}set{var v=values;v.softness=newValue;values=v}}
  public init() {}
  public static let controls=[DetailControl("angle","Direction (degrees)",-180...180,45),DetailControl("elevation","Elevation (degrees)",0...90,40),DetailControl("intensity","Intensity (%)",0...100,40),DetailControl("ambient","Ambient (%)",0...100,55),DetailControl("warmth","Warmth",-100...100,0),DetailControl("softness","Softness (%)",1...100,25)]
  public var isIdentity:Bool {intensity==0}
  public func validate()throws {try DetailSettingsJSON.validate([angle,elevation,intensity,ambient,warmth,softness],Self.controls)}
  public static func decodeJSON(_ data:Data)throws->Self {
    let d=try DetailSettingsJSON.object(JSONSerialization.jsonObject(with:data),keys:Set(controls.map(\.key)));var s=Self()
    s.angle=try DetailSettingsJSON.number(d,"angle",s.angle);s.elevation=try DetailSettingsJSON.number(d,"elevation",s.elevation);s.intensity=try DetailSettingsJSON.number(d,"intensity",s.intensity);s.ambient=try DetailSettingsJSON.number(d,"ambient",s.ambient);s.warmth=try DetailSettingsJSON.number(d,"warmth",s.warmth);s.softness=try DetailSettingsJSON.number(d,"softness",s.softness);try s.validate();return s
  }
  public static var apiSchema:[String:Any] {DetailSettingsJSON.schema(DetailSettingsJSON.properties(controls))}
  public static var apiCapabilities:[String:Any] {[
    "schema":apiSchema,"scope":"Photato photographic lighting extension; source-derived Retinex/Lambertian renderer. This is not Adobe Harmonize, Firefly or a generative model.",
    "processing":"Native Swift local processing; encoded RGB8/16 and unclipped linear RGB32. Alpha and transparent hidden pixels are retained. Six source dialog controls.",
    "maximumLayerPixels":RasterFilterEngine.maximumPixels,"scratchTileSize":128,"maximumPreviewSide":192,"maximumGaussianSigma":96,"maximumScratchPixels":1_048_576,
    "persistence":"Native71 and Actions26 retain editable settings; older readers reject the new feature. Adobe descriptors and editable PSD/PSB remain unsupported.",
    "qualification":"Original-engine fixtures and native/API tests qualify bounded cases; full source/Photoshop pixels, capacity, performance and platform acceptance remain open."]}
}

extension CraftDocument {
  var requiresRelightArchive:Bool {
    func filters(_ stack:SmartFilterStack?)->Bool {stack?.filters.contains(where:{$0.filter.relight != nil}) == true}
    func payload(_ value:AnimationLayerPayload)->Bool {filters(value.smartFilters)}
    func layer(_ value:Layer)->Bool {filters(value.smartFilters) || value.videoKeyframes?.contains(where:{$0.content.map(payload) ?? false}) == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.payload.map(payload) ?? false})}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])};return false
  }
}
