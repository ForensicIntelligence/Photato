import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class InkChannelOptionsDraft: Identifiable {
  let id = UUID()
  let source: CraftDocument
  let plateID: UUID
  let creating: Bool
  var name: String
  var color: Pixel
  var solidity: Float
  var density: Float = 0
  init(document: CraftDocument, plate: InkPlate?) {
    source = document; plateID = plate?.id ?? UUID(); creating = plate == nil
    let names = Set(document.colorChannelNames); var number = 1
    while names.contains("Spot Color \(number)") { number += 1 }
    name = plate?.name ?? "Spot Color \(number)"; color = plate?.color ?? .black; solidity = plate?.solidity ?? 0
  }
}

extension EditorStore {
  var effectiveInkTargets: [InkChannelTarget] {
    let retained = document.inkChannelTargets.filter { inkTargets.contains($0) }
    return retained.isEmpty ? document.inkChannelTargets : retained
  }
  var effectiveInkVisibility: Set<InkChannelTarget>? {
    guard let inkVisibility else { return nil }
    let retained = inkVisibility.intersection(document.inkChannelTargets)
    return retained.isEmpty ? nil : retained
  }
  var visibleInkTargets: Set<InkChannelTarget> { effectiveInkVisibility ?? Set(document.inkChannelTargets) }
  var canEditInkChannels: Bool {
    document.inkMode != nil && canSelectComponentTarget && historyOperation == nil
      && (document.colorMode == .multichannel || activeLayer.map { !document.isImageLocked($0.id) } == true)
      && !editingMask && editingChannel == nil && !smartFilterMaskEditing
  }
  func inkChannelName(_ target: InkChannelTarget) -> String {
    switch target {
    case .duotone: return "Duotone"
    case .plate(let id):
      guard case .multichannel(let r) = document.inkMode else { return "Ink" }
      return r.plates.first(where: { $0.id == id })?.name ?? "Ink"
    }
  }
  func selectInkChannels(_ targets: Set<InkChannelTarget>) throws {
    guard document.inkMode != nil, canSelectComponentTarget, document.quickMask == nil,
      targets.isSubset(of: Set(document.inkChannelTargets)) else { throw CraftError.invalid("Finish the current interaction and choose valid ink channels.") }
    finishNumericField(); finishLayerName()
    alphaEditingID = nil; alphaOverlay = false; componentTarget = .composite
    modeComponentTargets = []; modeComponentVisibility = nil; maskEditingLayerID = nil; smartFilterMaskEditing = false; clearMaskView()
    inkTargets = targets; inkVisibility = targets.isEmpty ? nil : targets
    render()
  }
  func setInkVisibility(_ targets: Set<InkChannelTarget>) throws {
    guard document.inkMode != nil, canChangeChannelVisibility, !targets.isEmpty,
      targets.isSubset(of: Set(document.inkChannelTargets)) else { throw CraftError.invalid("Choose at least one valid visible ink channel.") }
    inkVisibility = targets; render()
  }
  func routeInkChannels(_ command: Command) throws -> Command {
    guard document.inkMode != nil, editingChannel == nil, !editingMask else { return command }
    let targets = effectiveInkTargets
    switch command {
    case .stroke(_, let points, let brush): return .inkChannel(.edit(targets, .stroke(points, brush)))
    case .fill(_, let color): return .inkChannel(.edit(targets, .fill(unit(color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722), color.a)))
    case .clear: return .inkChannel(.edit(targets, .fill(1, 1)))
    case .applyAdjustment(_, .invert): return .inkChannel(.edit(targets, .invert))
    case .applyFilter(_, let filter): return .inkChannel(.edit(targets, .filter(filter)))
    default: return command
    }
  }
  func performInkChannel(_ command: InkChannelCommand) {
    guard canEditInkChannels else { return }; performGeometry(.inkChannel(command))
  }
  func beginInkChannelOptions(_ id: UUID? = nil) {
    guard canEditInkChannels, case .multichannel(let raster) = document.inkMode else { return }
    let plate = id.flatMap { id in raster.plates.first { $0.id == id } }
    guard id == nil || plate != nil else { return }
    inkChannelOptions = .init(document: document, plate: plate)
  }
  func commitInkChannelOptions() {
    guard let draft = inkChannelOptions else { return }
    let source = draft.source, id = draft.plateID, creating = draft.creating, name = draft.name,
      color = draft.color, solidity = draft.solidity, density = draft.density
    inkChannelOptions = nil
    performGeometry(label: creating ? "New Spot Channel" : "Spot Channel Options", prepare: { document in
      guard document == source else { throw CraftError.invalid("The source changed. Reopen Channel Options.") }
      if creating {
        return .inkChannel(.create(.init(id: id, name: name, color: color, solidity: solidity,
          samples: try InkPlane(width: document.width, height: document.height, depth: document.depth, value: density))))
      }
      return .inkChannel(.options(id, name, color, solidity))
    }, onSuccess: { [weak self] in try? self?.selectInkChannels([.plate(id)]) })
  }
  func loadSelectedInkChannel(mode: SelectionMode = .replace, invert: Bool = false) {
    guard let target = effectiveInkTargets.first else { return }; performInkChannel(.loadSelection(target, mode, invert))
  }
}
