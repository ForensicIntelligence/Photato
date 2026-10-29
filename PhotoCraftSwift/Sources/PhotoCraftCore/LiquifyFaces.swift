import Foundation

/// Normalized image-space rectangles (x,y,width,height), y down. No identity/biometric identifiers.
public struct LiquifyFaceGeometry: Codable, Equatable, Sendable {
  public var bounds: [Double]
  public var leftEye: [Double]
  public var rightEye: [Double]
  public var nose: [Double]
  public var mouth: [Double]
  public init(bounds: [Double], leftEye: [Double], rightEye: [Double], nose: [Double], mouth: [Double]) {
    self.bounds = bounds; self.leftEye = leftEye; self.rightEye = rightEye; self.nose = nose; self.mouth = mouth
  }
  public func validate() throws {
    for r in [bounds,leftEye,rightEye,nose,mouth] {
      guard r.count == 4, r.allSatisfy({ $0.isFinite && (0...1).contains($0) }), r[2] > 0, r[3] > 0,
        r[0]+r[2] <= 1.000001, r[1]+r[3] <= 1.000001 else { throw CraftError.invalid("Invalid normalized face geometry.") }
    }
  }
}
public enum LiquifyFaceParameter: String, Codable, CaseIterable, Sendable {
  case leftEyeSize, rightEyeSize, leftEyeHeight, rightEyeHeight, leftEyeWidth, rightEyeWidth, leftEyeTilt, rightEyeTilt, eyeDistance
  case noseHeight, noseWidth, smile, upperLip, lowerLip, mouthWidth, mouthHeight, forehead, chinHeight, jawline, faceWidth
  public var title: String {
    switch self {
    case .leftEyeSize: "Left Eye Size"; case .rightEyeSize: "Right Eye Size"
    case .leftEyeHeight: "Left Eye Height"; case .rightEyeHeight: "Right Eye Height"
    case .leftEyeWidth: "Left Eye Width"; case .rightEyeWidth: "Right Eye Width"
    case .leftEyeTilt: "Left Eye Tilt"; case .rightEyeTilt: "Right Eye Tilt"
    case .eyeDistance: "Eye Distance"; case .noseHeight: "Nose Height"; case .noseWidth: "Nose Width"
    case .smile: "Smile"; case .upperLip: "Upper Lip"; case .lowerLip: "Lower Lip"
    case .mouthWidth: "Mouth Width"; case .mouthHeight: "Mouth Height"
    case .forehead: "Forehead"; case .chinHeight: "Chin Height"; case .jawline: "Jawline"; case .faceWidth: "Face Width"
    }
  }
}
public struct LiquifyFaceAdjustment: Codable, Equatable, Sendable {
  public var geometry: LiquifyFaceGeometry
  public var parameters: [String:Double] = [:]
  public init(geometry: LiquifyFaceGeometry, parameters: [String:Double] = [:]) { self.geometry = geometry; self.parameters = parameters }
  public func validate() throws {
    try geometry.validate()
    guard Set(parameters.keys).isSubset(of:Set(LiquifyFaceParameter.allCases.map(\.rawValue))),
      parameters.values.allSatisfy({ $0.isFinite && (-100...100).contains($0) }) else { throw CraftError.invalid("Face Liquify parameters must be between−100 and100.") }
  }
  public subscript(_ p: LiquifyFaceParameter) -> Double {
    get { parameters[p.rawValue] ?? 0 }
    set { parameters[p.rawValue] = newValue }
  }
}
