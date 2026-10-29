import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension EditorStore {
  func colorRegionClick(at point: PathPoint, modifiers: NSEvent.ModifierFlags = []) {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil,
      let layer = activeLayer, point.x >= 0, point.y >= 0,
      point.x < Double(document.width), point.y < Double(document.height)
    else { return }
    let isWand = tool == .magicWand
    guard isWand || tool == .paintBucket else { return }
    guard !smartFilterMaskEditing else { error = "Use Brush or Fill to edit the Smart Filter mask."; return }
    if !isWand && modifiers.contains(.option) {
      if let surface { brush.color = surface.pixel(x: Int(floor(point.x)), y: Int(floor(point.y))) }
      return
    }
    let mask = editingMask
    if !isWand && (editingMask ? document.isLocked(layer.id) : document.isImageLocked(layer.id)) {
      error = "Unlock this layer and its parent groups before editing it."
      return
    }
    let wand = wandOptions
    let bucket = bucketOptions
    let color = brush.color
    let pattern = !isWand && bucketUsesPattern ? patterns.selected : nil
    if !isWand && bucketUsesPattern && (pattern == nil || patterns.busy) {
      error =
        patterns.busy ? "Wait for patterns to finish loading." : "Choose or define a pattern first."
      return
    }
    let placement = bucketPatternPlacement
    let mode = selectionMode(modifiers: modifiers)
    let all = !mask && (isWand ? wandSampleAllLayers : bucket.sampleAllLayers)
    let id = layer.id
    performGeometry(label: isWand ? "Magic Wand" : "Paint Bucket") { document in
      let sample = try Renderer.cloneSample(
        in: document, layerID: id,
        sampling: all ? .all : .current, mask: mask)
      if isWand { return .magicWand(sample, point, wand, mode, mask) }
      return .paintBucket(
        id,
        BucketFill(
          source: sample, seed: point, color: color,
          options: bucket, mask: mask, pattern: pattern, placement: placement))
    }
  }
}

extension WorkspaceView {
  @ViewBuilder var colorRegionOptions: some View {
    if store.tool == .magicWand {
      Picker("Selection mode", selection: $store.selectionMode) {
        ForEach(SelectionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.labelsHidden().frame(width: 100).controlSize(.small)
      labeledValue("Sample Size:", value: "Point Sample", width: 90)
        .help("Point sampling is available. Averaged sampling is not available yet.")
      matchOptions($store.wandOptions)
      Toggle("Sample All Layers", isOn: $store.wandSampleAllLayers).disabled(store.editingMask)
      Button("Select and Mask…") { store.beginSelectMask() }.disabled(!store.canBeginSelectMask).controlSize(.small)
    } else {
      Picker("Fill", selection: $store.bucketUsesPattern) {
        Text("Foreground").tag(false)
        Text("Pattern").tag(true)
      }.frame(width: 140).controlSize(.small)
      if store.bucketUsesPattern { bucketPatternPicker }
      Picker("Mode", selection: $store.bucketOptions.mode) {
        ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.frame(width: 150).controlSize(.small)
      percentField("Opacity:", value: $store.bucketOptions.opacity)
      matchOptions($store.bucketOptions.match)
      Toggle("All Layers", isOn: $store.bucketOptions.sampleAllLayers).disabled(store.editingMask)
      Text("⌥ Sample color").foregroundStyle(.secondary)
    }
  }
  @ViewBuilder func matchOptions(_ options: Binding<ColorMatchOptions>) -> some View {
    HStack(spacing: 4) {
      Text("Tolerance:")
      TextField("Tolerance", value: options.tolerance, format: .number)
        .frame(width: 38).textFieldStyle(.roundedBorder)
        .help("Color tolerance, 0–255")
    }
    Toggle("Anti-alias", isOn: options.antiAlias)
    Toggle("Contiguous", isOn: options.contiguous)
  }
}
