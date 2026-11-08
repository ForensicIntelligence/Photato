import Foundation

/// Display-only sampled color retained independently of the adjustment's pixel settings.
public struct HueRangeColor: Codable, Equatable, Sendable {
  public var hue: Int
  public var saturation: Int
  public var lightness: Int
  public init(hue: Int, saturation: Int, lightness: Int) {
    self.hue = hue; self.saturation = saturation; self.lightness = lightness
  }
  public func validate() throws {
    guard (0...360).contains(hue), (0...100).contains(saturation), (0...100).contains(lightness) else {
      throw CraftError.invalid("Invalid Hue/Saturation display color.")
    }
  }
  public var pixel: Pixel {
    let rgb = HSLColor.rgb(hue: Float(hue % 360) / 360,
      saturation: Float(saturation) / 100, lightness: Float(lightness) / 100)
    return Pixel(rgb.x, rgb.y, rgb.z)
  }
}
extension HueSaturationAdjustment {
  public var hasRangeDisplayColors: Bool { ranges.contains { $0.displayColor != nil } }
}
extension Adjustment {
  public var hasHueRangeDisplayColors: Bool {
    if case .hueSaturation(let value) = self { return value.hasRangeDisplayColors }
    return false
  }
}
extension CraftDocument {
  public var requiresHueRangeColorArchive: Bool {
    func content(_ value: LayerContent) -> Bool {
      if case .adjustment(let value) = value { return value.hasHueRangeDisplayColors }
      return false
    }
    func layer(_ value: Layer) -> Bool {
      content(value.content) || value.videoKeyframes?.contains {
        $0.content.map { content($0.content) } ?? false
      } == true
    }
    if layers.contains(where: layer) || animation?.frames.contains(where: {
      $0.layers.contains { $0.payload.map { content($0.content) } ?? false }
    }) == true { return true }
    var retained = videoTimeline?.retainedFrameSources ?? []
    if let source = animation?.retainedVideoSource { retained.append(source) }
    while let source = retained.popLast() {
      if source.layers.contains(where: layer) { return true }
      retained.append(contentsOf: source.timeline.retainedFrameSources ?? [])
    }
    return false
  }
}
