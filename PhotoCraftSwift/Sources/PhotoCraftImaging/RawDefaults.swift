import CoreImage
import Foundation
import ImageIO
import PhotoCraftCore

package struct RawDefaults: Codable, Equatable, Sendable {
  package static let maximumRules = 32
  package static let maximumPresetTotal = 512 * 1024
  package static let maximumEncodedBytes = 768 * 1024

  package struct Camera: Codable, Equatable, Hashable, Sendable {
    package var make: String
    package var model: String
    package var serial: String?

    package init(make: String, model: String, serial: String? = nil) {
      self.make = make
      self.model = model
      self.serial = serial
    }

    package var title: String {
      let name = model.lowercased().hasPrefix(make.lowercased()) ? model : "\(make) \(model)"
      guard let serial else { return name }
      return "\(name) (\(serial))"
    }

    var key: Self { .init(make: make.lowercased(), model: model.lowercased(), serial: serial) }
    package var withoutSerial: Self { .init(make: make, model: model) }

    fileprivate func validate() throws {
      guard RawDefaults.validLabel(make), RawDefaults.validLabel(model), serial.map(RawDefaults.validLabel) ?? true else {
        throw CraftError.invalid("Camera defaults require a make and model and an optional body serial number.")
      }
    }
  }

  package struct Choice: Codable, Equatable, Sendable {
    package enum Mode: String, CaseIterable, Codable, Sendable {
      case photato, camera, preset
    }

    package var mode: Mode
    package var name: String?
    package var xmp: Data?

    package init(mode: Mode = .photato, name: String? = nil, xmp: Data? = nil) {
      self.mode = mode
      self.name = name
      self.xmp = xmp
    }

    fileprivate func validate() throws {
      if mode == .preset {
        guard let name, RawDefaults.validLabel(name), let xmp else {
          throw CraftError.invalid("Choose a named Camera Raw XMP preset.")
        }
        try CameraRawXMP.validatePreset(xmp)
      } else if name != nil || xmp != nil {
        throw CraftError.invalid("Only a preset can include Camera Raw XMP.")
      }
    }
  }

  package struct Rule: Codable, Equatable, Sendable {
    package var camera: Camera
    package var choice: Choice

    package init(camera: Camera, choice: Choice) {
      self.camera = camera
      self.choice = choice
    }
  }

  package var master: Choice
  package var useOverrides: Bool
  package var rules: [Rule]

  package init(master: Choice = .init(), useOverrides: Bool = false, rules: [Rule] = []) {
    self.master = master
    self.useOverrides = useOverrides
    self.rules = rules
  }

  package func validate() throws {
    guard rules.count <= Self.maximumRules,
      Set(rules.map { $0.camera.key }).count == rules.count else {
      throw CraftError.invalid("Choose at most 32 camera defaults, with one rule per model or body.")
    }
    let choices = [master] + rules.map(\.choice)
    guard choices.reduce(0, { $0 + ($1.xmp?.count ?? 0) }) <= Self.maximumPresetTotal else {
      throw CraftError.invalid("Camera Raw defaults can store up to 512 KiB of presets.")
    }
    for rule in rules { try rule.camera.validate() }
    for choice in choices { try choice.validate() }
  }

  package func choice(for camera: Camera?) -> Choice {
    guard useOverrides, let camera else { return master }
    return rules.first { $0.camera.key == camera.key }?.choice
      ?? rules.first { $0.camera.key == camera.withoutSerial.key }?.choice
      ?? master
  }

  fileprivate static func validLabel(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.rangeOfCharacter(from: .controlCharacters) == nil
  }
}

extension RawSourceIO {
  package static func cameraIdentity(at url: URL) throws -> RawDefaults.Camera {
    guard recognizes(url),
      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let camera = cameraIdentity(properties) else {
      throw CraftError.invalid("Choose a camera RAW file with a recorded make and model.")
    }
    return camera
  }

  static func cameraIdentity(_ properties: [CFString: Any]?) -> RawDefaults.Camera? {
    func value(_ group: CFString, _ key: CFString) -> String? {
      guard let fields = properties?[group] as? [CFString: Any],
        let text = fields[key] as? String else { return nil }
      let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return RawDefaults.validLabel(label) ? label : nil
    }
    guard let make = value(kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFMake),
      let model = value(kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFModel)
        ?? value(kCGImagePropertyDNGDictionary, kCGImagePropertyDNGUniqueCameraModel) else { return nil }
    let serial = value(kCGImagePropertyExifDictionary, kCGImagePropertyExifBodySerialNumber)
      ?? value(kCGImagePropertyExifAuxDictionary, kCGImagePropertyExifAuxSerialNumber)
      ?? value(kCGImagePropertyDNGDictionary, kCGImagePropertyDNGCameraSerialNumber)
      ?? value(kCGImagePropertyCIFFDictionary, kCGImagePropertyCIFFCameraSerialNumber)
    return .init(make: make, model: model, serial: serial)
  }

  static func cameraISO(_ properties: [CFString: Any]?) -> Double? {
    guard let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
    let ratings = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber]
    let legacyISO = ratings?.first
    let values = [exif[kCGImagePropertyExifISOSpeed] as? NSNumber, legacyISO?.doubleValue == 65_535 ? nil : legacyISO,
      exif[kCGImagePropertyExifRecommendedExposureIndex] as? NSNumber,
      exif[kCGImagePropertyExifStandardOutputSensitivity] as? NSNumber]
    for case let value? in values where CFGetTypeID(value) != CFBooleanGetTypeID() {
      let speed = value.doubleValue
      if speed.isFinite && speed > 0 { return speed }
    }
    return nil
  }

  static func defaultDevelopment(_ choice: RawDefaults.Choice, from data: Data, iso: Double?) throws -> RawDevelopment {
    guard choice.mode != .photato else { return .init() }
    let (raw, _) = try decoder(data)
    var base = RawDevelopment()
    // Leave white balance and the optional corrections with the decoder. Copy
    // its other sensor defaults so the resulting settings can be saved and reopened.
    base.exposure = raw.exposure
    base.boost = raw.boostAmount
    base.shadowBoost = raw.boostShadowAmount
    base.extendedRange = raw.extendedDynamicRangeAmount
    if (try? base.validate()) == nil { base = .init() }
    if let xmp = choice.xmp { return try CameraRawXMP.readPreset(xmp, into: base, iso: iso) }
    return base
  }
}
