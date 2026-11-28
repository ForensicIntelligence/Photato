import Foundation

/// Axis-aligned crop in normalized RAW image coordinates.
public struct RawCropBounds: Codable, Equatable, Sendable {
  public let left: Float
  public let top: Float
  public let right: Float
  public let bottom: Float

  public init(left: Float, top: Float, right: Float, bottom: Float) throws {
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
    try validate()
  }

  fileprivate func validate() throws {
    guard left >= 0, left < right, right <= 1, top >= 0, top < bottom, bottom <= 1 else {
      throw CraftError.invalid("Choose a nonempty RAW crop inside the image.")
    }
  }

  package func rectangle(width: Int, height: Int) -> IntRect {
    let x = min(width - 1, Int((left * Float(width)).rounded()))
    let y = min(height - 1, Int((top * Float(height)).rounded()))
    let endX = max(x + 1, Int((right * Float(width)).rounded()))
    let endY = max(y + 1, Int((bottom * Float(height)).rounded()))
    return IntRect(x: x, y: y, width: endX - x, height: endY - y)
  }
}

/// Sensor settings are separate from the RGB Camera Raw Filter. The original file
/// and selected Apple decoder remain attached to the embedded Smart Object.
public struct RawDevelopment: Codable, Equatable, Sendable {
  public var decoderVersion: String?
  public var temperature: Float?
  public var tint: Float?
  public var exposure: Float = 0
  public var boost: Float = 1
  public var shadowBoost: Float = 1
  public var extendedRange: Float = 0
  public var lensCorrection: Bool?
  public var highlightRecovery: Bool?
  public var crop: RawCropBounds?
  public var geometry: RawGeometrySettings?
  public var adjustments = CameraRawSettings()
  public init() {}
  public func validate() throws {
    for (value,range) in [(temperature,Float(2000)...50000),(tint,Float(-150)...150),(Optional(exposure),Float(-5)...5),(Optional(boost),Float(0)...1),(Optional(shadowBoost),Float(0)...2),(Optional(extendedRange),Float(0)...2)] {
      if let value { guard value.isFinite,range.contains(value) else { throw CraftError.invalid("Invalid RAW sensor setting.") } }
    }
    if let decoderVersion { guard !decoderVersion.isEmpty,decoderVersion.utf8.count <= 64,decoderVersion.utf8.allSatisfy({ (32...126).contains($0) }) else { throw CraftError.invalid("Invalid RAW decoder version.") } }
    try crop?.validate()
    try geometry?.validate()
    try adjustments.validate()
  }
  public static func decodeJSON(_ data: Data, base: Self = .init()) throws -> Self {
    guard data.count <= 32768, let values = try JSONSerialization.jsonObject(with:data) as? [String:Any],
      Set(values.keys).isSubset(of:["decoderVersion","temperature","tint","exposure","boost","shadowBoost","extendedRange","lensCorrection","highlightRecovery","crop","geometry","adjustments"]) else { throw CraftError.invalid("Invalid RAW development settings.") }
    var result = base
    for (key,value) in values {
      switch key {
      case "adjustments": result.adjustments = try CameraRawSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      case "geometry":
        result.geometry = value is NSNull ? nil : try RawGeometrySettings.decode(value, base: result.geometry ?? .init())
      case "crop":
        if value is NSNull { result.crop = nil }
        else {
          guard let fields = value as? [String:Any], Set(fields.keys) == ["left", "top", "right", "bottom"] else {
            throw CraftError.invalid("A RAW crop needs left, top, right and bottom coordinates.")
          }
          result.crop = try JSONDecoder().decode(RawCropBounds.self, from: JSONSerialization.data(withJSONObject: fields))
        }
      case "decoderVersion":
        if value is NSNull { result.decoderVersion = nil }
        else { guard let text = value as? String else { throw CraftError.invalid("decoderVersion must be a string or null.") }; result.decoderVersion = text }
      case "lensCorrection", "highlightRecovery":
        let flag: Bool?
        if value is NSNull { flag = nil }
        else { guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw CraftError.invalid("\(key) must be boolean or null.") }; flag = n.boolValue }
        if key == "lensCorrection" { result.lensCorrection = flag } else { result.highlightRecovery = flag }
      default:
        let number: Float?
        if value is NSNull && ["temperature","tint"].contains(key) { number = nil }
        else { guard let n = value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else { throw CraftError.invalid("\(key) must be numeric.") }; number = n.floatValue }
        switch key {
        case "temperature": result.temperature = number
        case "tint": result.tint = number
        case "exposure": result.exposure = number!
        case "boost": result.boost = number!
        case "shadowBoost": result.shadowBoost = number!
        case "extendedRange": result.extendedRange = number!
        default: break
        }
      }
    }
    try result.validate(); return result
  }
}
