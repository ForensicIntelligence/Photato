import Foundation

/// PSD `lclr` identifiers (Adobe sheet-color block; psd-tools SheetColorType).
public enum LayerColorLabel: UInt16, CaseIterable, Sendable, Codable {
  case none = 0
  case red, orange, yellow, green, blue, violet, gray, seafoam, indigo, magenta, fuchsia
  public var title: String { String(describing: self).capitalized }
}

extension Layer {
  /// Unknown or extended records remain untouched unless the user changes the label.
  public var colorLabel: LayerColorLabel? {
    get {
      guard let data = sourceTags?["lclr"] else { return LayerColorLabel.none }
      let bytes = [UInt8](data)
      guard bytes.count == 8 else { return nil }
      return LayerColorLabel(rawValue: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
    }
    set {
      guard let newValue else { return }
      var tags = sourceTags ?? [:]
      var bytes = [UInt8](tags["lclr"] ?? Data(repeating: 0, count: 8))
      if bytes.count != 8 { bytes = Array(repeating: 0, count: 8) }
      bytes[0] = UInt8(newValue.rawValue >> 8)
      bytes[1] = UInt8(newValue.rawValue & 255)
      tags["lclr"] = Data(bytes)
      sourceTags = tags
    }
  }
}

extension BlendMode {
  /// Mathematical neutral source in the working blend space. Photoshop's exact
  /// integer-depth rounding remains an independent qualification requirement.
  public var neutralFillValue: Float? {
    switch self {
    case .darken, .multiply, .colorBurn, .linearBurn, .darkerColor, .divide: 1
    case .lighten, .screen, .colorDodge, .linearDodge, .lighterColor,
      .difference, .exclusion, .subtract:
      0
    case .overlay, .softLight, .hardLight, .vividLight, .linearLight, .pinLight: 0.5
    default: nil
    }
  }
}

public struct NewPixelLayerOptions: Equatable, Sendable, Codable {
  public var name: String
  public var color: LayerColorLabel = .none
  public var mode: BlendMode = .normal
  public var opacity: Float = 1
  public var clipped = false
  public var neutralFill = false
  public init(name: String) { self.name = name }

  public func layer(in document: CraftDocument) throws -> Layer {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf16.count <= 65_535, opacity.isFinite, (0...1).contains(opacity)
    else { throw CraftError.invalid("Enter a layer name and an opacity from 0% to 100%.") }
    var fill = Pixel.clear
    if neutralFill {
      guard let value = mode.neutralFillValue else {
        throw CraftError.invalid("This blending mode has no neutral fill color.")
      }
      let encoded = document.depth == .f32 ? SRGBTransfer.encoded(value) : value
      fill = Pixel(encoded, encoded, encoded)
    }
    var layer = Layer(
      name: name,
      content: .raster(
        try Surface(
          width: document.width, height: document.height, depth: document.depth, fill: fill)))
    layer.opacity = opacity
    layer.blendMode = mode
    if color != .none { layer.colorLabel = color }
    layer.clipped = clipped ? true : nil
    return layer
  }
}

extension CraftDocument {
  public var suggestedPixelLayerName: String {
    suggestedLayerName(base: "Layer")
  }
  public var suggestedGroupName: String { suggestedLayerName(base: "Group") }
  public func suggestedLayerName(base: String) -> String {
    let names = Set(layers.map(\.name))
    var number = 1
    while names.contains("\(base) \(number)") { number += 1 }
    return "\(base) \(number)"
  }

  mutating func insertNewLayer(_ incoming: Layer, below: Bool = false) throws {
    guard layers.count < LayerLimits.maximumLayers, !layers.contains(where: { $0.id == incoming.id }) else {
      throw CraftError.invalid("Layer limit or duplicate identifier.")
    }
    var layer = incoming
    var insertion = layers.count
    if let active = activeIndex {
      let target = layers[active]
      layer.parentID = !below && target.isGroup ? target.id : target.parentID
      if below {
        let subtree = subtreeIDs(target.id)
        insertion = layers.firstIndex { subtree.contains($0.id) } ?? active
      } else {
        insertion = target.isGroup ? active : active + 1
      }
    }
    if let parent = layer.parentID, isLocked(parent) {
      throw CraftError.invalid("Unlock the parent group before adding layers.")
    }
    if layer.isClipped {
      guard layers[..<insertion].contains(where: { $0.parentID == layer.parentID && !$0.isClipped })
      else {
        throw CraftError.invalid("A clipping mask needs a base layer below it in the same group.")
      }
    }
    if insertion==0,layers.first?.isBackground==true{insertion=1}
    layers.insert(layer, at: insertion)
    activeLayerID = layer.id
  }
}
