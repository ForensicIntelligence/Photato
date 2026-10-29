import Foundation
import PhotoCraftCore

/// Value snapshots keep a running operation independent of later preference edits.
public struct ColorSettings: Codable, Equatable, Sendable {
  public enum Policy: String, Codable, CaseIterable, Sendable { case preserveEmbedded, convertToWorking, off }
  public static let maximumArchiveBytes = 3 * ((ICCProfile.maximumBytes + 2) / 3 * 4) + 16_384
  public var workingRGB: Data?
  public var workingCMYK: Data?
  public var workingGray: Data?
  public var intent: ModeRenderingIntent = .relativeColorimetric
  public var blackPointCompensation = true
  public var rgbPolicy: Policy = .preserveEmbedded
  public var cmykPolicy: Policy = .preserveEmbedded
  public var grayPolicy: Policy = .preserveEmbedded
  public var askMismatchOpening = false
  public var askMismatchPasting = false
  public var askMissingOpening = false
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case workingRGB, workingCMYK, workingGray, intent, blackPointCompensation
    case rgbPolicy, cmykPolicy, grayPolicy, askMismatchOpening, askMismatchPasting, askMissingOpening
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    workingRGB = try c.decodeIfPresent(Data.self, forKey: .workingRGB)
    workingCMYK = try c.decodeIfPresent(Data.self, forKey: .workingCMYK)
    workingGray = try c.decodeIfPresent(Data.self, forKey: .workingGray)
    intent = try c.decode(ModeRenderingIntent.self, forKey: .intent)
    blackPointCompensation = try c.decode(Bool.self, forKey: .blackPointCompensation)
    rgbPolicy = try c.decodeIfPresent(Policy.self, forKey: .rgbPolicy) ?? .preserveEmbedded
    cmykPolicy = try c.decodeIfPresent(Policy.self, forKey: .cmykPolicy) ?? .preserveEmbedded
    grayPolicy = try c.decodeIfPresent(Policy.self, forKey: .grayPolicy) ?? .preserveEmbedded
    askMismatchOpening = try c.decodeIfPresent(Bool.self, forKey: .askMismatchOpening) ?? false
    askMismatchPasting = try c.decodeIfPresent(Bool.self, forKey: .askMismatchPasting) ?? false
    askMissingOpening = try c.decodeIfPresent(Bool.self, forKey: .askMissingOpening) ?? false
  }
  public func policy(_ mode: DocumentColorMode) -> Policy {
    switch mode { case .rgb: rgbPolicy; case .cmyk: cmykPolicy; case .grayscale: grayPolicy; default: .preserveEmbedded }
  }
  public static let workingModes: [DocumentColorMode] = [.rgb, .cmyk, .grayscale]
  public func storedProfile(_ mode: DocumentColorMode) -> Data? {
    switch mode { case .rgb: workingRGB; case .cmyk: workingCMYK; case .grayscale: workingGray; default: nil }
  }
  public mutating func setProfile(_ data: Data?, for mode: DocumentColorMode) throws {
    guard Self.workingModes.contains(mode) else { throw CraftError.invalid("This color mode has no configurable working space.") }
    if let data { try NativeModeProfile.validate(data, mode: mode, depth: .u16) }
    switch mode { case .rgb: workingRGB = data; case .cmyk: workingCMYK = data; case .grayscale: workingGray = data; default: break }
  }
  public func validate() throws {
    for mode in Self.workingModes {
      if let data = storedProfile(mode) { try NativeModeProfile.validate(data, mode: mode, depth: .u16) }
    }
  }
  public func profile(_ mode: DocumentColorMode, depth: PixelDepth) throws -> Data {
    if let data = storedProfile(mode) { return try NativeModeProfile.atDepth(data, mode: mode, depth: depth) }
    return try NativeModeProfile.standard(mode, depth: depth)
  }
  public func conversionProfile(from document: CraftDocument, to mode: DocumentColorMode, depth: PixelDepth) throws -> Data {
    // Changing only precision retains the document's interpretation, including custom ICC.
    if document.colorMode == mode, DocumentColorMode.componentModes.contains(mode) {
      return try NativeModeProfile.atDepth(ColorProfileInput.effectiveProfile(document), mode: mode, depth: depth)
    }
    return try profile(mode, depth: depth)
  }
  public func resolvingProof(_ original: ProofSettings, refresh: Bool = false) throws -> ProofSettings {
    var result = original
    if result.device == .workingCMYK, refresh || result.profile == nil {
      let profile = try self.profile(.cmyk, depth: .u16)
      result.profile = profile; result.profileName = ColorPolicyInput.name(profile)
    }
    return result
  }
}
