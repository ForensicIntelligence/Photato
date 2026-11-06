import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct PatternFillDraft {
  var layer: Layer
  var pattern: RasterPattern
  var fill: PatternFill
  var creating: Bool
  var preview = true
  var command: Command {
    if creating {
      var layer = layer
      layer.content = .patternFill(fill)
      return .addPatternFill(layer, pattern, true)
    }
    return .setPatternFill(layer.id, fill, pattern)
  }
}

extension EditorStore {
  private var patternFillReady: Bool {
    !editingComponent && !geometryBusy && !hasToneDraft && transformDraft == nil && !patterns.busy
  }
  var canBeginPatternFill: Bool {
    guard patternFillReady, patterns.selected != nil else { return false }
    let parent = activeLayer.flatMap { $0.isGroup ? $0.id : $0.parentID }
    return parent.map { !document.isLocked($0) } ?? true
  }
  func canEditPatternFill(_ id: UUID) -> Bool {
    guard patternFillReady, !document.isLocked(id),
      let layer = document.layers.first(where: { $0.id == id }),
      case .patternFill(let fill) = layer.content
    else { return false }
    return document.pattern(fill.patternID) != nil
  }
  func beginPatternFill(editing id: UUID? = nil) {
    guard patternFillReady else { return }
    if let id {
      guard canEditPatternFill(id), let layer = document.layers.first(where: { $0.id == id }),
        case .patternFill(var fill) = layer.content, let pattern = document.pattern(fill.patternID)
      else { return }
      if let placement = try? fill.flattenedPlacement() {
        fill.placement = placement
        fill.geometry = nil
      }
      patternFillDraft = .init(layer: layer, pattern: pattern, fill: fill, creating: false)
    } else {
      guard canBeginPatternFill else { return }
      guard let pattern = patterns.selected else {
        error = "Define or import a pattern first."
        return
      }
      let fill = PatternFill(patternID: pattern.id)
      let layer = Layer(name: "Pattern Fill", content: .patternFill(fill))
      patternFillDraft = .init(layer: layer, pattern: pattern, fill: fill, creating: true)
    }
    status = "Pattern Fill · Drag in the image to position · Return to apply · Esc to cancel"
    render()
  }
  func cancelPatternFill() {
    patternFillDraft = nil
    status = "Pattern Fill cancelled"
    render()
  }
  func commitPatternFill() {
    guard let draft = patternFillDraft else { return }
    patternFillDraft = nil
    performGeometry(draft.command) { [weak self] in self?.propertiesTab = .properties }
  }
  func choosePattern(_ pattern: RasterPattern, preservingLibrarySelection: Bool = false) {
    if !preservingLibrarySelection { patterns.selectedID = pattern.id }
    if patternFillDraft != nil {
      patternFillDraft?.pattern = pattern
      patternFillDraft?.fill.patternID = pattern.id
      render()
    } else if let layer = activeLayer, case .patternFill(var fill) = layer.content {
      fill.patternID = pattern.id
      perform(.setPatternFill(layer.id, fill, pattern))
    } else {
      bucketUsesPattern = true
    }
  }
  func dragPatternFill(from initial: PatternFill, x: Double, y: Double) {
    guard initial.linked, x.isFinite, y.isFinite else { return }
    do {
      var fill = initial
      try fill.transform(by: .translation(x, y))
      if let normalized = try? fill.flattenedPlacement() {
        fill.placement = normalized
        fill.geometry = nil
      }
      try fill.validate()
      patternFillDraft?.fill = fill
      render()
    } catch { self.error = error.localizedDescription }
  }
  func snapPatternFill() {
    guard var draft = patternFillDraft else { return }
    draft.fill.placement.phaseX = 0
    draft.fill.placement.phaseY = 0
    draft.fill.geometry?.tx = 0
    draft.fill.geometry?.ty = 0
    patternFillDraft = draft
    render()
  }
}

struct PatternFillEditor: View {
  @Bindable var store: EditorStore
  private func value(_ key: WritableKeyPath<PatternPlacement, Float>) -> Binding<Double> {
    Binding(
      get: { Double(store.patternFillDraft?.fill.placement[keyPath: key] ?? 0) },
      set: {
        guard $0.isFinite else { return }
        store.patternFillDraft?.fill.placement[keyPath: key] = Float($0)
        store.render()
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("Pattern Fill").font(.headline)
      if let draft = store.patternFillDraft {
        HStack {
          PatternSwatch(pattern: draft.pattern).frame(width: 48, height: 48)
          Menu {
            let candidates = (store.document.patterns ?? []) + store.patterns.items
            ForEach(Array(candidates.enumerated()), id: \.offset) { _, pattern in
              Button(pattern.displayName) { store.choosePattern(pattern) }
            }
          } label: {
            Text(draft.pattern.displayName).lineLimit(2)
          }
        }
        HStack {
          Text("Angle").frame(width: 42, alignment: .leading)
          Slider(value: value(\.angle), in: -180...180)
          TextField("Angle", value: value(\.angle), format: .number).frame(width: 54)
          Text("°")
        }
        HStack {
          Text("Scale").frame(width: 42, alignment: .leading)
          Slider(value: value(\.scale), in: 1...1000)
          TextField("Scale", value: value(\.scale), format: .number).frame(width: 54)
          Text("%")
        }
        Toggle(
          "Link with Layer",
          isOn: Binding(
            get: { draft.fill.linked },
            set: {
              store.patternFillDraft?.fill.linked = $0
              store.render()
            }))
        HStack {
          Text("X")
          TextField("X offset", value: value(\.phaseX), format: .number)
          Text("Y")
          TextField("Y offset", value: value(\.phaseY), format: .number)
          Text("px")
        }
        Button("Snap to Origin") { store.snapPatternFill() }
        Text(
          draft.fill.linked
            ? "Drag in the image to reposition the pattern."
            : "Enable Link with Layer to reposition by dragging."
        )
        .font(.caption).foregroundStyle(.secondary)
        Divider()
        HStack {
          Toggle(
            "Preview",
            isOn: Binding(
              get: { draft.preview },
              set: {
                store.patternFillDraft?.preview = $0
                store.render()
              }))
          Spacer()
          Button("Cancel") { store.cancelPatternFill() }.keyboardShortcut(.cancelAction)
          Button("OK") { store.commitPatternFill() }.keyboardShortcut(.defaultAction)
            .disabled((try? draft.fill.validate()) == nil)
        }
      }
    }.textFieldStyle(.roundedBorder).padding(16).frame(width: 342)
      .background(StudioTheme.chrome, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.line))
      .shadow(radius: 12)
  }
}
