import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension EditorStore {
  var canUseMagicWand: Bool {
    document.colorMode == .rgb && isCompositeColorTarget && editingChannel == nil
      && !smartFilterMaskEditing && pathTarget == nil && activeLayer != nil
      && canSelectComponentTarget && brushGesture == nil
  }
  func colorRegionClick(at point: PathPoint, modifiers: NSEvent.ModifierFlags = []) {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil,
      let layer = activeLayer, point.x >= 0, point.y >= 0,
      point.x < Double(document.width), point.y < Double(document.height)
    else { return }
    let isWand = tool == .magicWand
    guard isWand || tool == .paintBucket else { return }
    guard !smartFilterMaskEditing else { error = "Use Brush or Fill to edit the Smart Filter mask."; return }
    if isWand {
      guard canUseMagicWand else { return }
      let request = MagicWandRequest(layerID: layer.id, point: point, options: wandOptions,
        mode: selectionMode(modifiers: modifiers), sampleAllLayers: wandSampleAllLayers, mask: editingMask)
      performGeometry(label: "Magic Wand", allowAuxiliary: true) { try request.command(in: $0) }
      return
    }
    if !isWand && modifiers.contains(.option) {
      if let surface { brush.color = surface.pixel(x: Int(floor(point.x)), y: Int(floor(point.y))) }
      return
    }
    let mask = editingMask
    if !isWand && (editingMask ? document.isLocked(layer.id) : document.isImageLocked(layer.id)) {
      error = "Unlock this layer and its parent groups before editing it."
      return
    }
    let bucket = bucketOptions
    let color = brush.color
    let pattern = !isWand && bucketUsesPattern ? patterns.selected : nil
    if !isWand && bucketUsesPattern && (pattern == nil || patterns.busy) {
      error =
        patterns.busy ? "Wait for patterns to finish loading." : "Choose or define a pattern first."
      return
    }
    let placement = bucketPatternPlacement
    let all = !mask && (isWand ? wandSampleAllLayers : bucket.sampleAllLayers)
    let id = layer.id
    performGeometry(label: isWand ? "Magic Wand" : "Paint Bucket") { document in
      let sample = try Renderer.cloneSample(
        in: document, layerID: id,
        sampling: all ? .all : .current, mask: mask)
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
      Picker("Sample Size:", selection: $store.wandOptions.sampleSize) {
        ForEach(ColorSampleSettings.sizes, id: \.self) { size in
          Text(size == 1 ? "Point Sample" : "\(size) by \(size) Average").tag(size)
        }
      }.frame(width: 245).controlSize(.small).accessibilityLabel("Sample Size")
        .help("Average the sampled area around the click, clipped to the image bounds.")
      matchOptions($store.wandOptions)
      Toggle("Sample All Layers", isOn: $store.wandSampleAllLayers).disabled(store.editingMask)
      Button("Select Subject") { store.selectSubjectFromToolOptions() }
        .disabled(!store.canSelectSubjectFromToolOptions)
        .accessibilityIdentifier("selection.options.subject")
        .help("Select the main subjects using on-device processing.")
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
