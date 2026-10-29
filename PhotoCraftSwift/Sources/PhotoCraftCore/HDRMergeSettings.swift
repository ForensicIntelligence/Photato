import Foundation

public struct HDRMergeSettings: Codable, Equatable, Sendable {
  public enum ExposureSource: String, Codable, CaseIterable, Sendable { case metadata,manual,estimate }
  public enum Method: String, Codable, CaseIterable, Sendable {
    case localAdaptation,exposureGamma,highlightCompression,equalizeHistogram
    public var title: String { switch self { case .localAdaptation:"Local Adaptation";case .exposureGamma:"Exposure and Gamma";case .highlightCompression:"Highlight Compression";case .equalizeHistogram:"Equalize Histogram" } }
  }
  public var exposureSource: ExposureSource = .metadata
  public var exposureEV = [Double]()
  public var align = true
  public var removeGhosts = false
  public var ghostBase: Int?
  public var depth: PixelDepth = .f32
  public var method: Method = .localAdaptation
  public var radius: Float = 7
  public var strength: Float = 0.52
  public var gamma: Float = 1
  public var exposure: Float = 0
  public var detail: Float = 30
  public var shadows: Float = 0
  public var highlights: Float = 0
  public var vibrance: Float = 0
  public var saturation: Float = 20
  public init() {}
  public func validate(count: Int) throws {
    guard (2...16).contains(count),ghostBase == nil || (0..<count).contains(ghostBase!),
      exposureEV.count <= 16,exposureEV.allSatisfy({$0.isFinite && (-20...20).contains($0)}),
      exposureSource != .manual || exposureEV.count == count else { throw CraftError.invalid("Choose two to sixteen exposures, a valid base image, and one EV per image in manual mode (−20…20).") }
    for (v,lo,hi) in [(radius,Float(1),Float(500)),(strength,0.1,4),(gamma,0.1,4),(exposure,-5,5),(detail,-100,300),(shadows,-100,100),(highlights,-100,100),(vibrance,-100,100),(saturation,-100,100)] {
      guard v.isFinite,(lo...hi).contains(v) else { throw CraftError.invalid("HDR tone settings are outside their supported range.") }
    }
  }
}
