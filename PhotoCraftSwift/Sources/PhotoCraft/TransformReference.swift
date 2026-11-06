import AppKit
import PhotoCraftCore
import SwiftUI

extension TransformDraft {
  func sameReferenceGeometry(as other: Self) -> Bool {
    var a = self, b = other
    a.referenceAnchor = .center; b.referenceAnchor = .center
    a.customReferencePoint = nil; b.customReferencePoint = nil
    return a == b
  }
  var sourceReferencePoint: PathPoint {
    if let customReferencePoint { return customReferencePoint }
    let f = referenceAnchor.fractions
    return .init(Double(bounds.x) + Double(bounds.width) * f.0, Double(bounds.y) + Double(bounds.height) * f.1)
  }
  var transformReferencePoint: PathPoint {
    if selection { return selectionReferencePoint }
    if contentAware, customReferencePoint == nil, angle == 0 {
      let f = referenceAnchor.fractions
      return .init(centerX + (f.0 - 0.5) * Double(bounds.width) * scaleX / 100, centerY + (f.1 - 0.5) * Double(bounds.height) * scaleY / 100)
    }
    if customReferencePoint == nil, referenceAnchor == .center { return .init(centerX, centerY) }
    let source = sourceReferencePoint, p = delta.point(source.x, source.y)
    return .init(p.x, p.y)
  }
  func settingReferencePoint(_ point: PathPoint) throws -> Self {
    guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else {
      throw CraftError.invalid("Reference point must be finite and within the supported document coordinates.")
    }
    if customReferencePoint != nil, point == transformReferencePoint { return self }
    let local: PathPoint
    if selection { local = try selectionProjection.inverted().point(point.x, point.y) }
    else { let p = try delta.inverted().point(point.x, point.y); local = .init(p.x, p.y) }
    guard local.x.isFinite, local.y.isFinite, abs(local.x) <= 1e12, abs(local.y) <= 1e12 else {
      throw CraftError.invalid("Reference point cannot be represented by this transform.")
    }
    var next = self; next.customReferencePoint = local; return next
  }
  func transformNumeric(_ key: WritableKeyPath<TransformDraft, Double>, _ value: Double) -> Self {
    if selection { return selectionNumeric(key, value) }
    var next = self
    let pivot = transformReferencePoint, old = self[keyPath: key]
    if key == \.centerX { next.centerX += value - pivot.x; return next }
    if key == \.centerY { next.centerY += value - pivot.y; return next }
    next[keyPath: key] = value
    if proportional, old != 0 {
      if key == \.scaleX { next.scaleY *= value / old }
      if key == \.scaleY { next.scaleX *= value / old }
    }
    if contentAware, customReferencePoint == nil {
      let f = referenceAnchor.fractions
      next.centerX = pivot.x - (f.0 - 0.5) * Double(bounds.width) * next.scaleX / 100
      next.centerY = pivot.y - (f.1 - 0.5) * Double(bounds.height) * next.scaleY / 100
      return next
    }
    // Preserve the established center path exactly when no different origin was chosen.
    if customReferencePoint != nil || referenceAnchor != .center {
      let changed = next.transformReferencePoint
      next.centerX += pivot.x - changed.x; next.centerY += pivot.y - changed.y
    }
    return next
  }
}
@MainActor extension EditorStore {
  var canEditTransformReference: Bool {
    unavailableToolID == nil && transformDraft != nil && transformDraft?.movingPixels != true && transformDraft?.movingLayers != true
      && !geometryBusy && !aiBusy && !hasToneDraft && historyOperation == nil && selectionTransform?.committing != true
  }
  func setTransformReference(anchor: CanvasAnchor? = nil, point: PathPoint? = nil, visible: Bool? = nil,
    expected: UUID? = nil, gestureID: UUID? = nil) throws {
    guard expected == nil || expected == transformReferenceRevision else { throw CraftError.invalid("The transform workspace changed. Refresh its reference-point state.") }
    guard canEditTransformReference, let original = transformDraft,
      transformReferenceGestureID == nil || transformReferenceGestureID == gestureID else {
      throw CraftError.invalid("Finish the current interaction before changing the transform reference point.")
    }
    guard anchor != nil || point != nil || visible != nil, anchor == nil || point == nil else {
      throw CraftError.invalid("Choose one reference point or preset, with optional visibility.")
    }
    var next = original
    if let anchor { next.referenceAnchor = anchor; next.customReferencePoint = nil }
    if let point { next = try next.settingReferencePoint(point) }
    // A reference-only update never launches another image/contour preparation.
    if contentAwareScaleReadyDraft == original { contentAwareScaleReadyDraft = next }
    transformDraft = next
    if let visible { showTransformReferencePoint = visible }
  }
  func chooseTransformReference(anchor: CanvasAnchor? = nil, visible: Bool? = nil) {
    finishNumericField(); finishLayerName()
    do { try setTransformReference(anchor: anchor, visible: visible) } catch { self.error = error.localizedDescription }
  }
}
struct TransformReferenceOptions: View {
  @Bindable var store: EditorStore
  var body: some View {
    HStack(spacing: 5) {
      Toggle(isOn: Binding(get: { store.showTransformReferencePoint }, set: { store.chooseTransformReference(visible: $0) })) {
        Image(systemName: "scope")
      }.toggleStyle(.button).help("Show Reference Point").accessibilityLabel("Show Reference Point")
      Grid(horizontalSpacing: 2, verticalSpacing: 2) {
        ForEach(0..<3) { row in GridRow { ForEach(0..<3) { column in
          let anchor = CanvasAnchor.allCases[row * 3 + column]
          Button { store.chooseTransformReference(anchor: anchor) } label: {
            Image(systemName: store.transformDraft?.customReferencePoint == nil && store.transformDraft?.referenceAnchor == anchor ? "square.fill" : "square").font(.system(size: 6))
          }.buttonStyle(.plain).accessibilityLabel("Reference point \(anchor.rawValue)")
        } } }
      }.frame(width: 28)
    }.disabled(!store.canEditTransformReference)
  }
}
struct TransformReferenceGesture {
  let id = UUID()
  let original: TransformDraft
  var last: TransformDraft
  let session: UUID
  let owner: UUID
}
extension ToolCursor {
  static func transformReference(available: Bool) -> ToolCursor { available ? .symbol("scope") : .unavailable }
}
extension CraftCanvas {
  func transformReferenceHit(_ point: CGPoint) -> Bool {
    guard store.showTransformReferencePoint, let draft = store.transformDraft,
      !draft.movingLayers, !draft.movingPixels else { return false }
    let pivot = draft.transformReferencePoint, p = viewPoint(.init(x: pivot.x, y: pivot.y))
    return hypot(p.x - point.x, p.y - point.y) <= 7
  }
  func beginTransformReference(_ event: NSEvent) -> Bool {
    guard !spaceHeld, transformReferenceHit(convert(event.locationInWindow, from: nil)) else { return false }
    guard store.canEditTransformReference, let draft = store.transformDraft else { return true }
    let gesture = TransformReferenceGesture(original: draft, last: draft, session: store.sessionGeneration, owner: store.layerPanelGeneration)
    transformReferenceGesture = gesture; store.transformReferenceGestureID = gesture.id
    needsDisplay = true; return true
  }
  func dragTransformReference(_ event: NSEvent) -> Bool {
    guard var gesture = transformReferenceGesture else { return false }
    guard store.layerPanelGeneration == gesture.owner, store.sessionGeneration == gesture.session,
      store.transformDraft == gesture.last, store.transformReferenceGestureID == gesture.id else {
      cancelTransformReference(); return true
    }
    let p = docPoint(event)
    if let point = try? gesture.original.settingReferencePoint(.init(p.x, p.y)) {
      do {
        try store.setTransformReference(point: point.transformReferencePoint, gestureID: gesture.id)
        gesture.last = store.transformDraft!; transformReferenceGesture = gesture
      } catch { cancelTransformReference() }
    }
    needsDisplay = true; return true
  }
  func endTransformReference(_ event: NSEvent) -> Bool {
    guard transformReferenceGesture != nil else { return false }
    _ = dragTransformReference(event)
    if let gesture = transformReferenceGesture, store.transformReferenceGestureID == gesture.id { store.transformReferenceGestureID = nil }
    transformReferenceGesture = nil; needsDisplay = true; return true
  }
  func cancelTransformReference() {
    guard let gesture = transformReferenceGesture else { return }
    if store.layerPanelGeneration == gesture.owner, store.sessionGeneration == gesture.session,
      store.transformDraft == gesture.last, store.transformReferenceGestureID == gesture.id {
      if store.contentAwareScaleReadyDraft == gesture.last { store.contentAwareScaleReadyDraft = gesture.original }
      store.transformDraft = gesture.original
    }
    if store.transformReferenceGestureID == gesture.id { store.transformReferenceGestureID = nil }
    transformReferenceGesture = nil; needsDisplay = true
  }
}
