import Foundation
import PhotoCraftCore

/// Local colour and contact-shadow matching. Keep all output in ordinary layers
/// so a user can refine the result after switching to a different variation.
public enum Harmonize {
  public enum Variation: Int, CaseIterable, Sendable {
    case subtle = 1, balanced, ambient

    public var name: String {
      switch self {
      case .subtle: "Subtle"
      case .balanced: "Balanced"
      case .ambient: "Ambient"
      }
    }

    var strength: Float {
      switch self {
      case .subtle: 0.35
      case .balanced: 0.65
      case .ambient: 0.9
      }
    }
  }

  static let tag = "PtHz"

  public struct Choices: Equatable, Sendable {
    public let groupID: UUID
    public let selected: Variation?
    public let variations: [Variation]
  }

  public static func foreground(in document: CraftDocument) -> UUID? {
    guard document.colorMode == .rgb, document.restrictedMode == nil, document.inkMode == nil,
      document.animation == nil, document.videoTimeline == nil, !document.isChannelOnly,
      document.layers.count <= LayerLimits.maximumLayers - (2 + Variation.allCases.count * 2),
      let index = document.activeIndex else { return nil }
    let layer = document.layers[index]
    guard layer.parentID == nil, layer.visible, layer.opacity == 1, layer.blendMode == .normal,
      !layer.isBackground, !layer.isClipped, layer.style == nil, layer.video == nil,
      layer.smartObject == nil, layer.warp == nil, layer.sourceProjection == nil,
      case .raster = layer.content, document.isVisible(layer.id), !document.isLocked(layer.id),
      document.layers[..<index].contains(where: { $0.parentID == nil && $0.visible && $0.opacity > 0 }),
      document.layers[(index + 1)...].first(where: { $0.parentID == nil })?.isClipped != true else { return nil }
    return layer.id
  }

  public static func apply(in document: CraftDocument, foregroundID: UUID,
    variation: Variation = .balanced) throws -> Command {
    try Task.checkCancellation()
    try document.validate()
    guard foreground(in: document) == foregroundID, let index = document.activeIndex else {
      throw CraftError.invalid("Select an ordinary pixel layer above a visible background.")
    }
    let original = document.layers[index]
    let preview = try Context(document: document, subject: original, index: index)
    var group = Layer(name: "Harmonize", content: .group(.init()))
    group.sourceTags = [tag: Data([1, 0])]
    var subject = original
    subject.id = UUID()
    subject.name = "Harmonized Subject"
    subject.parentID = group.id
    subject.sourceTags = nil
    subject.linkID = nil
    subject.linkDisabled = nil
    var shadows: [Layer] = [], corrections: [Layer] = []
    for option in Variation.allCases {
      try Task.checkCancellation()
      let cast = try preview.shadow(option, depth: document.depth)
      var shadow = Layer(name: "\(option.name) Shadow", content: .raster(cast))
      shadow.parentID = group.id
      shadow.visible = option == variation
      shadow.blendMode = .multiply
      shadow.x = preview.request.region.x
      shadow.y = preview.request.region.y
      let xScale = Double(preview.request.region.width) / Double(preview.request.width)
      let yScale = Double(preview.request.region.height) / Double(preview.request.height)
      if xScale != 1 || yScale != 1 {
        // PSD can retain this small shadow and its transform as an editable
        // source without baking a canvas-size raster during native editing.
        var source = try CraftDocument(width: cast.width, height: cast.height, depth: document.depth)
        source.workingICC = document.workingICC
        source.layers[0].content = .raster(cast)
        let (object, samples) = try SmartObjectIO.embedded(document: source, in: document)
        shadow.content = .raster(samples)
        shadow.smartObject = object
        shadow.affine = .scale(xScale, yScale)
      }
      shadow.sourceTags = [tag: Data([1, UInt8(option.rawValue + 3)])]
      shadows.append(shadow)

      var correction = Layer(name: "\(option.name) Colour and Tone", content: .adjustment(.curves(preview.curves(option))))
      correction.parentID = group.id
      correction.visible = option == variation
      correction.clipped = true
      correction.sourceTags = [tag: Data([1, UInt8(option.rawValue)])]
      corrections.append(correction)
    }
    var edited = document
    edited.layers[index].visible = false
    edited.layers.insert(contentsOf: shadows + [subject] + corrections + [group], at: index + 1)
    edited.activeLayerID = group.id
    try edited.validate()
    return .regionRetouch(.init(source: document, result: edited, label: "Harmonize"))
  }

  public static func choices(in document: CraftDocument, groupID: UUID? = nil) -> Choices? {
    let targetID = groupID ?? document.activeLayerID
    guard let layer = document.layers.first(where: { $0.id == targetID }),
      let group = layer.isGroup ? layer : document.layers.first(where: { $0.id == layer.parentID }),
      group.isGroup, group.sourceTags?[tag] == Data([1, 0]) else { return nil }
    let children = document.children(of: group.id)
    let available = Variation.allCases.filter { members($0, in: children) != nil }
    guard !available.isEmpty else { return nil }
    let active = available.filter { option in
      members(option, in: children)?.allSatisfy(\.visible) == true
    }
    return Choices(groupID: group.id, selected: active.count == 1 ? active.first : nil, variations: available)
  }

  public static func select(_ variation: Variation, in document: CraftDocument, groupID: UUID) throws -> Command {
    guard let choices = choices(in: document, groupID: groupID), choices.groupID == groupID,
      choices.variations.contains(variation), !document.isLocked(groupID) else {
      throw CraftError.invalid("Choose an available Harmonize variation in an unlocked group.")
    }
    var result = document
    let children = document.children(of: groupID)
    for option in choices.variations {
      guard let layers = members(option, in: children) else { continue }
      for layer in layers {
        guard let index = result.layers.firstIndex(where: { $0.id == layer.id }) else { continue }
        result.layers[index].visible = option == variation
      }
    }
    try result.validate()
    return .regionRetouch(.init(source: document, result: result, label: "Harmonize Variation"))
  }

  private static func members(_ option: Variation, in children: [Layer]) -> [Layer]? {
    let members = children.filter { layer in
      switch layer.content {
      case .adjustment(.curves):
        layer.isClipped && layer.sourceTags?[tag] == Data([1, UInt8(option.rawValue)])
      case .raster:
        layer.sourceTags?[tag] == Data([1, UInt8(option.rawValue + 3)])
      default: false
      }
    }
    return members.count == 2 && members.contains(where: \.isClipped) ? members : nil
  }

  private struct RGBStatistics {
    var sum = SIMD3<Double>.zero
    var squares = SIMD3<Double>.zero
    var weight = 0.0
    var mean: SIMD3<Double> { sum / weight }
    var contrast: Double {
      let variance = squares / weight - mean * mean
      return sqrt(max(0, (variance.x + variance.y + variance.z) / 3))
    }
    var luminance: Double { mean.x * 0.2126 + mean.y * 0.7152 + mean.z * 0.0722 }

    mutating func include(_ pixel: Pixel, weight: Double) {
      guard weight > 0 else { return }
      let value = SIMD3(Double(unit(pixel.r)), Double(unit(pixel.g)), Double(unit(pixel.b)))
      sum += value * weight
      squares += value * value * weight
      self.weight += weight
    }
  }

  private struct Context {
    let request: RasterPreviewRequest
    let matte: Surface
    let source: RGBStatistics
    let scene: RGBStatistics
    let contact: (x: Double, y: Int, width: Double, height: Double)
    let direction: Double

    init(document: CraftDocument, subject: Layer, index: Int) throws {
      guard case .raster(let pixels) = subject.content else { throw CraftError.invalid("Expected a pixel layer.") }
      let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
      let bounds = try subject.coordinateTransform.viewportBounds(width: pixels.width, height: pixels.height, in: canvas)
      guard bounds.width > 0, bounds.height > 0 else { throw CraftError.invalid("The subject is outside the canvas.") }
      let margin = max(4, max(bounds.width, bounds.height) / 4)
      let padded = IntRect(x: bounds.x - margin, y: bounds.y - margin,
        width: bounds.width + 2 * margin, height: bounds.height + 2 * margin)
        .clipped(toWidth: document.width, height: document.height)
      let scale = min(1, 240 / Double(max(padded.width, padded.height)))
      let width = max(1, Int((Double(padded.width) * scale).rounded()))
      let height = max(1, Int((Double(padded.height) * scale).rounded()))
      request = try RasterPreviewRequest(region: padded, width: width, height: height)

      var isolated = document
      isolated.layers = [subject]
      matte = try request.reducing(Renderer.compositeValidated(isolated, region: padded, preferPaged: true))
      var backdrop = document
      backdrop.layers = Array(document.layers[..<index])
      let context = try request.reducing(Renderer.compositeValidated(backdrop, region: padded, preferPaged: true))
      var source = RGBStatistics(), scene = RGBStatistics(), beneath = RGBStatistics()
      var left = RGBStatistics(), right = RGBStatistics()
      var minX = width, maxX = 0, minY = height, maxY = 0
      var lowerEdges = Array(repeating: -1, count: width)
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          let foreground = matte.pixel(x: x, y: y)
          let surrounding = context.pixel(x: x, y: y)
          let subjectWeight = Double(unit(foreground.a))
          let backgroundWeight = Double(unit(surrounding.a))
          let exposed = backgroundWeight * (1 - subjectWeight)
          source.include(foreground, weight: subjectWeight)
          scene.include(surrounding, weight: exposed)
          beneath.include(surrounding, weight: backgroundWeight * subjectWeight)
          if x < width / 2 { left.include(surrounding, weight: exposed) }
          else { right.include(surrounding, weight: exposed) }
          if foreground.a > 0.15 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            lowerEdges[x] = y
          }
        }
      }
      guard source.weight > 0, minX <= maxX, minY <= maxY else {
        throw CraftError.invalid("The subject has no visible coverage in the canvas.")
      }
      guard scene.weight > 0 || beneath.weight > 0 else {
        throw CraftError.invalid("There is no visible background near the subject.")
      }
      self.source = source
      self.scene = scene.weight > 0 ? scene : beneath
      let baseWidth = Double(maxX - minX + 1), baseHeight = Double(maxY - minY + 1)
      let supportedFeet = (minX...maxX).filter { lowerEdges[$0] >= maxY - max(1, Int(baseHeight * 0.07)) }
      let footCenter = Double(supportedFeet.reduce(0, +)) / Double(max(1, supportedFeet.count))
      contact = (footCenter + 0.5, maxY, baseWidth, baseHeight)
      direction = left.weight > 0 && right.weight > 0
        ? min(1, max(-1, (left.luminance - right.luminance) * 3))
        : 0
    }

    func curves(_ option: Variation) -> CurvesAdjustment {
      let contrast = min(0.35, max(-0.35, log((scene.contrast + 0.1) / (source.contrast + 0.1))))
      func channel(_ component: Int) -> CurveChannel {
        let shift = min(0.23, max(-0.23, (scene.mean[component] - source.mean[component]) * 0.75))
        let samples = [0, 64, 128, 192, 255]
        return CurveChannel(samples.map { point in
          let x = Double(point) / 255
          let amount = (shift + (x - 0.5) * contrast) * 4 * x * (1 - x)
          let value = x + amount * Double(option.strength)
          return CurvePoint(point, Int((min(1, max(0, value)) * 255).rounded()))
        })
      }
      return CurvesAdjustment(red: channel(0), green: channel(1), blue: channel(2))
    }

    func shadow(_ option: Variation, depth: PixelDepth) throws -> Surface {
      let w = request.width, h = request.height, baseY = Double(contact.y) + 0.5
      let span = max(1.0, contact.height * (0.13 + Double(option.strength) * 0.16))
      let skew = direction * contact.width * 0.35
      var cast = [Float](repeating: 0, count: w * h)
      for y in 0..<h {
        try Task.checkCancellation()
        let distance = (Double(y) + 0.5 - baseY) / span
        guard (0...1).contains(distance) else { continue }
        let inputY = baseY - distance * (contact.height - 1)
        for x in 0..<w {
          let inputX = Double(x) + 0.5 - skew * distance
          let pixel = RasterGeometry.sample(matte, x: inputX, y: inputY, method: .bilinear)
          cast[y * w + x] = pixel.a * Float(1 - 0.65 * distance)
        }
      }
      let radius = min(12, max(1, Int(contact.width * 0.045)))
      let softened = try Self.blur(cast, width: w, height: h, radius: radius)
      var result = try Surface(width: w, height: h, depth: depth)
      try result.mapPixels(in: .init(x: 0, y: 0, width: w, height: h)) { x, y, _ in
        let dx = (Double(x) + 0.5 - contact.x) / max(2, contact.width * 0.35)
        let dy = (Double(y) + 0.5 - baseY) / max(1, span * 0.24)
        let near = max(0, 1 - dx * dx - dy * dy)
        let alpha = (softened[y * w + x] * 0.3 + Float(near * near) * 0.24) * option.strength
        return Pixel(0.03, 0.03, 0.03, alpha)
      }
      return result
    }

    private static func blur(_ values: [Float], width: Int, height: Int, radius: Int) throws -> [Float] {
      var blurred = values
      let denominator = Float(2 * radius + 1)
      for horizontal in [true, false] {
        let input = blurred, lines = horizontal ? height : width, length = horizontal ? width : height
        for line in 0..<lines {
          try Task.checkCancellation()
          func index(_ offset: Int) -> Int { horizontal ? line * width + offset : offset * width + line }
          func sample(_ offset: Int) -> Float { (0..<length).contains(offset) ? input[index(offset)] : 0 }
          var sum = (-radius...radius).reduce(Float.zero) { $0 + sample($1) }
          for offset in 0..<length {
            blurred[index(offset)] = max(0, sum / denominator)
            sum += sample(offset + radius + 1) - sample(offset - radius)
          }
        }
      }
      return blurred
    }
  }
}
