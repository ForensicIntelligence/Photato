import Foundation

/// Duotone's sole gray source or an independent Multichannel printing plate.
public enum InkChannelTarget: Codable, Equatable, Hashable, Sendable {
  case duotone
  case plate(UUID)
  public var key: String { switch self { case .duotone: "duotone"; case .plate(let id): id.uuidString } }
  public var inverted: Bool { if case .plate = self { return true }; return false }
}
public enum InkChannelOperation: Sendable {
  /// Gray shown in Channels: zero is black/full ink, one is white/paper.
  case fill(Float, Float)
  case stroke([StrokePoint], Brush)
  case invert
  case filter(RasterFilter)
}
public enum InkChannelCommand: Sendable {
  case create(InkPlate)
  case delete(UUID)
  case duplicate(UUID, UUID, String?)
  case move(UUID, Int)
  case options(UUID, String, Pixel, Float)
  /// Numeric data: gray for Duotone, density (zero=paper) for Multichannel.
  case write(InkChannelTarget, Int, [Float])
  case edit([InkChannelTarget], InkChannelOperation)
  case loadSelection(InkChannelTarget, SelectionMode, Bool)
  public var label: String {
    switch self {
    case .create: "New Spot Channel"
    case .delete: "Delete Channel"
    case .duplicate: "Duplicate Channel"
    case .move: "Channel Order"
    case .options: "Spot Channel Options"
    case .write: "Edit Ink Samples"
    case .loadSelection: "Load Selection"
    case .edit(_, let operation): switch operation {
      case .fill: "Fill Ink Channels"
      case .stroke(_, let brush): brush.erase ? "Erase Ink Channels" : "Paint Ink Channels"
      case .invert: "Invert Ink Channels"
      case .filter(let filter): filter.kind.title
      }
    }
  }
  public static var filters: Set<RasterFilter.Kind> { ModeComponentEdit.filters }
  public func apply(to document: inout CraftDocument) throws {
    try document.validate(); try Task.checkCancellation()
    var result = document
    switch self {
    case .create(let plate):
      try plate.validate()
      guard case .multichannel(var raster) = result.inkMode else { throw CraftError.invalid("New Spot Channel requires Multichannel mode.") }
      raster.plates.append(plate); result.inkMode = .multichannel(raster)
    case .delete(let id):
      var raster = try document.multichannelRaster()
      guard raster.plates.count > 1, let i = raster.plates.firstIndex(where: { $0.id == id }) else { throw CraftError.invalid("Keep at least one ink plate in a Multichannel document.") }
      raster.plates.remove(at: i); result.inkMode = .multichannel(raster)
    case .duplicate(let id, let newID, let name):
      let raster = try document.multichannelRaster()
      guard var plate = raster.plates.first(where: { $0.id == id }) else { throw CraftError.invalid("Ink plate not found.") }
      plate.id = newID; plate.name = name ?? plate.name + " copy"
      try InkChannelCommand.create(plate).apply(to: &result)
    case .move(let id, let destination):
      var raster = try document.multichannelRaster()
      guard let index = raster.plates.firstIndex(where: { $0.id == id }), raster.plates.indices.contains(destination) else { throw CraftError.invalid("Choose a valid ink channel order.") }
      let plate = raster.plates.remove(at: index); raster.plates.insert(plate, at: destination); result.inkMode = .multichannel(raster)
    case .options(let id, let name, let color, let solidity):
      let raster = try document.multichannelRaster()
      guard var plate = raster.plates.first(where: { $0.id == id }) else { throw CraftError.invalid("Ink plate not found.") }
      plate.name = name; plate.color = color; plate.solidity = solidity
      result = try result.replacingInkPlate(plate)
    case .write(let target, let offset, let values):
      try result.setInkChannel(try result.inkChannel(target).replacing(offset: offset, values: values), at: target)
    case .loadSelection(let target, let mode, let invert):
      let pixels = try result.inkChannel(target).surface(inverted: target.inverted)
      let channel = AlphaChannel(name: "Ink", pixels: pixels)
      let mask = try channel.selection(invert: invert)
      result.setCoverageSelection(try mask.combined(with: result.coverageSelection(), mode: mode))
    case .edit(let targets, let operation):
      guard !targets.isEmpty, targets.count <= MultichannelRaster.maximumChannels,
        Set(targets).count == targets.count else { throw CraftError.invalid("Choose distinct ink channels to edit.") }
      // Validate all targets before performing any work; result is committed only
      // after every plane succeeds. Other numeric planes are never reconstructed.
      for target in targets { _ = try document.inkChannel(target) }
      switch operation {
      case .fill(let gray, let opacity):
        guard gray.isFinite, opacity.isFinite, (0...1).contains(gray), (0...1).contains(opacity) else { throw CraftError.invalid("Channel fill and opacity must be in0...1.") }
      case .stroke(let points, let brush): try BrushPainter.validate(brush, points: points)
      case .filter(let filter):
        guard Self.filters.contains(filter.kind) else { throw CraftError.unsupported("This filter is not yet implemented for ink channels.") }
        try filter.validate()
      case .invert: break
      }
      for target in targets {
        try Task.checkCancellation()
        let plane = try document.inkChannel(target)
        let edited: InkPlane
        switch operation {
        case .fill(let gray, let opacity):
          edited = try Self.map(plane) { x, y, old in
            let amount = document.selectionCoverage(x: x, y: y) * opacity
            return old * (1 - amount) + (target.inverted ? 1 - gray : gray) * amount
          }
        case .invert:
          edited = try Self.map(plane) { x, y, old in
            let amount = document.selectionCoverage(x: x, y: y)
            return old * (1 - amount) + (1 - old) * amount
          }
        case .stroke, .filter:
          let before = try plane.surface(inverted: target.inverted)
          var proxy = try CraftDocument(width: document.width, height: document.height, depth: document.depth)
          proxy.selection = document.selection; proxy.selectionMask = document.selectionMask
          let channel = AlphaChannel(name: "Ink", pixels: before)
          proxy.alphaChannels = [channel]
          switch operation {
          case .stroke(let points, let brush): try ChannelCommand.stroke(.alpha(channel.id), points, brush).apply(to: &proxy)
          case .filter(let filter): try ChannelCommand.filter(.alpha(channel.id), filter).apply(to: &proxy)
          default: break
          }
          edited = try plane.reconciled(with: proxy.channel(.alpha(channel.id)).pixels, previous: before, inverted: target.inverted)
        }
        try result.setInkChannel(edited, at: target)
      }
    }
    try result.validate(); document = result
  }
  private static func map(_ plane: InkPlane, _ transform: (Int, Int, Float) -> Float) throws -> InkPlane {
    try plane.mapped { x, y, value in unit(transform(x, y, value)) }
  }

}
extension CraftDocument {
  public var inkChannelTargets: [InkChannelTarget] {
    switch inkMode { case .duotone: [.duotone]; case .multichannel(let r): r.plates.map { .plate($0.id) }; case nil: [] }
  }
  public func inkChannel(_ target: InkChannelTarget) throws -> InkPlane {
    switch (target, inkMode) {
    case (.duotone, .duotone(let raster)): return raster.gray
    case (.plate(let id), .multichannel(let raster)):
      guard let plate = raster.plates.first(where: { $0.id == id }) else { throw CraftError.invalid("Ink plate not found.") }; return plate.samples
    default: throw CraftError.invalid("The ink channel does not exist in this document mode.")
    }
  }
  public func multichannelRaster() throws -> MultichannelRaster {
    guard case .multichannel(let raster) = inkMode else { throw CraftError.invalid("This operation requires Multichannel mode.") }; return raster
  }
  mutating func setInkChannel(_ plane: InkPlane, at target: InkChannelTarget) throws {
    let old = try inkChannel(target); try plane.validate()
    guard plane.width == old.width, plane.height == old.height, plane.depth == old.depth else { throw CraftError.invalid("Ink channel geometry and precision must match the document.") }
    switch (target, inkMode) {
    case (.duotone, .duotone(var raster)):
      if let id = activeLayerID, isImageLocked(id) { throw CraftError.invalid("Unlock the Duotone layer before editing its gray source.") }
      raster.gray = plane; inkMode = .duotone(raster); layers[0].content = .raster(try plane.surface())
    case (.plate(let id), .multichannel(var raster)):
      guard let i = raster.plates.firstIndex(where: { $0.id == id }) else { throw CraftError.invalid("Ink plate not found.") }
      raster.plates[i].samples = plane; inkMode = .multichannel(raster)
    default: throw CraftError.invalid("Ink channel no longer exists.")
    }
  }
}
