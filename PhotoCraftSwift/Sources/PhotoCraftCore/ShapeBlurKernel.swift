import CoreGraphics
import Foundation

/// A value snapshot, not a preset ID: saved filters and Actions survive library edits.
public struct ShapeBlurKernel:Codable,Equatable,Sendable {
  public var name:String
  public var path:VectorPath
  public init(name:String,path:VectorPath)throws {
    self.name=name;self.path=path;try validate()
  }
  public func validate()throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=255,
      !path.inverted,!path.isEmpty else {throw CraftError.invalid("Choose a named, finite custom shape for Shape Blur.")}
    try path.validate()
    let filled=try VectorPathGeometry.filledPath(path),bounds=filled.boundingBoxOfPath
    guard !filled.isEmpty,!bounds.isNull,bounds.width>1e-9,bounds.height>1e-9 else {
      throw CraftError.invalid("The custom Shape Blur kernel has no filled area.")
    }
  }
  /// Preserve aspect ratio and center the filled bounds in the radius square.
  func scaledPath(radius:Double)throws->CGPath {
    try validate()
    let filled=try VectorPathGeometry.filledPath(path),bounds=filled.boundingBoxOfPath
    let scale=2*radius/max(bounds.width,bounds.height)
    var transform=CGAffineTransform(a:scale,b:0,c:0,d:scale,tx:-bounds.midX*scale,ty:-bounds.midY*scale)
    guard let result=filled.copy(using:&transform) else {throw CraftError.invalid("Cannot scale the custom Shape Blur kernel.")}
    return result
  }
  /// Pixel cells cover the whole odd-sized footprint. Keep fractional edge area.
  /// The observed Photoshop reference uses 32 coverage levels expanded to 8 bits.
  /// Core Graphics edge rounding still has a measured reference residual.
  func coverage(radius:Int)throws->[UInt8] {
    guard (5...1000).contains(radius) else {throw CraftError.invalid("Invalid custom Shape Blur radius.")}
    let side=2*radius+1
    let centered=try scaledPath(radius:Double(radius)+0.5)
    var placement=CGAffineTransform(translationX:Double(side)/2,y:Double(side)/2)
    guard let shape=centered.copy(using:&placement),let context=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue),let storage=context.data else {throw CraftError.invalid("Cannot prepare custom Shape Blur coverage.")}
    context.setAllowsAntialiasing(true);context.setShouldAntialias(true)
    context.translateBy(x:0,y:Double(side));context.scaleBy(x:1,y:-1)
    context.setFillColor(gray:1,alpha:1);context.addPath(shape);context.fillPath()
    let bytes=storage.assumingMemoryBound(to:UInt8.self)
    var result=[UInt8](repeating:0,count:side*side)
    for y in 0..<side {try Task.checkCancellation();for x in 0..<side {
      let level=bytes[y*side+x]>>3;result[y*side+x]=(level<<3)|(level>>2)
    }}
    guard result.contains(where:{$0>0}) else {throw CraftError.invalid("This custom shape has no coverage at the chosen radius. Increase Radius.")}
    return result
  }
  public func previewPath()throws->VectorPath {
    try validate();let bounds=try VectorPathGeometry.filledPath(path).boundingBoxOfPath
    let scale=1/max(bounds.width,bounds.height)
    return path.transformed(.translation(0.5,0.5) * .scale(scale,scale) * .translation(-bounds.midX,-bounds.midY))
  }
  public static var apiSchema:[String:Any] {
    func object(_ properties:[String:Any])->[String:Any] {["type":"object","additionalProperties":false,"required":Array(properties.keys).sorted(),"properties":properties]}
    let number:[String:Any]=["type":"number","minimum":-1_000_000,"maximum":1_000_000]
    let point=object(["x":number,"y":number])
    let knot=object(["anchor":point,"incoming":point,"outgoing":point,"smooth":["type":"boolean"]])
    let component=object(["knots":["type":"array","maxItems":4096,"items":knot],"closed":["type":"boolean"],"operation":["type":"string","enum":PathOperation.allCases.map(\.rawValue)]])
    let path=object(["components":["type":"array","minItems":1,"maxItems":256,"items":component],"fillRule":["type":"string","enum":PathFillRule.allCases.map(\.rawValue)],"inverted":["const":false,"type":"boolean"]])
    return object(["name":["type":"string","minLength":1,"maxLength":255],"path":path])
  }
  /// Codable alone accepts unknown keys; public API geometry is deliberately strict.
  static func validateAPI(_ value:Any)throws {
    func fields(_ value:Any,_ keys:Set<String>)throws->[String:Any] {
      guard let object=value as? [String:Any],Set(object.keys)==keys else {throw CraftError.invalid("Unknown or missing custom Shape Blur geometry field.")}
      return object
    }
    let kernel=try fields(value,["name","path"]),path=try fields(kernel["path"]!,["components","fillRule","inverted"])
    guard let parts=path["components"] as? [Any],parts.count<=256 else {throw CraftError.invalid("Invalid custom Shape Blur components.")}
    var total=0
    for raw in parts {
      let component=try fields(raw,["knots","closed","operation"])
      guard let knots=component["knots"] as? [Any] else {throw CraftError.invalid("Invalid custom Shape Blur knots.")}
      total+=knots.count;guard total<=VectorPath.maxKnots else {throw CraftError.invalid("Too many custom Shape Blur knots.")}
      for rawKnot in knots {
        let knot=try fields(rawKnot,["anchor","incoming","outgoing","smooth"])
        for key in ["anchor","incoming","outgoing"] {_ = try fields(knot[key]!,["x","y"])}
      }
    }
  }
}

extension CraftDocument {
  public var requiresShapeBlurKernelArchive:Bool {
    func filters(_ stack:SmartFilterStack?)->Bool {stack?.filters.contains{$0.filter.classicDetail?.kernel != nil} == true}
    func payload(_ value:AnimationLayerPayload)->Bool {filters(value.smartFilters)}
    func layer(_ value:Layer)->Bool {filters(value.smartFilters) || value.videoKeyframes?.contains{$0.content.map(payload) ?? false} == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains{$0.payload.map(payload) ?? false}}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let original=animation?.retainedVideoSource{retained.append(original)}
    while let original=retained.popLast(){if original.layers.contains(where:layer){return true};retained.append(contentsOf:original.timeline.retainedFrameSources ?? [])}
    return false
  }
}
