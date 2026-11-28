import Foundation
import ImageIO
import PhotoCraftCore

/// Portable Camera Raw adjustment settings. Sensor white balance uses kelvin;
/// Camera Raw Filter uses a separate pair of relative color controls.
public enum CameraRawXMP {
  public static let maximumBytes = 256 * 1024
  private static let namespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
  private static let prefix = "crs"

  private static let scalars: [(String, String)] = [
    ("Exposure2012", "exposure"), ("Contrast2012", "contrast"),
    ("Highlights2012", "highlights"), ("Shadows2012", "shadows"),
    ("Whites2012", "whites"), ("Blacks2012", "blacks"),
    ("IncrementalTemperature", "temperature"), ("IncrementalTint", "tint"),
    ("Vibrance", "vibrance"), ("Saturation", "saturation"),
    ("Texture", "texture"), ("Clarity2012", "clarity"), ("Dehaze", "dehaze"),
    ("PostCropVignetteAmount", "vignetteAmount"), ("PostCropVignetteMidpoint", "vignetteMidpoint"),
    ("PostCropVignetteRoundness", "vignetteRoundness"), ("PostCropVignetteFeather", "vignetteFeather"),
    ("PostCropVignetteHighlightContrast", "vignetteHighlights"),
    ("GrainAmount", "grainAmount"), ("GrainSize", "grainSize"), ("GrainFrequency", "grainRoughness"),
    ("ParametricHighlights", "curveHighlights"), ("ParametricLights", "curveLights"),
    ("ParametricDarks", "curveDarks"), ("ParametricShadows", "curveShadows"),
    ("Sharpness", "sharpenAmount"), ("SharpenRadius", "sharpenRadius"),
    ("SharpenDetail", "sharpenDetail"), ("SharpenEdgeMasking", "sharpenMasking"),
    ("LuminanceSmoothing", "noiseLuminance"), ("LuminanceNoiseReductionDetail", "noiseLuminanceDetail"),
    ("ColorNoiseReduction", "noiseColor"), ("ColorNoiseReductionDetail", "noiseColorDetail"),
    ("ColorGradeBlending", "gradeBlending"), ("SplitToningBalance", "gradeBalance"),
  ]
  private static let splits = ["ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit"]
  private static let colors = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
  private static let mixer: [(String, WritableKeyPath<CameraRawSettings, [Float]> & Sendable)] = [
    ("HueAdjustment", \.hslHue), ("SaturationAdjustment", \.hslSat), ("LuminanceAdjustment", \.hslLum),
  ]
  private static let grading: [(WritableKeyPath<CameraRawSettings, CameraRawSettings.Wheel> & Sendable, String, String, String)] = [
    (\.gradeShadows, "SplitToningShadowHue", "SplitToningShadowSaturation", "ColorGradeShadowLum"),
    (\.gradeMidtones, "ColorGradeMidtoneHue", "ColorGradeMidtoneSat", "ColorGradeMidtoneLum"),
    (\.gradeHighlights, "SplitToningHighlightHue", "SplitToningHighlightSaturation", "ColorGradeHighlightLum"),
    (\.gradeGlobal, "ColorGradeGlobalHue", "ColorGradeGlobalSat", "ColorGradeGlobalLum"),
  ]
  private static let curves: [(String, WritableKeyPath<CameraRawSettings, [[Float]]> & Sendable)] = [
    ("ToneCurvePV2012", \.pointCurve), ("ToneCurvePV2012Red", \.pointCurveRed),
    ("ToneCurvePV2012Green", \.pointCurveGreen), ("ToneCurvePV2012Blue", \.pointCurveBlue),
  ]
  private static let identityCurve: [[Float]] = [[0, 0], [255, 255]]
  private static let vignetteStyles = ["highlightPriority", "colorPriority", "paintOverlay"]
  private static let supportedFields: Set<String> = {
    var names = Set(scalars.map(\.0))
    names.formUnion(splits)
    names.formUnion(curves.map(\.0))
    names.formUnion(["WhiteBalance", "Temperature", "Tint", "PostCropVignetteStyle"])
    for (field, _) in mixer { names.formUnion(colors.map { field + $0 }) }
    for (_, hue, saturation, luminance) in grading { names.formUnion([hue, saturation, luminance]) }
    return names
  }()

  public static func read(_ data: Data, into base: CameraRawSettings = .init()) throws -> CameraRawSettings {
    try read(Packet(data), into: base)
  }

  public static func read(_ data: Data, into base: RawDevelopment) throws -> RawDevelopment {
    let packet = try Packet(data)
    var result = base
    result.adjustments = try read(packet, into: base.adjustments)
    if packet.string("WhiteBalance") == "As Shot" {
      result.temperature = nil
      result.tint = nil
    } else {
      result.temperature = try packet.float("Temperature") ?? result.temperature
      result.tint = try packet.float("Tint") ?? result.tint
    }
    try result.validate()
    return result
  }

  private static func read(_ packet: Packet, into base: CameraRawSettings) throws -> CameraRawSettings {
    try base.validate()
    var result = base
    for (field, control) in scalars {
      if let value = try packet.float(field) { result[control] = value }
    }
    for (index, field) in splits.enumerated() {
      if let value = try packet.float(field) { result.curveSplits[index] = value }
    }
    for (field, values) in mixer {
      for (index, color) in colors.enumerated() {
        if let value = try packet.float(field + color) { result[keyPath: values][index] = value }
      }
    }
    for (wheel, hue, saturation, luminance) in grading {
      var values = result[keyPath: wheel]
      values.hue = try packet.float(hue) ?? values.hue
      values.sat = try packet.float(saturation) ?? values.sat
      values.lum = try packet.float(luminance) ?? values.lum
      result[keyPath: wheel] = values
    }
    for (field, curve) in curves {
      if let points = try packet.points(field) { result[keyPath: curve] = points == identityCurve ? [] : points }
    }
    if let number = try packet.float("PostCropVignetteStyle") {
      guard let index = Int(exactly: number), (1...vignetteStyles.count).contains(index) else {
        throw CraftError.invalid("Invalid Camera Raw XMP vignette style.")
      }
      result.vignetteStyle = vignetteStyles[index - 1]
    }
    try result.validate()
    return result
  }

  public static func write(_ settings: CameraRawSettings) throws -> Data {
    try write(settings, sensor: nil)
  }

  public static func write(_ settings: RawDevelopment) throws -> Data {
    try settings.validate()
    return try write(settings.adjustments, sensor: settings)
  }

  private static func write(_ settings: CameraRawSettings, sensor: RawDevelopment?) throws -> Data {
    try settings.validate()
    let metadata = CGImageMetadataCreateMutable()
    guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, nil) else {
      throw CraftError.invalid("Could not register the Camera Raw XMP namespace.")
    }
    func set(_ name: String, _ value: CFTypeRef, type: CGImageMetadataType = .string) throws {
      guard let tag = CGImageMetadataTagCreate(namespace as CFString, prefix as CFString, name as CFString, type, value),
        CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString, tag) else {
        throw CraftError.invalid("Could not write Camera Raw XMP field \(name).")
      }
    }
    func number(_ value: Float) -> String {
      let text = String(value)
      return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
    func setNumber(_ name: String, _ value: Float) throws { try set(name, number(value) as CFString) }
    try set("ProcessVersion", "15.4" as CFString)
    try set("HasSettings", "True" as CFString)
    let whiteBalance = if let sensor { sensor.temperature != nil || sensor.tint != nil }
      else { settings.temperature != 0 || settings.tint != 0 }
    try set("WhiteBalance", (whiteBalance ? "Custom" : "As Shot") as CFString)
    if let temperature = sensor?.temperature { try setNumber("Temperature", temperature) }
    if let tint = sensor?.tint { try setNumber("Tint", tint) }
    for (field, control) in scalars {
      if sensor != nil && (control == "temperature" || control == "tint") { continue }
      try setNumber(field, settings[control])
    }
    for (index, field) in splits.enumerated() { try setNumber(field, settings.curveSplits[index]) }
    for (field, values) in mixer {
      for (index, color) in colors.enumerated() { try setNumber(field + color, settings[keyPath: values][index]) }
    }
    for (wheel, hue, saturation, luminance) in grading {
      let values = settings[keyPath: wheel]
      try setNumber(hue, values.hue)
      try setNumber(saturation, values.sat)
      try setNumber(luminance, values.lum)
    }
    let usesCustomCurve = curves.contains { !settings[keyPath: $0.1].isEmpty && settings[keyPath: $0.1] != identityCurve }
    try set("ToneCurveName2012", (usesCustomCurve ? "Custom" : "Linear") as CFString)
    for (field, curve) in curves {
      let points = settings[keyPath: curve].isEmpty ? identityCurve : settings[keyPath: curve]
      let values = points.map { "\(number($0[0])), \(number($0[1]))" }
      try set(field, values as CFArray, type: .arrayOrdered)
    }
    if let index = vignetteStyles.firstIndex(of: settings.vignetteStyle) {
      try setNumber("PostCropVignetteStyle", Float(index + 1))
    }
    guard let data = CGImageMetadataCreateXMPData(metadata, nil) as Data?, data.count <= maximumBytes else {
      throw CraftError.invalid("Could not write the Camera Raw XMP settings.")
    }
    return data
  }

  private struct Packet {
    let fields: [String: CGImageMetadataTag]

    init(_ data: Data) throws {
      guard !data.isEmpty, data.count <= maximumBytes,
        let metadata = CGImageMetadataCreateFromXMPData(data as CFData),
        let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else {
        throw CraftError.invalid("Choose a valid Camera Raw XMP settings file under 256 KiB.")
      }
      var fields: [String: CGImageMetadataTag] = [:]
      for tag in tags where CGImageMetadataTagCopyNamespace(tag) as String? == namespace {
        guard let name = CGImageMetadataTagCopyName(tag) as String? else { continue }
        fields[name] = tag
      }
      guard !supportedFields.isDisjoint(with: fields.keys) else {
        throw CraftError.invalid("The XMP file has no supported Camera Raw adjustments.")
      }
      self.fields = fields
    }

    func string(_ name: String) -> String? {
      fields[name].flatMap { CGImageMetadataTagCopyValue($0) as? String }
    }

    func float(_ name: String) throws -> Float? {
      guard fields[name] != nil else { return nil }
      guard let text = string(name), let value = Float(text.trimmingCharacters(in: .whitespacesAndNewlines)),
        value.isFinite else { throw CraftError.invalid("Invalid Camera Raw XMP field \(name).") }
      return value
    }

    func points(_ name: String) throws -> [[Float]]? {
      guard let tag = fields[name] else { return nil }
      guard let values = CGImageMetadataTagCopyValue(tag) as? [CGImageMetadataTag], (2...16).contains(values.count) else {
        throw CraftError.invalid("Camera Raw XMP curves require 2–16 points.")
      }
      return try values.map { value in
        guard let pair = CGImageMetadataTagCopyValue(value) as? String else {
          throw CraftError.invalid("Invalid Camera Raw XMP curve point.")
        }
        let coordinates = pair.split(separator: ",", omittingEmptySubsequences: false)
        let point = coordinates.compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard coordinates.count == 2, point.count == 2 else {
          throw CraftError.invalid("Invalid Camera Raw XMP curve point.")
        }
        return point
      }
    }
  }
}
