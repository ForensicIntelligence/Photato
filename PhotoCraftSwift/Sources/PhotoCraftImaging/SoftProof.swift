// The C SDK declares read-only constant strings as global variables.
@preconcurrency import ColorSync
import CoreGraphics
import Foundation
import PhotoCraftCore

/// View settings only: never serialized into document pixels or edit history.
public struct ProofSettings: Codable, Equatable, Sendable {
  public enum Device: String, Codable, CaseIterable, Sendable { case workingCMYK, sRGB, custom, legacyMacintoshRGB }
  public enum Plate: String, Codable, CaseIterable, Sendable { case composite, cyan, magenta, yellow, black, cmy }
  public var enabled = false
  public var gamutWarning = false
  public var device: Device = .workingCMYK
  public var profile: Data?
  public var profileName = "Generic CMYK"
  public var intent: ModeRenderingIntent = .relativeColorimetric
  public var blackPointCompensation = true
  public var preserveNumbers = false
  public var simulatePaper = false
  public var simulateBlack = false
  public var plate: Plate = .composite
  public var warningColor = Pixel(0.5, 0.5, 0.5)
  public var warningOpacity: Float = 1
  public var gamutThreshold: Float = 4
  public init() {}
  public var active: Bool { enabled || gamutWarning }
  public var gamutWarningAvailable: Bool { device != .legacyMacintoshRGB }
  public var displayName: String { device == .legacyMacintoshRGB ? "Macintosh" : device == .workingCMYK && profile == nil ? "Generic CMYK" : device == .sRGB ? "sRGB" : profileName }
  /// Factory preset observed in Photoshop 2026; independent of edit history.
  public func selectingLegacyMacintosh(preserveNumbers: Bool = true) -> Self {
    var result = self
    result.device = .legacyMacintoshRGB; result.profile = nil; result.profileName = "Apple RGB"
    result.enabled = true; result.gamutWarning = false; result.plate = .composite
    result.intent = .relativeColorimetric; result.blackPointCompensation = false; result.preserveNumbers = preserveNumbers
    result.simulatePaper = false; result.simulateBlack = false
    return result
  }
  public func resolvedProfile() throws -> Data {
    switch device {
    case .workingCMYK:
      if let profile { try NativeModeProfile.validate(profile, mode: .cmyk, depth: .u16); return profile }
      return try NativeModeProfile.standard(.cmyk, depth: .u16)
    case .sRGB: return try NativeModeProfile.standard(.rgb, depth: .u16)
    case .legacyMacintoshRGB: return try NativeModeProfile.appleRGB()
    case .custom:
      guard let profile else { throw CraftError.invalid("Choose a proof profile.") }; return profile
    }
  }
  public static func mode(of profile: Data) throws -> DocumentColorMode {
    guard profile.count >= 132, let mode = DocumentColorMode.componentModes.first(where: {
      $0.profileSignature == String(decoding: profile[16..<20], as: UTF8.self)
    }) else { throw CraftError.invalid("Proofing requires an RGB, CMYK, Lab or grayscale ICC profile.") }
    try NativeModeProfile.validate(profile, mode: mode, depth: .u16); return mode
  }
  public func validate() throws {
    guard profileName.count <= 1024, warningColor.isFinite, warningColor.a == 1,
      [warningColor.r, warningColor.g, warningColor.b, warningOpacity].allSatisfy({ (0...1).contains($0) }),
      gamutThreshold.isFinite, (0.01...100).contains(gamutThreshold) else { throw CraftError.invalid("Invalid proof or gamut-warning settings.") }
    guard gamutWarningAvailable || !gamutWarning else { throw CraftError.invalid("Gamut Warning is unavailable for the legacy Macintosh proof preset.") }
    if device == .legacyMacintoshRGB, profile != nil { throw CraftError.invalid("The built-in Apple RGB profile cannot be replaced. Choose a custom proof profile instead.") }
    if let profile { _ = try Self.mode(of: profile) }
    let mode = try Self.mode(of: resolvedProfile())
    guard plate == .composite || mode == .cmyk else { throw CraftError.invalid("Ink plate proofing requires a CMYK profile.") }
  }
}

/// An operation owns the native ColorSync transform. Float Lab in ColorSync uses
/// L/100 and a/256+0.5, unlike the document's normalized (a+128)/255 planes.
struct ProofTransform {
  let transform: ColorSyncTransform
  let inputCount: Int
  let outputCount: Int
  init(_ source: Data, _ destination: Data, intent: ModeRenderingIntent, bpc: Bool) throws {
    inputCount = try ProofSettings.mode(of: source).componentCount
    outputCount = try ProofSettings.mode(of: destination).componentCount
    guard let a = ColorSyncProfileCreate(source as CFData, nil)?.takeRetainedValue(),
      let b = ColorSyncProfileCreate(destination as CFData, nil)?.takeRetainedValue() else { throw CraftError.invalid("ColorSync cannot open the proof profile.") }
    let rendering: CFString
    switch intent {
    case .perceptual: rendering = kColorSyncRenderingIntentPerceptual.takeUnretainedValue()
    case .relativeColorimetric: rendering = kColorSyncRenderingIntentRelative.takeUnretainedValue()
    case .saturation: rendering = kColorSyncRenderingIntentSaturation.takeUnretainedValue()
    case .absoluteColorimetric: rendering = kColorSyncRenderingIntentAbsolute.takeUnretainedValue()
    }
    func link(_ profile: ColorSyncProfile, _ tag: CFString) -> [String: Any] {
      [kColorSyncProfile.takeUnretainedValue() as String: profile,
       kColorSyncTransformTag.takeUnretainedValue() as String: tag,
       kColorSyncRenderingIntent.takeUnretainedValue() as String: rendering,
       kColorSyncBlackPointCompensation.takeUnretainedValue() as String: bpc]
    }
    guard let result = ColorSyncTransformCreate([
      link(a, kColorSyncTransformDeviceToPCS.takeUnretainedValue()),
      link(b, kColorSyncTransformPCSToDevice.takeUnretainedValue())] as CFArray, nil)?.takeRetainedValue() else {
      throw CraftError.unsupported("ColorSync cannot construct this proof conversion.")
    }
    transform = result
  }
  func apply(_ samples: [Float]) throws -> [Float] {
    try Task.checkCancellation()
    guard samples.count % inputCount == 0, samples.allSatisfy(\.isFinite) else { throw CraftError.invalid("Invalid proof input samples.") }
    let width = samples.count / inputCount
    var output = [Float](repeating: 0, count: width * outputCount)
    let rowBytes = output.count * MemoryLayout<Float>.size
    let ok = output.withUnsafeMutableBytes { destination in samples.withUnsafeBytes { source in
      ColorSyncTransformConvert(transform, width, 1, destination.baseAddress!, kColorSync32BitFloat, 0,
        rowBytes, source.baseAddress!, kColorSync32BitFloat, 0, samples.count * MemoryLayout<Float>.size, nil)
    } }
    guard ok, output.allSatisfy(\.isFinite) else { throw CraftError.invalid("ColorSync proof conversion failed.") }
    return output
  }
}

public enum SoftProof {
  /// Legacy kernel/print budget. Printing retains its separate preparation limit.
  public static let maximumPixels = 8_388_608
  public static let maximumDocumentPixels = Surface.maxPixels
  public static func retainedComponents(_ document: CraftDocument) -> NativeModeRaster? {
    guard !document.hasArtboards, document.artboardOrigin == nil,
      !InkModeInput.needsMerge(document), let layer = document.layers.first,
      let native = layer.nativeMode, native.width == document.width, native.height == document.height else { return nil }
    return native
  }
  public static func canPreserveNumbers(_ document: CraftDocument, settings: ProofSettings) -> Bool {
    guard let mode = try? ProofSettings.mode(of: settings.resolvedProfile()), mode == document.colorMode else { return false }
    return (mode == .rgb && document.modeDescriptor == nil) || retainedComponents(document) != nil
  }
  public static func validate(_ settings: ProofSettings, in document: CraftDocument) throws {
    try settings.validate()
    guard document.width > 0, document.height > 0,document.width<=Surface.maxDimension,document.height<=Surface.maxDimension,document.width<=maximumDocumentPixels/document.height else {
      throw CraftError.unsupported("Soft proofing supports up to300,000 pixels per dimension; composition and scratch resource limits still apply.")
    }
    guard !settings.preserveNumbers || canPreserveNumbers(document, settings: settings) else {
      throw CraftError.unsupported("Preserve Numbers requires matching modes and retained flat component samples. Flatten the component document first.")
    }
  }
  public static func surface(_ document: CraftDocument, composite: Surface? = nil, settings: ProofSettings) throws -> Surface {
    try Task.checkCancellation(); try validate(settings, in: document)
    if document.width>maximumPixels/document.height{return try PagedSoftProof.surface(document,composite:composite,settings:settings)}
    let original = try composite ?? Renderer.composite(document)
    guard original.width == document.width, original.height == document.height else { throw CraftError.invalid("Proof preview dimensions differ from the document.") }
    let native = retainedComponents(document)
    let sourceProfile = try native?.profile ?? ColorManagement.space(for: document).copyICCData() as Data? ?? NativeModeProfile.standard(.rgb, depth: document.depth)
    let proofProfile = try settings.resolvedProfile()
    let displayProfile = try NativeModeProfile.standard(.rgb, depth: .u16)
    let proofMode = try ProofSettings.mode(of: proofProfile), proofCount = proofMode.componentCount
    let toProof = try ProofTransform(sourceProfile, proofProfile, intent: settings.intent, bpc: settings.blackPointCompensation)
    let toDisplay = try ProofTransform(proofProfile, displayProfile,
      intent: settings.simulatePaper ? .absoluteColorimetric : .relativeColorimetric,
      bpc: !settings.simulatePaper && !settings.simulateBlack)
    let directDisplay = try ProofTransform(sourceProfile, displayProfile, intent: .relativeColorimetric, bpc: true)
    let lab = try settings.gamutWarning ? NativeModeProfile.standard(.lab, depth: .u16) : nil
    let directLab = try lab.map { try ProofTransform(sourceProfile, $0, intent: .relativeColorimetric, bpc: false) }
    let gamutDevice = try lab.map { _ in try ProofTransform(sourceProfile, proofProfile, intent: .relativeColorimetric, bpc: false) }
    let proofLab = try lab.map { try ProofTransform(proofProfile, $0, intent: .relativeColorimetric, bpc: false) }
    var output = try Surface(width: document.width, height: document.height, depth: .f32, colorEncoding: .sRGB)
    for y in 0..<document.height {
      try Task.checkCancellation()
      var input = [Float](); input.reserveCapacity(document.width * (native?.mode.componentCount ?? 3))
      for x in 0..<document.width {
        if let native {
          for c in 0..<native.mode.componentCount {
            let value = native.value(component: c, index: y * document.width + x)
            input.append(native.mode == .lab && c > 0 ? value * 255 / 256 : value)
          }
        } else {
          let p = document.depth == .f32 ? original.linearPixel(x: x, y: y) : original.pixel(x: x, y: y)
          input += [p.r, p.g, p.b]
        }
      }
      var device = try settings.preserveNumbers ? input : toProof.apply(input).map(unit)
      let plateIndex: Int? = switch settings.plate { case .cyan: 0; case .magenta: 1; case .yellow: 2; case .black: 3; default: nil }
      if settings.plate == .cmy { for x in 0..<document.width { device[x * proofCount + 3] = 0 } }
      let display = try settings.enabled ? toDisplay.apply(device) : directDisplay.apply(input)
      var warnings = [Bool](repeating: false, count: document.width)
      if let directLab, let gamutDevice, let proofLab {
        let a = try directLab.apply(input), b = try proofLab.apply(gamutDevice.apply(input).map(unit))
        for x in 0..<document.width {
          let l = (a[x * 3] - b[x * 3]) * 100
          let aa = (a[x * 3 + 1] - b[x * 3 + 1]) * 256, bb = (a[x * 3 + 2] - b[x * 3 + 2]) * 256
          warnings[x] = sqrt(l * l + aa * aa + bb * bb) > settings.gamutThreshold
        }
      }
      for x in 0..<document.width {
        let alpha = original.pixel(x: x, y: y).a
        var p = Pixel(unit(display[x * 3]), unit(display[x * 3 + 1]), unit(display[x * 3 + 2]), alpha)
        if settings.enabled, let plateIndex { let v = 1 - unit(device[x * proofCount + plateIndex]); p = Pixel(v, v, v, alpha) }
        if settings.gamutWarning, warnings[x], alpha > 0 {
          let a = settings.warningOpacity, c = settings.warningColor
          p = Pixel(p.r * (1 - a) + c.r * a, p.g * (1 - a) + c.g * a, p.b * (1 - a) + c.b * a, alpha)
        }
        output.setPixel(x: x, y: y, p)
      }
    }
    return output
  }
  public static func image(_ document: CraftDocument, composite: Surface? = nil, settings: ProofSettings,request:RasterPreviewRequest?=nil) throws -> CGImage {
    let pixels=try surface(document,composite:composite,settings:settings)
    let request=try request ?? (document.width>Surface.maximumDensePixels/document.height ? RasterPreviewRequest.overview(width:document.width,height:document.height):nil)
    return try RasterIO.displayImage(request?.reducing(pixels) ?? pixels)
  }
}
