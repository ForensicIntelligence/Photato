import Foundation

public struct ContentAwareSettings: Codable, Equatable, Sendable {
  public enum Sampling: String, Codable, CaseIterable, Sendable { case auto, rectangular, custom }
  public enum ColorAdaptation: String, Codable, CaseIterable, Sendable { case none, `default`, high, veryHigh
    public var amount: Float { switch self { case .none:0; case .default:0.35; case .high:0.65; case .veryHigh:0.9 } }
  }
  public enum Rotation: String, Codable, CaseIterable, Sendable { case none, low, medium, high, full
    public var angles: [Double] { switch self { case .none:[]; case .low:[-10,10]; case .medium:[-20,20]; case .high:[-35,35]; case .full:[90,180,270] } }
  }
  public var sampling: Sampling = .auto
  public var colorAdaptation: ColorAdaptation = .default
  public var rotation: Rotation = .none
  public var scale = false
  public var mirror = false
  public var sampleAllLayers = false
  public var margin = 64
  public var seed: UInt32 = 1
  public init() {}
  public func validate() throws { guard (0...100_000).contains(margin) else { throw CraftError.invalid("Sampling margin must be 0–100000 pixels.") } }
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard let raw = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CraftError.invalid("Expected content-aware settings object.") }
    var base = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    guard Set(raw.keys).isSubset(of:Set(base.keys)) else { throw CraftError.invalid("Unknown Content-Aware Fill setting.") }
    for (k,v) in raw { base[k] = v }
    let value = try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:base)); try value.validate(); return value
  }
}
public enum ContentAwareOutput: String, Codable, CaseIterable, Sendable { case current, new, duplicate
  public var title: String { switch self { case .current:"Current Layer"; case .new:"New Layer"; case .duplicate:"Duplicate Layer" } }
}
public struct ContentAwareStroke: Codable, Equatable, Sendable {
  public enum Target: String, Codable, CaseIterable, Sendable { case sampling, selection }
  public enum Kind: String, Codable, CaseIterable, Sendable { case brush, lasso }
  public var target: Target = .sampling
  public var kind: Kind = .brush
  public var add = false
  public var size: Double = 30
  public var points: [[Double]] = []
  public init() {}
  public func validate() throws {
    guard size.isFinite, (1...5000).contains(size), !points.isEmpty, points.count <= 4096,
      points.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } }) else { throw CraftError.invalid("Invalid sampling/selection stroke.") }
  }
  public func applying(to mask: SelectionMask) throws -> SelectionMask {
    try validate(); let w = mask.width, h = mask.height
    var bytes = mask.bytes
    if kind == .lasso {
      let shape = try SelectionMask.make(.polygon(points.map { SelectionPoint($0[0],$0[1]) }),width:w,height:h,antiAlias:true)
      for y in 0..<h { try Task.checkCancellation(); for x in 0..<w { let i = y*w+x; bytes[i] = add ? max(bytes[i],shape.bytes[i]):min(bytes[i],255-shape.bytes[i]) } }
    } else {
      var visits = 0; let r = size/2
      for j in points.indices {
        let a = points[max(0,j-1)], b = points[j], dx = b[0]-a[0], dy = b[1]-a[1], length = dx*dx+dy*dy
        let x0 = max(0,min(w,Int(floor(min(a[0],b[0])-r)))), x1 = max(0,min(w,Int(ceil(max(a[0],b[0])+r))))
        let y0 = max(0,min(h,Int(floor(min(a[1],b[1])-r)))), y1 = max(0,min(h,Int(ceil(max(a[1],b[1])+r))))
        visits += (x1-x0)*(y1-y0); guard visits <= 100_000_000 else { throw CraftError.invalid("Sampling stroke is too large.") }
        for y in y0..<y1 { try Task.checkCancellation(); for x in x0..<x1 {
          let px = Double(x)+0.5-a[0], py = Double(y)+0.5-a[1], t = length == 0 ? 0:min(1,max(0,(px*dx+py*dy)/length))
          if hypot(px-t*dx,py-t*dy) <= r { bytes[y*w+x] = add ? 255:0 }
        } }
      }
    }
    return try SelectionMask(width:w,height:h,bytes:bytes)
  }
}
