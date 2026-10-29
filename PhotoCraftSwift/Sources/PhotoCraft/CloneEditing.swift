import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct CloneSlot {
  var token = UUID()
  weak var store: EditorStore?
  weak var target: EditorStore?
  var layerID: UUID?
  var mask = false
  var source: PathPoint?
  var anchor: PathPoint?
  var width = 100.0
  var height = 100.0
  var rotation = 0.0
  var flipHorizontal = false
  var flipVertical = false
  func mapping(at point: PathPoint, target: EditorStore, aligned: Bool) throws -> CloneMapping {
    guard let source else {
      throw CraftError.invalid("Option-click to define a retouching source first.")
    }
    var result = CloneMapping(
      source: source, anchor: aligned && self.target === target ? anchor ?? point : point)
    result.width = width
    result.height = height
    result.rotation = rotation
    result.flipHorizontal = flipHorizontal
    result.flipVertical = flipVertical
    _ = try result.transform()
    return result
  }
}

@MainActor @Observable final class RetouchSettings {
  var aligned = true
  var sampling = CloneSampling.current
  var ignoreAdjustments = false
  var brush = CloneBrush()
  var toning = ToningOptions()
  var focus = FocusOptions()
  var spotType = SpotHealingType.contentAware
}

@MainActor @Observable final class CloneSources {
  static let shared = CloneSources()
  var slots = Array(repeating: CloneSlot(), count: 5)
  var active = 0
  var clone = RetouchSettings()
  var healing = RetouchSettings()
  var spot = RetouchSettings()
  var dodge = RetouchSettings()
  var burn = RetouchSettings()
  var sponge = RetouchSettings()
  var blur = RetouchSettings()
  var sharpen = RetouchSettings()
  var smudge = RetouchSettings()
  // Source-compatible accessors for Clone Stamp callers.
  var aligned: Bool {
    get { clone.aligned }
    set { clone.aligned = newValue }
  }
  var sampling: CloneSampling {
    get { clone.sampling }
    set { clone.sampling = newValue }
  }
  var ignoreAdjustments: Bool {
    get { clone.ignoreAdjustments }
    set { clone.ignoreAdjustments = newValue }
  }
  var brush: CloneBrush {
    get { clone.brush }
    set { clone.brush = newValue }
  }
  var linkedScale = true
  var showOverlay = true
  var overlayOpacity: Float = 0.5
  var clippedOverlay = true
  var autoHideOverlay = true
  var invertOverlay = false
  var overlayBlend = CloneOverlayBlend.normal
  var slot: CloneSlot { slots[min(4, max(0, active))] }
}

enum CloneOverlayBlend: String, CaseIterable {
  case normal = "Normal"
  case darken = "Darken"
  case lighten = "Lighten"
  case difference = "Difference"
  var cgMode: CGBlendMode {
    switch self {
    case .normal: .normal
    case .darken: .darken
    case .lighten: .lighten
    case .difference: .difference
    }
  }
}

struct CloneSourceRequest: Sendable {
  let document: CraftDocument
  let layerID: UUID
  let sampling: CloneSampling
  let ignoreAdjustments: Bool
  let mask: Bool
  var target: CraftDocument? = nil
  func sample() throws -> CloneSample {
    let sampled = try Renderer.cloneSample(
      in: document, layerID: layerID, sampling: sampling, ignoreAdjustments: ignoreAdjustments,
      mask: mask)
    guard !mask, let target else { return sampled }
    return CloneSample(
      surface: try ColorManagement.converted(sampled.surface, from: document, to: target),
      transform: sampled.transform, outside: sampled.outside)
  }
}
struct CloneDraft: Sendable {
  let token = UUID()
  let layerID: UUID
  let slot: Int
  let sourceToken: UUID
  let mapping: CloneMapping
  let brush: CloneBrush
  let mask: Bool
  let aligned: Bool
  var focus: FocusTool?
  var focusOptions = FocusOptions()
  var focusForeground = Pixel.black
  var toning: ToningTool?
  var toningOptions = ToningOptions()
  var healing = false
  var spot: SpotHealingType?
  var destination: CloneSample?
  var sample: CloneSample?
  var points: [StrokePoint]
  var commitRequested = false
  var command: Command? {
    if let toning {
      return .toning(
        layerID,
        ToningStroke(tool: toning, options: toningOptions, brush: brush, points: points, mask: mask)
      )
    }
    guard let sample else { return nil }
    if let focus {
      return .focus(
        layerID,
        FocusStroke(
          tool: focus, options: focusOptions, brush: brush, points: points, mask: mask,
          foreground: focusForeground, sample: sample))
    }
    if let spot {
      return .spotHealing(
        layerID,
        SpotHealingStroke(sample: sample, brush: brush, points: points, kind: spot, mask: mask))
    }
    let stroke = CloneStroke(
      source: sample, mapping: mapping, brush: brush, points: points, mask: mask)
    return healing
      ? .healingBrush(layerID, HealingStroke(stroke: stroke, destination: destination))
      : .cloneStamp(layerID, stroke)
  }
  var previewCommand: Command? {
    guard spot != nil else { return command }
    guard let marker = try? Surface(width: 1, height: 1, depth: .f32, fill: .black) else {
      return nil
    }
    var markerBrush = brush
    markerBrush.opacity = 0.5
    markerBrush.mode = .normal
    return .cloneStamp(
      layerID,
      CloneStroke(
        source: .init(surface: marker, outside: .black),
        mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: markerBrush,
        points: points, mask: mask))
  }

}
struct CloneOverlayKey: Equatable {
  let sourceID: UUID
  let revision: Int
  let layerID: UUID
  let sampling: CloneSampling
  let ignoreAdjustments: Bool
  let mask: Bool
  let invert: Bool
}
struct CloneOverlayImage {
  let image: CGImage
  let transform: Transform2D
  var outside: Pixel = .clear
}

extension EditorStore {
  var retouchSettings: RetouchSettings {
    switch tool {
    case .blur: cloneState.blur
    case .sharpen: cloneState.sharpen
    case .smudge: cloneState.smudge
    case .dodge: cloneState.dodge
    case .burn: cloneState.burn
    case .sponge: cloneState.sponge
    case .spotHealing: cloneState.spot
    case .healingBrush: cloneState.healing
    default: cloneState.clone
    }
  }

  var canClone: Bool {
    guard !smartFilterMaskEditing, !geometryBusy, !hasToneDraft, transformDraft == nil, let layer = activeLayer,
      !(editingMask ? document.isLocked(layer.id) : document.isImageLocked(layer.id))
    else { return false }
    if editingMask { return true }
    if case .raster = layer.content { return true }
    return false
  }
  func setCloneSource(at point: PathPoint) {
    guard !smartFilterMaskEditing, !geometryBusy, !hasToneDraft, transformDraft == nil, let layer = activeLayer,
      point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
      point.x < Double(document.width), point.y < Double(document.height)
    else { return }
    var slot = cloneState.slot
    slot.token = UUID()
    slot.source = point
    slot.anchor = nil
    slot.target = nil
    slot.store = self
    slot.layerID = layer.id
    slot.mask = editingMask
    cloneState.slots[cloneState.active] = slot
    status = "Clone Source \(cloneState.active + 1) set"
    refreshCloneOverlay()
  }
  func cloneRequest() throws -> CloneSourceRequest {
    let slot = cloneState.slot
    guard let source = slot.store, slot.source != nil, let layerID = slot.layerID else {
      throw CraftError.invalid("Option-click an open image to define a retouching source first.")
    }
    guard slot.mask == editingMask else {
      throw CraftError.invalid(
        "Sample a pixel mask to clone onto a mask, or sample image pixels to clone onto a pixel layer."
      )
    }
    return CloneSourceRequest(
      document: source.document, layerID: layerID, sampling: retouchSettings.sampling,
      ignoreAdjustments: retouchSettings.ignoreAdjustments, mask: slot.mask, target: document)
  }
  func beginClone(_ point: StrokePoint, alternate: Bool = false) {
    guard canClone, let layerID = activeLayer?.id else {
      if !hasToneDraft && !geometryBusy {
        error = "Select an unlocked pixel layer or pixel mask for retouching."
      }
      return
    }
    do {
      if let selected = tool.toningTool {
        let kind: ToningTool =
          alternate && selected != .sponge ? (selected == .dodge ? .burn : .dodge) : selected
        try retouchSettings.brush.validate()
        cloneDraft = CloneDraft(
          layerID: layerID, slot: cloneState.active, sourceToken: cloneState.slot.token,
          mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: retouchSettings.brush,
          mask: editingMask, aligned: false, toning: kind, toningOptions: retouchSettings.toning,
          points: [point])
        status = kind.rawValue
        render()
        return
      }
      let focus = tool.focusTool
      var focusOptions = retouchSettings.focus
      if focus == .smudge && alternate { focusOptions.fingerPainting.toggle() }
      let automatic = tool == .spotHealing || focus != nil
      let title = tool.rawValue
      let request =
        automatic
        ? CloneSourceRequest(
          document: document, layerID: layerID,
          sampling: focus != nil
            ? (focusOptions.sampleAllLayers ? .all : .current) : retouchSettings.sampling,
          ignoreAdjustments: false, mask: editingMask) : try cloneRequest()
      let mapping =
        automatic
        ? CloneMapping(source: .init(0, 0), anchor: .init(0, 0))
        : try cloneState.slot.mapping(
          at: PathPoint(point.x, point.y), target: self, aligned: retouchSettings.aligned)
      try retouchSettings.brush.validate()
      let healing = tool == .healingBrush
      let destinationRequest =
        healing && retouchSettings.sampling != .current && !editingMask
        ? CloneSourceRequest(
          document: document, layerID: layerID, sampling: retouchSettings.sampling,
          ignoreAdjustments: retouchSettings.ignoreAdjustments, mask: false) : nil
      let draft = CloneDraft(
        layerID: layerID, slot: cloneState.active, sourceToken: cloneState.slot.token,
        mapping: mapping,
        brush: retouchSettings.brush, mask: editingMask,
        aligned: !automatic && retouchSettings.aligned,
        focus: focus, focusOptions: focusOptions, focusForeground: brush.color,
        healing: healing, spot: tool == .spotHealing ? retouchSettings.spotType : nil,
        points: [point])
      cloneDraft = draft
      if automatic { render() }
      status = "Preparing \(title)…"
      clonePrepareTask?.cancel()
      clonePrepareTask = Task { [weak self] in
        let worker = Task.detached(priority: .userInitiated) {
          (try request.sample(), try destinationRequest?.sample())
        }
        do {
          let sample = try await withTaskCancellationHandler(
            operation: { try await worker.value }, onCancel: { worker.cancel() })
          guard let self, !Task.isCancelled, cloneDraft?.token == draft.token else { return }
          cloneDraft?.sample = sample.0
          cloneDraft?.destination = sample.1
          status = title
          if cloneDraft?.commitRequested == true { commitClone() } else { render() }
        } catch is CancellationError {} catch {
          guard let self, cloneDraft?.token == draft.token else { return }
          cloneDraft = nil
          self.error = error.localizedDescription
          render()
        }
      }
    } catch { self.error = error.localizedDescription }
  }
  func extendClone(_ point: StrokePoint) {
    guard var draft = cloneDraft, !draft.commitRequested else { return }
    guard draft.points.count < 100_000 else {
      cancelClone()
      error = "Retouching stroke is too long."
      return
    }
    draft.points.append(point)
    cloneDraft = draft
    if draft.command != nil || draft.spot != nil { render() }
  }
  func finishClone() {
    guard cloneDraft != nil else { return }
    cloneDraft?.commitRequested = true
    if cloneDraft?.command != nil { commitClone() }
  }
  func commitClone() {
    guard let draft = cloneDraft, let command = draft.command else { return }
    cloneDraft = nil
    performGeometry(command) { [weak self] in
      guard let self else { return }
      if draft.aligned {
        // Do not rewrite a source that the user replaced in another document.
        if cloneState.slots[draft.slot].token == draft.sourceToken {
          cloneState.slots[draft.slot].anchor = draft.mapping.anchor
          cloneState.slots[draft.slot].target = self
        }
      }
      cloneOverlayKey = nil
    }
  }
  func cancelClone() {
    guard cloneDraft != nil else { return }
    clonePrepareTask?.cancel()
    cloneDraft = nil
    render()
    status = "Retouching cancelled"
  }
  func refreshCloneOverlay() {
    guard tool.samplesRetouchSource, cloneDraft == nil, cloneState.showOverlay else { return }
    let slot = cloneState.slot
    guard let source = slot.store, let layerID = slot.layerID, let request = try? cloneRequest()
    else {
      cloneOverlay = nil
      cloneOverlayKey = nil
      return
    }
    let key = CloneOverlayKey(
      sourceID: source.identity, revision: source.revision, layerID: layerID,
      sampling: retouchSettings.sampling, ignoreAdjustments: retouchSettings.ignoreAdjustments,
      mask: slot.mask, invert: cloneState.invertOverlay)
    guard key != cloneOverlayKey else { return }
    cloneOverlayKey = key
    cloneOverlay = nil
    cloneOverlayTask?.cancel()
    cloneOverlayTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        let sample = try request.sample()
        var surface = sample.surface
        var outside = sample.outside
        if key.mask {
          try surface.mapPixels(in: .init(x: 0, y: 0, width: surface.width, height: surface.height))
          {
            _, _, p in Pixel(unit(p.r), unit(p.r), unit(p.r))
          }
        }
        if key.invert {
          try surface.mapPixels(in: .init(x: 0, y: 0, width: surface.width, height: surface.height))
          {
            _, _, p in Pixel(1 - p.r, 1 - p.g, 1 - p.b, p.a)
          }
          outside = Pixel(1 - outside.r, 1 - outside.g, 1 - outside.b, outside.a)
        }
        return CloneOverlayImage(
          image: try key.mask
            ? RasterIO.displayImage(surface)
            : ColorManagement.displayImage(surface, in: request.target ?? request.document),
          transform: sample.transform, outside: outside)
      }
      do {
        let overlay = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        guard let self, !Task.isCancelled, cloneOverlayKey == key else { return }
        cloneOverlay = overlay
      } catch { if let self, cloneOverlayKey == key { cloneOverlay = nil } }
    }
  }
}
