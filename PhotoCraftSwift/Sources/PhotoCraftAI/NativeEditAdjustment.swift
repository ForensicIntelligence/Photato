import Foundation

/// Values offered for review, never arbitrary command arguments or model targets.
public struct NativeEditAdjustment: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case exposure, brightnessContrast, hueSaturation, vibrance
    public var title: String {
      switch self {
      case .exposure: "Exposure"
      case .brightnessContrast: "Brightness/Contrast"
      case .hueSaturation: "Hue/Saturation"
      case .vibrance: "Vibrance"
      }
    }
    public var parameters: [Parameter] {
      switch self {
      case .exposure: [.init("exposure", "Exposure", -20, 20, 0, "EV"),
        .init("offset", "Offset", -0.5, 0.5, 0), .init("gammaCorrection", "Gamma Correction", 0.01, 9.99, 1)]
      case .brightnessContrast: [.init("brightness", "Brightness", -150, 150, 0, integer: true),
        .init("contrast", "Contrast", -100, 100, 0, integer: true)]
      case .hueSaturation: [.init("hue", "Hue", -180, 180, 0, "°", integer: true),
        .init("saturation", "Saturation", -100, 100, 0, "%", integer: true),
        .init("lightness", "Lightness", -100, 100, 0, "%", integer: true)]
      case .vibrance: [.init("vibrance", "Vibrance", -100, 100, 0, integer: true),
        .init("saturation", "Saturation", -100, 100, 0, "%", integer: true)]
      }
    }
  }
  public struct Parameter: Equatable, Sendable {
    public let name: String, title: String, unit: String
    public let minimum: Double, maximum: Double, neutral: Double
    public let integer: Bool
    init(_ name: String, _ title: String, _ minimum: Double, _ maximum: Double,
      _ neutral: Double, _ unit: String = "", integer: Bool = false) {
      self.name = name; self.title = title; self.minimum = minimum; self.maximum = maximum
      self.neutral = neutral; self.unit = unit; self.integer = integer
    }
  }
  public let operation: Kind
  public let parameters: [String: Double]
  public init(_ operation: Kind, parameters: [String: Double]) throws {
    self.operation = operation; self.parameters = parameters
    try validate()
  }
  public func validate() throws {
    guard Set(parameters.keys) == Set(operation.parameters.map(\.name)) else {
      throw LocalAIError.unavailable("\(operation.title) needs exactly these values: \(operation.parameters.map(\.name).joined(separator: ", ")).")
    }
    for field in operation.parameters {
      guard let value = parameters[field.name], value.isFinite,
        (field.minimum...field.maximum).contains(value), !field.integer || value.rounded() == value else {
        throw LocalAIError.unavailable("Invalid \(operation.title) \(field.title): use \(field.minimum)…\(field.maximum)\(field.integer ? " in whole numbers" : "").")
      }
    }
  }
  public var detail: String {
    operation.parameters.map { field in
      let value = parameters[field.name].map { String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "?"
      return "\(field.title) \(value)\(field.unit.isEmpty ? "" : " " + field.unit)"
    }.joined(separator: ", ")
  }
  private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    guard Set(container.allKeys.map(\.stringValue)) == ["operation", "parameters"] else {
      throw LocalAIError.unavailable("An adjustment needs only operation and parameters.")
    }
    let kind = try container.decode(Kind.self, forKey: Key(stringValue: "operation")!)
    let values = try container.decode([String: Double].self, forKey: Key(stringValue: "parameters")!)
    try self.init(kind, parameters: values)
  }
  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(operation, forKey: Key(stringValue: "operation")!)
    try container.encode(parameters, forKey: Key(stringValue: "parameters")!)
  }
}
