import Foundation

/// Inert original file/session hints. They never authorize filesystem or document access.
public struct SourceDisplacementReference:Codable,Equatable,Sendable {
  public var path:String?
  public var documentName:String?
  public var documentIndex:UInt64?
  public var layerID:UInt64?
  public init(){}
  public var label:String {path.flatMap{$0.isEmpty ? nil:$0} ?? documentName ?? documentIndex.map{"Original document \($0)"} ?? "Map pixels were not stored"}
  public func validate()throws {
    guard path.map({$0.utf8.count<=4096 && !$0.contains("\0")}) != false,documentName.map({$0.utf8.count<=4096 && !$0.contains("\0")}) != false,documentName==nil || documentIndex==nil else{throw CraftError.invalid("Invalid original displacement map reference.")}
  }
}
/// Two numerical Float32 channels, without alpha or 8-bit quantization.
public struct FloatDisplacementMap:Codable,Equatable,Sendable {
  public static let maximumPixels=DisplacementMap.maximumPixels
  public var width:Int
  public var height:Int
  public var channels:Int
  public var samples:Data
  public var name:String
  public init(width:Int,height:Int,channels:Int,samples:Data,name:String="Displacement Map"){self.width=width;self.height=height;self.channels=channels;self.samples=samples;self.name=name}
  public func validate()throws {
    guard width>0,height>0,width<=Self.maximumPixels/height,(1...2).contains(channels),samples.count==width*height*channels*4,name.utf8.count<=256 else{throw CraftError.invalid("Invalid Float32 displacement map dimensions or bytes.")}
    guard values.allSatisfy(\.isFinite) else{throw CraftError.invalid("Displacement map samples must be finite.")}
  }
  public var values:[Float] {samples.withUnsafeBytes{b in (0..<(b.count/4)).map{Float(bitPattern:UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}}}
  public static func read(_ pixels:Surface,name:String)throws->Self {
    guard pixels.width<=maximumPixels/pixels.height else{throw CraftError.unsupported("Displacement maps retain their1,048,576-pixel preparation limit.")}
    let numeric=try pixels.interpretingSamples(as:.sRGB)
    var values=[SIMD2<Float>]();values.reserveCapacity(pixels.width*pixels.height);var mono=true
    for y in 0..<pixels.height {try Task.checkCancellation();for x in 0..<pixels.width {let p=numeric.pixel(x:x,y:y);guard p.isFinite else{throw CraftError.invalid("Nonfinite displacement map.")};values.append(SIMD2(p.r,p.g));if p.r != p.g || p.r != p.b{mono=false}}}
    var data=Data();data.reserveCapacity(values.count*(mono ? 4:8))
    func append(_ value:Float){var bits=value.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}}
    for p in values{append(p.x);if !mono{append(p.y)}}
    let map=Self(width:pixels.width,height:pixels.height,channels:mono ? 1:2,samples:data,name:String(name.prefix(80)));try map.validate();return map
  }
}
/// The original Smart renderer has no retained map: unresolved stages are identity.
/// Native editing requires explicit rebinding; hints are never opened automatically.
public struct SourceDisplacement:Codable,Equatable,Sendable {
  public var reference=SourceDisplacementReference()
  public var map:FloatDisplacementMap?
  public init(){}
  public func validate()throws{try reference.validate();try map?.validate()}
  public var estimatedBytes:Int {(map?.samples.count ?? 0)+(reference.path?.utf8.count ?? 0)+(reference.documentName?.utf8.count ?? 0)+256}
  public static func decodeJSON(_ value:Any)throws->Self {
    guard let d=value as? [String:Any],Set(d.keys).isSubset(of:["reference","map"]) else{throw CraftError.invalid("Unknown source displacement fields.")}
    if let reference=d["reference"] {guard let fields=reference as? [String:Any],Set(fields.keys).isSubset(of:["path","documentName","documentIndex","layerID"]) else{throw CraftError.invalid("Unknown source map reference fields.")}}
    if let map=d["map"] {guard let fields=map as? [String:Any],Set(fields.keys).isSubset(of:["width","height","channels","samples","name"]),let samples=fields["samples"] as? String,samples.utf8.count<=11_184_812 else{throw CraftError.invalid("Invalid source map payload.")}}
    var complete=d;if complete["reference"]==nil{complete["reference"]=[String:Any]()}
    if var map=complete["map"] as? [String:Any],map["name"]==nil{map["name"]="Displacement Map";complete["map"]=map}
    let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:complete));try result.validate();return result
  }
  public static var apiSchema:[String:Any] {[
    "type":"object","additionalProperties":false,"properties":[
      "reference":["type":"object","additionalProperties":false,"properties":["path":["type":"string","maxLength":4096],"documentName":["type":"string","maxLength":4096],"documentIndex":["type":"integer","minimum":0],"layerID":["type":"integer","minimum":0]]],
      "map":["type":"object","additionalProperties":false,"required":["width","height","channels","samples"],"properties":["width":["type":"integer","minimum":1,"maximum":maximumMapPixels],"height":["type":"integer","minimum":1,"maximum":maximumMapPixels],"channels":["type":"integer","enum":[1,2]],"samples":["type":"string","contentEncoding":"base64","maxLength":11_184_812],"name":["type":"string","maxLength":256]],"description":"Row-major little-endian finite Float32 channels, red/horizontal then green/vertical; mono uses the first for both. Neutral0.5; no alpha. Product<=1048576. Native73/Actions28."]],
    "description":"Original-source Displace context. References are inert hints. Supply embedded Float32 map data to bind; unresolved original Smart stages preserve the original renderer's identity behavior. Ordinary native filter application requires a map. Mutually exclusive with legacy8-bit map data."]}
  static var maximumMapPixels:Int {FloatDisplacementMap.maximumPixels}
}

extension DistortionSettings {
  public var hasDisplacementMap:Bool {map != nil || source?.map != nil}
  public var requiresSourceDisplacementArchive:Bool {source != nil || edge == .transparent}
}
extension CraftDocument {
  var requiresSourceDisplacementArchive:Bool {
    func filters(_ stack:SmartFilterStack?)->Bool{stack?.filters.contains(where:{$0.filter.distortion?.requiresSourceDisplacementArchive == true}) == true}
    func payload(_ p:AnimationLayerPayload)->Bool{filters(p.smartFilters)}
    func layer(_ l:Layer)->Bool{filters(l.smartFilters) || l.videoKeyframes?.contains(where:{$0.content.map(payload) ?? false}) == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.payload.map(payload) ?? false})}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])};return false
  }
}
