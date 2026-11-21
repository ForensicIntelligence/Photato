import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension BucketOptions {
  static var modeNames: [String] {
    BlendMode.allCases.flatMap { mode in
      mode == .dissolve ? [mode.rawValue, BrushPaintMode.clear.title] : [mode.rawValue]
    }
  }

  var modeName: String { clearsAlpha ? BrushPaintMode.clear.title : mode.rawValue }

  @discardableResult mutating func chooseMode(_ name: String) -> Bool {
    if name == BrushPaintMode.clear.title {
      clearsAlpha = true
    } else {
      guard let next = BlendMode(rawValue: name) else { return false }
      mode = next
      clearsAlpha = false
    }
    return true
  }
}

extension EditorStore {
  var canUseMagicWand: Bool {
    document.colorMode == .rgb && isCompositeColorTarget && editingChannel == nil
      && !smartFilterMaskEditing && pathTarget == nil && activeLayer != nil
      && canSelectComponentTarget && brushGesture == nil
  }
  var canUseBucketContext: Bool {
    !geometryBusy && !hasToneDraft && transformDraft == nil && historyOperation == nil
      && !smartFilterMaskEditing && !editingComponent && editingChannel == nil && pathTarget == nil
  }

  func canUseBucket(clearsAlpha: Bool) -> Bool {
    guard canUseBucketContext, let layer = activeLayer else { return false }
    return (try? document.validateBucketTarget(layerID: layer.id, mask: editingMask,
      clearsAlpha: clearsAlpha)) != nil
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
    guard canUseBucketContext else { return }
    if modifiers.contains(.option) {
      let x = Int(floor(point.x)), y = Int(floor(point.y))
      do {
        if let pixel = try patternCanvasPreview?.pixel(x: x, y: y) ?? surface?.pixel(x: x, y: y) {
          brush.color = pixel
        }
      } catch { self.error = error.localizedDescription }
      return
    }
    let options = bucketOptions, mask = editingMask
    do {
      try document.validateBucketTarget(layerID: layer.id, mask: mask, clearsAlpha: options.clearsAlpha)
    } catch {
      self.error = error.localizedDescription
      return
    }
    let pattern = bucketUsesPattern ? patterns.selected : nil
    if bucketUsesPattern && (pattern == nil || patterns.busy) {
      error = patterns.busy ? "Wait for patterns to finish loading." : "Choose or define a pattern first."
      return
    }
    let request = PaintBucketRequest(layerID: layer.id, point: point, color: brush.color, options: options,
      mask: mask, pattern: pattern, placement: bucketPatternPlacement)
    performGeometry(label: "Paint Bucket") { try request.command(in: $0) }
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
      Picker("Mode", selection: Binding(get: { store.bucketOptions.modeName }, set: { name in
        var options = store.bucketOptions
        if options.chooseMode(name) { store.bucketOptions = options }
      })) {
        ForEach(BucketOptions.modeNames, id: \.self) { name in
          Text(name).tag(name).disabled(name == BrushPaintMode.clear.title && !store.canUseBucket(clearsAlpha: true))
        }
      }.frame(width: 150).controlSize(.small)
        .accessibilityIdentifier("paintBucket.mode")
        .help("Clear removes alpha from pixels on an unlocked pixel layer.")
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
