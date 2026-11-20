import Foundation
import PhotoCraftCore

/// The Channels panel copies numerical data independently of the current selection or preview.
public enum ChannelDuplication {
  public enum Result: Sendable {
    case edit(Command, channelID: UUID)
    case document(CraftDocument, channelID: UUID)
  }

  public static func sources(in document: CraftDocument) -> [SelectionChannelSource] {
    SelectionChannelSource.choices(in: document, includingComponents: true).filter { source in
      switch source {
      case .alpha, .plate, .duotone: true
      case .component: !document.isChannelOnly && !document.colorMode.isRestricted
      default: false
      }
    }
  }

  private static func isSpot(_ source: SelectionChannelSource, in document: CraftDocument) -> Bool {
    if case .plate = source { return true }
    if case .alpha(let id) = source {
      return document.alphaChannels?.first(where: { $0.id == id })?.spot != nil
    }
    return false
  }

  public static func accepts(_ target: CraftDocument?, source: SelectionChannelSource, in document: CraftDocument) -> Bool {
    let spot = isSpot(source, in: document)
    guard let target else { return !spot || document.depth != .f32 }
    guard target.width == document.width, target.height == document.height, !target.colorMode.isRestricted else { return false }
    if spot {
      guard !target.isChannelOnly, target.inkMode?.mode != .duotone else { return false }
    }
    if case .multichannel(let raster) = target.inkMode {
      let free = raster.plates.count + (target.alphaChannels?.count ?? 0) + (target.quickMask == nil ? 0 : 1) < MultichannelRaster.maximumChannels
      if spot || !free { return free }
    }
    return (target.alphaChannels?.count ?? 0) < target.auxiliaryChannelLimit
  }

  public static func prepare(_ source: SelectionChannelSource, in document: CraftDocument,
    to target: CraftDocument?, name: String, documentName: String = "Untitled", invert: Bool = false) throws -> Result {
    try Task.checkCancellation()
    try document.validate()
    guard sources(in: document).contains(source), accepts(target, source: source, in: document) else {
      throw CraftError.invalid("Choose an individual channel and a matching document with room for a copy.")
    }
    let depth = target?.depth ?? document.depth
    let id = UUID()
    let destinationIsInk: Bool
    if let target { destinationIsInk = target.inkMode?.mode == .multichannel }
    else { destinationIsInk = isSpot(source, in: document) }

    var alpha: AlphaChannel
    switch source {
    case .alpha(let originalID):
      alpha = try document.channel(.alpha(originalID))
      alpha.id = id
      alpha.name = name
      alpha.psdIdentifier = nil
      alpha = try alpha.convertedCoverage(to: depth)
      if invert {
        alpha.pixels = try inverted(alpha.pixels)
        alpha.psdSpotGray = nil
        alpha.psdSelectedGray = nil
      }
      if let ink = alpha.spot, destinationIsInk {
        let gray = try NativeModeRaster(width: document.width, height: document.height, mode: .grayscale, depth: depth)
          .replacingChannel(0, with: alpha.pixels)
        return try plateResult(.init(id: id, name: name, color: ink.color, solidity: ink.solidity,
          samples: gray.inkPlane(component: 0)), source: document, target: target, documentName: documentName)
      }
    case .plate(let originalID):
      guard case .multichannel(let raster) = document.inkMode,
        let plate = raster.plates.first(where: { $0.id == originalID }) else { throw CraftError.invalid("Printing plate not found.") }
      if destinationIsInk {
        return try plateResult(.init(id: id, name: name, color: plate.color, solidity: plate.solidity,
          samples: plate.samples.converted(to: depth, inverted: invert)), source: document, target: target, documentName: documentName)
      }
      let pixels = try plate.samples.surface().quantizedStoredDepth(depth)
      alpha = try .init(id: id, name: name, pixels: invert ? inverted(pixels) : pixels,
        spot: SpotInk(color: plate.color, solidity: plate.solidity))
    case .duotone, .component:
      let pixels = try numeric(source, in: document).quantizedStoredDepth(depth)
      alpha = try .init(id: id, name: name, pixels: invert ? inverted(pixels) : pixels)
    default:
      throw CraftError.invalid("Choose an individual color, ink or saved channel.")
    }

    try alpha.validate(width: document.width, height: document.height, depth: depth)
    if target != nil { return .edit(.channel(.create(alpha)), channelID: id) }

    var result = try newDocument(source: document, name: documentName)
    result.layers = []
    result.activeLayerID = nil
    result.channelOnly = true
    result.alphaChannels = [alpha]
    try result.validate()
    return .document(result, channelID: id)
  }

  private static func numeric(_ source: SelectionChannelSource, in document: CraftDocument) throws -> Surface {
    if case .duotone = source { return try document.inkChannel(.duotone).surface() }
    guard case .component(let component) = source else { throw CraftError.invalid("Color component not found.") }
    if document.layers.count == 1, let layer = document.layers.first, InkModeInput.isAlignedRaster(layer, in: document),
      let native = layer.nativeMode, native.isOpaque {
      let plane = try native.channel(component)
      return native.mode == .cmyk ? try inverted(plane) : plane
    }
    if document.colorMode != .rgb {
      let plane = try ModeChannelPresentation.singleComponent(document, component: component)
      return try plane.mappedStoredSamples(encoding: .sRGB) { p in
        let value = p.r
        return Pixel(value, value, value).quantized(document.depth)
      }.retaggedCoverageStorage(depth: document.depth)
    }
    let specification = ChannelArithmeticSource(documentID: document.id, channel: .component(component))
    let plane = try ChannelArithmeticPreparation.input(specification, destination: document, sources: []).samples
    // Arithmetic uses Float32 scratch even when the original component is integer.
    return try plane.quantizedStoredDepth(document.depth)
  }

  private static func inverted(_ pixels: Surface) throws -> Surface {
    try pixels.mappedStoredSamples { p in
      let value = 1 - p.r
      return Pixel(value, value, value).quantized(pixels.depth)
    }.retaggedCoverageStorage(depth: pixels.depth)
  }

  private static func newDocument(source: CraftDocument, name: String) throws -> CraftDocument {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.count <= 256, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw CraftError.invalid("Enter a valid name for the new document.")
    }
    var result = try CraftDocument(width: source.width, height: source.height, depth: source.depth, name: name)
    result.resolution = source.resolution
    return result
  }

  private static func plateResult(_ plate: InkPlate, source: CraftDocument, target: CraftDocument?,
    documentName: String) throws -> Result {
    try plate.validate()
    if target != nil { return .edit(.inkChannel(.create(plate)), channelID: plate.id) }
    let result = try newDocument(source: source, name: documentName)
      .replacingInkMode(.multichannel(MultichannelRaster(plates: [plate])))
    return .document(result, channelID: plate.id)
  }
}
