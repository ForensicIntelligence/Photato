import Foundation

/// Native Select and Mask parameters, translated from PhotoCraft matting.rs.
public struct SelectionRefinement: Codable, Equatable, Sendable {
  public var radius: Double = 0
  public var smartRadius = false
  public var smooth: Double = 0
  public var feather: Double = 0
  public var contrast: Double = 0
  public var shiftEdge: Double = 0
  public var decontaminate = false
  public var amount: Double = 100
  public init() {}
  public var neutral: Bool { radius == 0 && smooth == 0 && feather == 0 && contrast == 0 && shiftEdge == 0 }
  public func validate() throws {
    guard radius.isFinite, (0...250).contains(radius), feather.isFinite, (0...1000).contains(feather),
      [smooth,contrast,amount].allSatisfy({ $0.isFinite && (0...100).contains($0) }),
      shiftEdge.isFinite, (-100...100).contains(shiftEdge) else { throw CraftError.invalid("Invalid Select and Mask refinement parameters.") }
  }
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard let raw = try JSONSerialization.jsonObject(with:data) as? [String:Any],
      Set(raw.keys).isSubset(of:["radius","smartRadius","smooth","feather","contrast","shiftEdge","decontaminate","amount"]) else { throw CraftError.invalid("Unknown refinement parameter.") }
    var fields = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    for (key,value) in raw { fields[key] = value }
    let result = try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:fields))
    try result.validate(); return result
  }
}
public enum SelectionRefinementOutput: String, CaseIterable, Codable, Sendable {
  case selection, layerMask, newLayer, newLayerWithMask, newDocument, newDocumentWithMask
  public var title: String {
    switch self {
    case .selection: "Selection"; case .layerMask: "Layer Mask"; case .newLayer: "New Layer"
    case .newLayerWithMask: "New Layer with Layer Mask"; case .newDocument: "New Document"
    case .newDocumentWithMask: "New Document with Layer Mask"
    }
  }
  public var createsDocument: Bool { self == .newDocument || self == .newDocumentWithMask }
  public func allowingDecontamination(_ enabled: Bool) -> Self {
    enabled && (self == .selection || self == .layerMask) ? .newLayerWithMask : self
  }
}
