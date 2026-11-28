import Foundation
import ImageIO
import PhotoCraftCore

/// Portable Camera Raw adjustment settings. Sensor white balance uses kelvin;
/// Camera Raw Filter uses a separate pair of relative color controls.
public enum CameraRawXMP {
  public static let maximumBytes = 256 * 1024
  private static let namespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
  private static let prefix = "crs"
  private static let nativeNamespace = "https://forensicintelligence.ca/photato/ns/raw/1.0/"
  private static let nativePrefix = "photatoRaw"
  private static let nativeField = "Development"

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
    try readRaw(Packet(data), into: base)
  }

  static func validatePreset(_ data: Data) throws {
    var packet = try Packet(data, readingPreset: true)
    _ = try readRaw(packet, into: RawDevelopment())
    let series = try packet.isoSeries()
    for iso in series.speeds {
      packet.adaptiveValues = series.values(at: iso)
      _ = try readRaw(packet, into: RawDevelopment())
    }
  }

  static func readPreset(_ data: Data, into base: RawDevelopment, iso: Double?) throws -> RawDevelopment {
    var packet = try Packet(data, readingPreset: true)
    if let iso { packet.adaptiveValues = try packet.isoSeries().values(at: iso) }
    return try readRaw(packet, into: base)
  }

  static func readStored(_ data: Data) throws -> RawDevelopment {
    let packet = try Packet(data)
    var result = try readRaw(packet, into: RawDevelopment())
    guard let native = packet.nativeDevelopment else { return result }
    // Adobe fields remain authoritative after an external edit. The extra
    // namespace carries only the controls with no equivalent portable field.
    result.decoderVersion = native.decoderVersion
    result.exposure = native.exposure
    result.boost = native.boost
    result.shadowBoost = native.shadowBoost
    result.extendedRange = native.extendedRange
    result.lensCorrection = native.lensCorrection
    result.highlightRecovery = native.highlightRecovery
    result.adjustments.temperature = native.adjustments.temperature
    result.adjustments.tint = native.adjustments.tint
    result.adjustments.seed = native.adjustments.seed
    result.adjustments.pixelScale = native.adjustments.pixelScale
    return result
  }

  private static func readRaw(_ packet: Packet, into base: RawDevelopment) throws -> RawDevelopment {
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

  public static func write(_ settings: RawDevelopment, replacing original: Data? = nil) throws -> Data {
    try settings.validate()
    return try write(settings.adjustments, sensor: settings, replacing: original)
  }

  static func writeStored(_ settings: RawDevelopment, replacing original: Data?, including sidecar: Data?) throws -> Data {
    try settings.validate()
    return try write(settings.adjustments, sensor: settings, replacing: original,
      including: sidecar, includeNativeDevelopment: true)
  }

  static func writeStoredSidecar(_ settings: RawDevelopment, replacing previous: RawSourceIO.RelatedXMP?) throws -> Data {
    try settings.validate()
    return try write(settings.adjustments, sensor: settings, replacing: previous?.data,
      includeNativeDevelopment: true, preserving: previous?.settings)
  }

  private static func tags(in metadata: CGImageMetadata) -> [CGImageMetadataTag] {
    (CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]) ?? []
  }

  private static func merge(_ data: Data, into metadata: CGMutableImageMetadata) throws {
    guard (1...maximumBytes).contains(data.count),
      let source = CGImageMetadataCreateFromXMPData(data as CFData) else {
      throw CraftError.invalid("Could not preserve the source sidecar metadata.")
    }
    for tag in tags(in: metadata) where CGImageMetadataTagCopyNamespace(tag) as String? == namespace {
      guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?,
        let name = CGImageMetadataTagCopyName(tag) as String?,
        CGImageMetadataRemoveTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString) else {
        throw CraftError.invalid("Could not replace the embedded Camera Raw settings with the sidecar.")
      }
    }
    for tag in tags(in: source) {
      guard let namespace = CGImageMetadataTagCopyNamespace(tag),
        let prefix = CGImageMetadataTagCopyPrefix(tag),
        let name = CGImageMetadataTagCopyName(tag) as String?,
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil),
        CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString, tag) else {
        throw CraftError.invalid("Could not merge a source sidecar metadata field.")
      }
    }
  }

  private static func write(_ settings: CameraRawSettings, sensor: RawDevelopment?,
    replacing original: Data? = nil, including sidecar: Data? = nil,
    includeNativeDevelopment: Bool = false, preserving previous: RawDevelopment? = nil) throws -> Data {
    try settings.validate()
    let metadata: CGMutableImageMetadata
    if let original {
      guard (1...maximumBytes).contains(original.count),
        let source = CGImageMetadataCreateFromXMPData(original as CFData),
        let copy = CGImageMetadataCreateMutableCopy(source) else {
        throw CraftError.invalid("Could not preserve the original XMP metadata.")
      }
      metadata = copy
    } else {
      metadata = CGImageMetadataCreateMutable()
    }
    if let sidecar { try merge(sidecar, into: metadata) }
    let originalTags = tags(in: metadata)
    let cameraTag = originalTags.first { CGImageMetadataTagCopyNamespace($0) as String? == namespace }
    let prefix = cameraTag.flatMap { CGImageMetadataTagCopyPrefix($0) as String? } ?? Self.prefix
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
    func setNumber(_ name: String, _ value: Float, previous: Float? = nil) throws {
      guard value != previous else { return }
      try set(name, number(value) as CFString)
    }
    if previous == nil { try set("ProcessVersion", "15.4" as CFString) }
    try set("HasSettings", "True" as CFString)
    if previous == nil || sensor?.temperature != previous?.temperature || sensor?.tint != previous?.tint {
      let whiteBalance = if let sensor { sensor.temperature != nil || sensor.tint != nil }
        else { settings.temperature != 0 || settings.tint != 0 }
      try set("WhiteBalance", (whiteBalance ? "Custom" : "As Shot") as CFString)
      if let temperature = sensor?.temperature { try setNumber("Temperature", temperature) }
      else if sensor != nil { CGImageMetadataRemoveTagWithPath(metadata, nil, "\(prefix):Temperature" as CFString) }
      if let tint = sensor?.tint { try setNumber("Tint", tint) }
      else if sensor != nil { CGImageMetadataRemoveTagWithPath(metadata, nil, "\(prefix):Tint" as CFString) }
    }
    let previousAdjustments = previous?.adjustments
    for (field, control) in scalars {
      if sensor != nil && (control == "temperature" || control == "tint") { continue }
      try setNumber(field, settings[control], previous: previousAdjustments?[control])
    }
    for (index, field) in splits.enumerated() {
      try setNumber(field, settings.curveSplits[index], previous: previousAdjustments?.curveSplits[index])
    }
    for (field, values) in mixer {
      for (index, color) in colors.enumerated() {
        try setNumber(field + color, settings[keyPath: values][index],
          previous: previousAdjustments?[keyPath: values][index])
      }
    }
    for (wheel, hue, saturation, luminance) in grading {
      let values = settings[keyPath: wheel]
      let old = previousAdjustments?[keyPath: wheel]
      try setNumber(hue, values.hue, previous: old?.hue)
      try setNumber(saturation, values.sat, previous: old?.sat)
      try setNumber(luminance, values.lum, previous: old?.lum)
    }
    func curvePoints(_ points: [[Float]]) -> [[Float]] {
      points.isEmpty ? identityCurve : points
    }
    var changedCurve = false
    for (field, curve) in curves {
      let points = curvePoints(settings[keyPath: curve])
      if let previousAdjustments, points == curvePoints(previousAdjustments[keyPath: curve]) { continue }
      changedCurve = true
      let values = points.map { "\(number($0[0])), \(number($0[1]))" }
      try set(field, values as CFArray, type: .arrayOrdered)
    }
    if changedCurve {
      let usesCustomCurve = curves.contains { curvePoints(settings[keyPath: $0.1]) != identityCurve }
      try set("ToneCurveName2012", (usesCustomCurve ? "Custom" : "Linear") as CFString)
    }
    if settings.vignetteStyle != previousAdjustments?.vignetteStyle,
      let index = vignetteStyles.firstIndex(of: settings.vignetteStyle) {
      try setNumber("PostCropVignetteStyle", Float(index + 1))
    }
    if includeNativeDevelopment, let sensor {
      // Keep the portable controls in Adobe's namespace even though this
      // supplemental record also uses the native settings representation.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let value = try encoder.encode(sensor).base64EncodedString()
      let tag = originalTags.first { CGImageMetadataTagCopyNamespace($0) as String? == nativeNamespace }
      let alias = tag.flatMap { CGImageMetadataTagCopyPrefix($0) as String? } ?? nativePrefix
      guard CGImageMetadataRegisterNamespaceForPrefix(metadata, nativeNamespace as CFString, alias as CFString, nil),
        CGImageMetadataSetValueWithPath(metadata, nil, "\(alias):\(nativeField)" as CFString, value as CFString) else {
        throw CraftError.invalid("Could not retain Photato’s native RAW settings in the XMP packet.")
      }
    }
    guard let data = CGImageMetadataCreateXMPData(metadata, nil) as Data?, data.count <= maximumBytes else {
      throw CraftError.invalid("Could not write the Camera Raw XMP settings.")
    }
    return data
  }

  private struct ISOSettings {
    typealias Point = (speed: Double, value: Float)
    let speeds: [Double]
    let fields: [String: [Point]]

    func values(at iso: Double) -> [String: Float] {
      guard iso.isFinite, iso > 0 else { return [:] }
      return fields.compactMapValues { points in
        guard let first = points.first, let last = points.last else { return nil }
        if iso <= first.speed { return first.value }
        if iso >= last.speed { return last.value }
        guard let upper = points.firstIndex(where: { $0.speed >= iso }), upper > 0 else { return nil }
        let low = points[upper - 1], high = points[upper]
        if iso == high.speed { return high.value }
        let fraction = log2(iso / low.speed) / log2(high.speed / low.speed)
        return Float(Double(low.value) + fraction * (Double(high.value) - Double(low.value)))
      }
    }
  }

  private struct Packet {
    let fields: [String: CGImageMetadataTag]
    let nativeDevelopment: RawDevelopment?
    var adaptiveValues: [String: Float] = [:]

    init(_ data: Data, readingPreset: Bool = false) throws {
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
      guard !supportedFields.isDisjoint(with: fields.keys) || (readingPreset && fields["ISODependent"] != nil) else {
        throw CraftError.invalid("The XMP file has no supported Camera Raw adjustments.")
      }
      self.fields = fields
      let native = tags.first { tag in
        CGImageMetadataTagCopyNamespace(tag) as String? == nativeNamespace
          && CGImageMetadataTagCopyName(tag) as String? == nativeField
      }
      let value = native.flatMap { CGImageMetadataTagCopyValue($0) as? String }
      nativeDevelopment = value.flatMap { text in
        guard text.utf8.count <= 43_692, let data = Data(base64Encoded: text) else { return nil }
        return try? RawDevelopment.decodeJSON(data)
      }
    }

    func string(_ name: String) -> String? {
      fields[name].flatMap { CGImageMetadataTagCopyValue($0) as? String }
    }

    func float(_ name: String) throws -> Float? {
      if let value = adaptiveValues[name] { return value }
      guard let field = fields[name] else { return nil }
      return try number(field, named: name)
    }

    private func number(_ tag: CGImageMetadataTag, named name: String) throws -> Float {
      guard let text = CGImageMetadataTagCopyValue(tag) as? String,
        let value = Float(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
        throw CraftError.invalid("Invalid Camera Raw XMP field \(name).")
      }
      return value
    }

    func isoSeries() throws -> ISOSettings {
      guard let sequence = fields["ISODependent"] else { return .init(speeds: [], fields: [:]) }
      guard let entries = CGImageMetadataTagCopyValue(sequence) as? [CGImageMetadataTag],
        (2...128).contains(entries.count) else {
        throw CraftError.invalid("An ISO-adaptive preset needs 2–128 ISO points.")
      }
      // Adobe writes one resource per ISO. Curves and categorical values do
      // not use the numeric interpolator; their top-level values still apply.
      let numericFields = supportedFields.subtracting(curves.map(\.0)).subtracting(["WhiteBalance", "PostCropVignetteStyle"])
      var speeds = Set<Double>()
      var series: [String: [ISOSettings.Point]] = [:]
      for entry in entries {
        let row = (CGImageMetadataTagCopyValue(entry) as? [String: CGImageMetadataTag])?.values
        let tags = row?.filter { CGImageMetadataTagCopyNamespace($0) as String? == namespace } ?? []
        guard let isoTag = tags.first(where: { CGImageMetadataTagCopyName($0) as String? == "ISO" }) else {
          throw CraftError.invalid("Each Camera Raw preset point needs an ISO value.")
        }
        let iso = Double(try number(isoTag, named: "ISO"))
        guard iso > 0, speeds.insert(iso).inserted else {
          throw CraftError.invalid("Camera Raw ISO values must be positive and unique.")
        }
        for tag in tags {
          guard let name = CGImageMetadataTagCopyName(tag) as String?, numericFields.contains(name) else { continue }
          series[name, default: []].append((iso, try number(tag, named: name)))
        }
      }
      guard !series.isEmpty || !supportedFields.isDisjoint(with: fields.keys) else {
        throw CraftError.invalid("The ISO-adaptive preset has no supported Camera Raw adjustments.")
      }
      return .init(speeds: speeds.sorted(), fields: series.mapValues { $0.sorted { $0.speed < $1.speed } })
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
