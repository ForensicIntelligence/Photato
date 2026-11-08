import Foundation

/// Immutable height samples, independent of a file URL or mutable library entry.
public struct GalleryTextureSource: Codable, Equatable, Sendable {
  public static let maximumPixels = 8_388_608
  public static let maximumBase64 = ((maximumPixels + 2) / 3) * 4
  public let name: String
  public let width: Int
  public let height: Int
  public let samples: Data
  public init(name: String, width: Int, height: Int, samples: Data) throws {
    self.name=name; self.width=width; self.height=height; self.samples=Data(samples)
    try validate()
  }
  public static func supports(_ filter: GalleryFilter) -> Bool {
    [.roughPastels, .underpainting, .glass, .conteCrayon, .texturizer].contains(filter)
  }
  public func validate() throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.utf8.count<=256,
      !name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),
      (1...300_000).contains(width), (1...300_000).contains(height),
      width<=Self.maximumPixels/height, samples.count==width*height
    else { throw CraftError.invalid("Invalid custom texture name, dimensions or samples (maximum 8 MP).") }
  }
  private enum Keys: String, CodingKey { case name, width, height, samples }
  private struct AnyKey: CodingKey {
    var stringValue:String; var intValue:Int? {nil}
    init?(stringValue:String){self.stringValue=stringValue}
    init?(intValue:Int){return nil}
  }
  public init(from decoder:any Decoder) throws {
    let keys=try decoder.container(keyedBy:AnyKey.self)
    guard Set(keys.allKeys.map(\.stringValue))==["name","width","height","samples"] else {throw CraftError.invalid("Unknown or missing custom texture field.")}
    let c=try decoder.container(keyedBy:Keys.self)
    name=try c.decode(String.self,forKey:.name); width=try c.decode(Int.self,forKey:.width); height=try c.decode(Int.self,forKey:.height)
    guard (1...300_000).contains(width),(1...300_000).contains(height),width<=Self.maximumPixels/height else {throw CraftError.invalid("Custom texture exceeds 8 MP.")}
    let text=try c.decode(String.self,forKey:.samples)
    guard text.utf8.count<=Self.maximumBase64,let bytes=Data(base64Encoded:text),bytes.count==width*height,bytes.base64EncodedString()==text else {throw CraftError.invalid("Custom texture requires canonical base64 height samples.")}
    samples=bytes;try validate()
  }
  public func encode(to encoder:any Encoder) throws {
    try validate();var c=encoder.container(keyedBy:Keys.self)
    try c.encode(name,forKey:.name);try c.encode(width,forKey:.width);try c.encode(height,forKey:.height);try c.encode(samples.base64EncodedString(),forKey:.samples)
  }
  /// Pixel centers are at integer coordinates; bilinear samples repeat in both axes.
  public func sample(x:Float,y:Float,scale:Float=1)->Float {
    guard x.isFinite,y.isFinite,scale.isFinite,(0.5...2).contains(scale),abs(x)<=1e9,abs(y)<=1e9 else {return 0}
    let u=x/scale,v=y/scale,ix=Int(floor(u)),iy=Int(floor(v)),fx=u-Float(ix),fy=v-Float(iy)
    func at(_ x:Int,_ y:Int)->Float {Float(samples[((y%height+height)%height)*width+(x%width+width)%width])/255}
    let a=at(ix,iy),b=at(ix,iy+1)
    let top=a+(at(ix+1,iy)-a)*fx,bottom=b+(at(ix+1,iy+1)-b)*fx
    return top+(bottom-top)*fy
  }
  public static var apiSchema:[String:Any] {
    ["type":"object","additionalProperties":false,"required":["name","width","height","samples"],"properties":["name":["type":"string","minLength":1,"maxLength":256],"width":["type":"integer","minimum":1,"maximum":300000],"height":["type":"integer","minimum":1,"maximum":300000],"samples":["type":"string","contentEncoding":"base64","minLength":4,"maxLength":maximumBase64]]]
  }
}

extension CraftDocument {
  public var requiresGalleryTextureArchive:Bool {
    func filters(_ s:SmartFilterStack?)->Bool {s?.filters.contains{$0.filter.artistic?.effects.contains{$0.texture != nil} == true} == true}
    func payload(_ p:AnimationLayerPayload)->Bool {filters(p.smartFilters)}
    func layer(_ l:Layer)->Bool {filters(l.smartFilters) || l.videoKeyframes?.contains{$0.content.map(payload) ?? false} == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains{$0.payload.map(payload) ?? false}}) == true {return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let original=animation?.retainedVideoSource{retained.append(original)}
    while let original=retained.popLast(){if original.layers.contains(where:layer){return true};retained.append(contentsOf:original.timeline.retainedFrameSources ?? [])}
    return false
  }
}
