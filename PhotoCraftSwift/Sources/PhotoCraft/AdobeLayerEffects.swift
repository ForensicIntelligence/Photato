import CoreFoundation
import Foundation
import PhotoCraftCore

/// Pinned Firefly v2 LayerEffects mapping onto editable native Drop Shadows.
enum AdobeLayerEffects {
  static func parse(_ raw: Any?) throws -> [LayerEffect]? {
    guard let raw else { return nil }
    guard let object = raw as? [String: Any], Set(object.keys).isSubset(of: ["dropShadow"]) else {
      throw AdobeAPIError.invalid("layerEffects must contain the published dropShadow array.")
    }
    guard let values = object["dropShadow"] else { return nil }
    guard let values = values as? [[String: Any]], (1...10).contains(values.count) else {
      throw AdobeAPIError.invalid("dropShadow requires one to10 effects.")
    }
    return try values.map { fields in
      let allowed: Set<String> = ["angle", "antiAliased", "blendMode", "color", "contour", "distance", "enabled", "layerKnocksOut", "noise", "opacity", "size", "spread", "useGlobalLight"]
      guard Set(fields.keys).isSubset(of: allowed) else { throw AdobeAPIError.invalid("Unknown dropShadow property.") }
      func integer(_ key: String, _ range: ClosedRange<Double>, _ fallback: Double) throws -> Double {
        guard let raw = fields[key] else { return fallback }
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
          n.doubleValue.rounded() == n.doubleValue, range.contains(n.doubleValue) else {
          throw AdobeAPIError.invalid("Invalid dropShadow.\(key).")
        }
        return n.doubleValue
      }
      func flag(_ key: String, _ fallback: Bool) throws -> Bool {
        guard let raw = fields[key] else { return fallback }
        guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw AdobeAPIError.invalid("Invalid dropShadow.\(key).") }
        return n.boolValue
      }
      var effect = LayerEffect(.dropShadow)
      effect.angle = try integer("angle", -180...180, effect.angle)
      effect.distance = try integer("distance", 0...30000, effect.distance)
      effect.size = try integer("size", 0...250, effect.size)
      effect.spread = try integer("spread", 0...100, effect.spread)
      effect.opacity = Float(try integer("opacity", 0...100, Double(effect.opacity)*100)/100)
      effect.enabled = try flag("enabled", true)
      effect.useGlobalLight = try flag("useGlobalLight", true)
      var advanced = LayerEffectAdvanced()
      advanced.noise = Float(try integer("noise", 0...100, 0) / 100)
      advanced.antiAlias = try flag("antiAliased", false)
      advanced.knocksOut = try flag("layerKnocksOut", true)
      if let raw = fields["contour"] { advanced.contour = try contour(raw) }
      if advanced != LayerEffectAdvanced() { effect.advanced = advanced }
      if let raw = fields["blendMode"] {
        guard let name = raw as? String,
          let mode = BlendMode.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "_") == name }),
          ![.subtract, .linearLight].contains(mode) else { throw AdobeAPIError.invalid("Invalid dropShadow blendMode.") }
        effect.blendMode = mode
      }
      if let raw = fields["color"] {
        guard let color = raw as? [String: Any], Set(color.keys) == ["rgb"],
          let rgb = color["rgb"] as? [String: Any], Set(rgb.keys) == ["red", "green", "blue"] else {
          throw AdobeAPIError.invalid("Effect color requires rgb red, green and blue integers.")
        }
        let components = try ["red", "green", "blue"].map { key -> Float in
          guard let n = rgb[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
            n.doubleValue.rounded() == n.doubleValue, (0...255).contains(n.doubleValue) else {
            throw AdobeAPIError.invalid("Invalid effect RGB component.")
          }
          return Float(n.doubleValue/255)
        }
        effect.color = Pixel(components[0],components[1],components[2])
      }
      try effect.validate()
      return effect
    }
  }

  private static func contour(_ raw: Any) throws -> EffectContour {
    guard let shape = raw as? [String: Any], Set(shape.keys) == ["name", "curve"],
          shape["name"] as? String == "Custom", let curve = shape["curve"] as? [[String: Any]],
          (2...256).contains(curve.count) else {
      throw AdobeAPIError.invalid("A Custom contour requires 2–256 curve points.")
    }
    var points = [[Float]]()
    var smooth = [Bool]()
    for point in curve {
      guard Set(point.keys) == ["horizontal", "vertical", "continuity"],
            let continuity = point["continuity"] as? NSNumber, CFGetTypeID(continuity) == CFBooleanGetTypeID() else {
        throw AdobeAPIError.invalid("A contour point requires horizontal, vertical and Boolean continuity.")
      }
      let coordinates = try ["horizontal", "vertical"].map { key -> Float in
        guard let value = point[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              (0...255).contains(value.doubleValue) else {
          throw AdobeAPIError.invalid("Contour coordinates must be numbers from 0 through 255.")
        }
        return Float(value.doubleValue / 255)
      }
      points.append(coordinates)
      smooth.append(continuity.boolValue)
    }
    return EffectContour(name: "Custom", points: points, smoothPoints: smooth.contains(false) ? smooth : nil)
  }
}
