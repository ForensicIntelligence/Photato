import PhotoCraftCore
import SwiftUI

struct TonalStepsDraft: Identifiable, Sendable {
  let id: UUID
  var adjustment: TonalStepsAdjustment
  var preview = true
}

struct TonalStepsControls: View {
  @Binding var adjustment: TonalStepsAdjustment
  var histogram: RGBHistogram?
  var analysisBusy = false
  var analysisError: String?
  var coalesce: (Bool) -> Void = { _ in }
  var value: Binding<Double> {
    Binding(
      get: { Double(adjustment.level) },
      set: { value in
        guard value.isFinite else { return }
        adjustment.level = Int(
          min(255, max(Double(adjustment.kind.range.lowerBound), value)).rounded())
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(adjustment.kind == .threshold ? "Threshold Level" : "Levels")
        Spacer()
        TextField("Level", value: value, format: .number.precision(.fractionLength(0)))
          .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 64)
          .accessibilityLabel("\(adjustment.kind.rawValue) level")
      }
      if adjustment.kind == .threshold {
        if let histogram { HistogramChart(histogram: histogram, channel: .rgb).frame(height: 88) }
        if analysisBusy { ProgressView("Analyzing tones…").controlSize(.small) }
        if let analysisError { Text(analysisError).font(.caption).foregroundStyle(.secondary) }
      }
      Slider(
        value: value, in: Double(adjustment.kind.range.lowerBound)...255, step: 1,
        onEditingChanged: coalesce
      )
      .accessibilityLabel("\(adjustment.kind.rawValue) level")
      LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
        .frame(height: 9).accessibilityHidden(true)
      HStack {
        Text("\(adjustment.kind.range.lowerBound)").foregroundStyle(.secondary)
        Spacer()
        Button("Reset") { adjustment.level = adjustment.kind.defaultLevel }
          .disabled(adjustment.level == adjustment.kind.defaultLevel)
        Spacer()
        Text("255").foregroundStyle(.secondary)
      }
    }
  }
}

struct TonalStepsEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  @State private var analysis = LevelsAnalysis()
  var adjustment: TonalStepsAdjustment {
    if pixelLayer, let value = store.tonalStepsDraft?.adjustment { return value }
    if case .adjustment(.tonalSteps(let value)) = store.document.layers.first(where: {
      $0.id == layerID
    })?.content {
      return value
    }
    return .init(kind: .threshold)
  }
  var request: LevelsAnalysisRequest {
    .init(document: store.document, layerID: layerID, pixelLayer: pixelLayer, luminance: true)
  }
  var body: some View {
    TonalStepsControls(
      adjustment: Binding(
        get: { adjustment },
        set: { value in
          if pixelLayer {
            store.tonalStepsDraft?.adjustment = value
            store.render()
          } else {
            store.setTonalSteps(layerID, value)
          }
        }), histogram: analysis.histogram, analysisBusy: analysis.busy,
      analysisError: analysis.error, coalesce: { if !pixelLayer { store.coalesce($0) } }
    )
    .task(id: request) { if adjustment.kind == .threshold { analysis.update(request) } }
    .onDisappear { analysis.cancel() }
  }
}

struct TonalStepsSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let draft = store.tonalStepsDraft {
        Text(draft.adjustment.kind.rawValue).font(.title2.bold())
        TonalStepsEditor(store: store, layerID: draft.id, pixelLayer: true)
      }
      Divider()
      HStack {
        Toggle(
          "Preview",
          isOn: Binding(
            get: { store.tonalStepsDraft?.preview ?? false },
            set: {
              store.tonalStepsDraft?.preview = $0
              store.render()
            }))
        Spacer()
        Button("Cancel") { store.cancelTonalSteps() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitTonalSteps() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 380)
  }
}

extension EditorStore {
  func beginTonalSteps(_ kind: TonalStepsAdjustment.Kind) {
    guard canBeginLevels, let layer = activeLayer else { return }
    tonalStepsDraft = .init(id: layer.id, adjustment: .init(kind: kind))
  }
  func cancelTonalSteps() {
    tonalStepsDraft = nil
    render()
  }
  func commitTonalSteps() {
    guard let draft = tonalStepsDraft else { return }
    tonalStepsDraft = nil
    performGeometry(.applyAdjustment(draft.id, .tonalSteps(draft.adjustment)))
  }
  func addTonalStepsLayer(_ kind: TonalStepsAdjustment.Kind) {
    addToneLayer(.tonalSteps(.init(kind: kind)), name: kind.rawValue)
  }
  func setTonalSteps(_ id: UUID, _ settings: TonalStepsAdjustment) {
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .adjustment(.tonalSteps(let current)) = layer.content, current.kind == settings.kind
    else { return }
    perform(.replaceContent(id, .adjustment(.tonalSteps(settings))))
  }
}
