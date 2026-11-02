import Foundation
import PhotoCraftCore

/// Adobe image resources1037 (angle) and1049 (altitude), shared with every PSD mode writer.
enum PSDGlobalLight {
  static func angle(_ value: Double) -> Double {
    let result = value.truncatingRemainder(dividingBy: 360)
    return result == 0 ? 0 : result < 0 ? result + 360 : result
  }
  static func read(_ blocks: [PSDImageResources.Block]) throws -> GlobalLight? {
    let angles = blocks.filter { $0.id == 1037 }, altitudes = blocks.filter { $0.id == 1049 }
    guard angles.count <= 1, altitudes.count <= 1 else { throw CraftError.invalid("Duplicate Photoshop Global Light resources.") }
    guard !angles.isEmpty || !altitudes.isEmpty else { return nil }
    func integer(_ block: PSDImageResources.Block?, fallback: Double) throws -> Double {
      guard let block else { return fallback }
      guard block.data.count == 4 else { throw CraftError.invalid("Invalid Photoshop Global Light resource length.") }
      var r = PSDReader(data: block.data); return Double(try r.i32())
    }
    let light = try GlobalLight(angle: integer(angles.first, fallback: 120), altitude: integer(altitudes.first, fallback: 30))
    try light.validate(); return light
  }
  static func exportLight(_ document: CraftDocument) throws -> GlobalLight? {
    let light: GlobalLight?
    if let explicit = document.globalLight { light = explicit }
    else {
      let inherited = document.layers.compactMap { layer -> GlobalLight? in
        guard let style = layer.style, style.effects.contains(where: { [.dropShadow, .innerShadow].contains($0.kind) && $0.useGlobalLight }) else { return nil }
        return GlobalLight(angle: angle(style.lightAngle), altitude: style.lightAltitude)
      }
      if let first = inherited.first {
        guard inherited.allSatisfy({ $0 == first }) else { throw CraftError.unsupported("Choose one document Global Light before saving these different legacy shared-light settings as PSD/PSB.") }
        light = first
      } else { light = try read(PSDImageResources.blocks(document.sourceMetadata?["psdResources"] ?? Data())) }
    }
    guard let light else { return nil }
    try light.validate()
    guard angle(light.angle).rounded() == angle(light.angle), light.altitude.rounded() == light.altitude else {
      throw CraftError.unsupported("Photoshop Global Light resources store whole degrees. Keep fractional shared-light settings in Photato format.")
    }
    return GlobalLight(angle: angle(light.angle), altitude: light.altitude)
  }
  static func applying(_ resources: Data, document: CraftDocument) throws -> Data {
    guard let light = try exportLight(document) else { return resources }
    let values = [1037: light.angle, 1049: light.altitude]
    var result = Data(), written = Set<Int>()
    for block in try PSDImageResources.blocks(resources) {
      guard let value = values[block.id] else { result.append(block.raw); continue }
      guard written.insert(block.id).inserted else { continue }
      var w = PSDWriter(); w.n(Int(value), 4)
      // Keep resource order, Pascal name and padding when updating this fixed-size field.
      if block.data.count == 4 {
        var raw = block.raw; raw.replaceSubrange((raw.count - 4)..<raw.count, with: w.data); result.append(raw)
      } else { result.append(PSDImageResources.block(block.id, data: w.data)) }
    }
    for id in [1037, 1049] where !written.contains(id) {
      var w = PSDWriter(); w.n(Int(values[id]!), 4); result.append(PSDImageResources.block(id, data: w.data))
    }
    return result
  }
}

/// Older native files retained Photoshop resources without promoting shared light.
/// Adopt them only when doing so preserves every participating legacy style.
public enum GlobalLightInput {
  public static func adoptingLegacyLight(_ document: CraftDocument) throws -> CraftDocument {
    guard document.globalLight == nil,
      let data = document.sourceMetadata?["psdResources"],
      let blocks = try? PSDImageResources.blocks(data),
      let light = try? PSDGlobalLight.read(blocks) else { return document }
    for layer in document.layers {
      guard let style = layer.style,
        style.effects.contains(where: { [.dropShadow, .innerShadow, .bevelEmboss].contains($0.kind) && $0.useGlobalLight }) else { continue }
      guard PSDGlobalLight.angle(style.lightAngle) == PSDGlobalLight.angle(light.angle), style.lightAltitude == light.altitude else { return document }
    }
    var result = document; result.globalLight = light; try result.validate(); return result
  }
}
