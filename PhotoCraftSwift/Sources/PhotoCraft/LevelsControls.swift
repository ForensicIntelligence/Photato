import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct LevelsDraft: Identifiable, Sendable {
  let id: UUID
  var levels = LevelsAdjustment()
  var preview = true
}

struct LevelsControls: View {
  @Binding var levels: LevelsAdjustment
  var coalesce: (Bool) -> Void = { _ in }
  var histogram: RGBHistogram?
  var analysisBusy = false
  var analysisError: String?
  @State private var channel = LevelsAdjustment.Channel.rgb
  @State private var importing = false
  @State private var exporting = false
  @State private var presetFile: LevelsPresetFile?
  @State private var loadedPreset: LevelsPresetFile?
  @State private var presetError: String?
  @State private var autoOptions = false
  @State private var shadowClip = 0.1
  @State private var highlightClip = 0.1
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Menu {
          ForEach(BuiltInLevelsPreset.allCases, id: \.self) { preset in
            Button(preset.rawValue) { levels = preset.levels }
          }
          Divider()
          Button("Load Levels Preset…") { importing = true }
          Button("Save Levels Preset…") {
            presetFile = .init(levels: levels, original: loadedPreset?.original)
            exporting = true
          }
        } label: {
          Text(
            "Preset: \(BuiltInLevelsPreset.allCases.first(where: { $0.levels == levels })?.rawValue ?? "Custom")"
          )
        }
        Menu("Auto") {
          ForEach(AutoCorrection.allCases, id: \.self) { kind in
            Button(kind.rawValue) { autoCorrect(kind) }.disabled(histogram?.samples ?? 0 == 0)
          }
          Divider()
          Button("Clipping Options…") { autoOptions = true }
        }.fixedSize()
          .popover(isPresented: $autoOptions) {
            VStack(alignment: .leading, spacing: 12) {
              Text("Automatic Clipping").fontWeight(.semibold)
              TextField(
                "Shadows (%)", value: $shadowClip, format: .number.precision(.fractionLength(2)))
              TextField(
                "Highlights (%)", value: $highlightClip,
                format: .number.precision(.fractionLength(2)))
              Text("0–9.99% at each end; default 0.10%.").font(.caption).foregroundStyle(.secondary)
              Button("Done") { autoOptions = false }
            }.textFieldStyle(.roundedBorder).padding().frame(width: 245)
          }
      }
      Picker("Channel", selection: $channel) {
        ForEach(LevelsAdjustment.Channel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      if let histogram {
        HistogramChart(histogram: histogram, channel: channel).frame(height: 88)
      } else if analysisBusy {
        ProgressView("Calculating histogram…").controlSize(.small).frame(height: 88)
      } else if let analysisError {
        Text(analysisError).font(.caption).foregroundStyle(.secondary)
      }
      Text("Input Levels").fontWeight(.medium)
      HStack {
        control(
          "Black", key: \.inputBlack, range: 0...Double(min(253, levels[channel].inputWhite - 1)))
        gammaControl
        control(
          "White", key: \.inputWhite, range: Double(max(2, levels[channel].inputBlack + 1))...255)
      }
      LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
        .frame(height: 12).accessibilityHidden(true)
      Text("Output Levels").fontWeight(.medium)
      HStack {
        control("Black", key: \.outputBlack, range: 0...255)
        control("White", key: \.outputWhite, range: 0...255)
      }
      Button("Reset") { levels = LevelsAdjustment() }.help("Reset all four channels")
    }.controlSize(.small)
      .fileImporter(isPresented: $importing, allowedContentTypes: [LevelsPresetFile.type]) {
        result in
        do {
          let preset = try LevelsPresetFile.load(result.get())
          loadedPreset = preset
          levels = preset.levels
        } catch { presetError = error.localizedDescription }
      }
      .fileExporter(
        isPresented: $exporting, document: presetFile, contentType: LevelsPresetFile.type,
        defaultFilename: "Levels.alv"
      ) { result in
        if case .failure(let error) = result { presetError = error.localizedDescription }
      }
      .alert(
        "Levels",
        isPresented: Binding(get: { presetError != nil }, set: { if !$0 { presetError = nil } })
      ) {
        Button("OK") { presetError = nil }
      } message: {
        Text(presetError ?? "")
      }
  }
  func autoCorrect(_ kind: AutoCorrection) {
    guard let histogram else { return }
    do {
      var adjusted = try kind.levels(
        from: histogram, shadowClip: shadowClip, highlightClip: highlightClip)
      // Editable controls/ALV use hundredths; pixel Auto Color retains the Rust
      // estimator's full precision through its separate transactional command.
      for channel in LevelsAdjustment.Channel.allCases {
        adjusted[channel].gamma = (adjusted[channel].gamma * 100).rounded() / 100
      }
      levels = adjusted
    } catch { presetError = error.localizedDescription }
  }
  func control(
    _ title: String, key: WritableKeyPath<LevelsChannel, Int>, range: ClosedRange<Double>
  ) -> some View {
    let binding = Binding<Double>(
      get: { Double(levels[channel][keyPath: key]) },
      set: { value in
        guard value.isFinite else { return }
        var record = levels[channel]
        record[keyPath: key] = Int(min(range.upperBound, max(range.lowerBound, value)).rounded())
        levels[channel] = record
      })
    return VStack(spacing: 4) {
      Text(title).foregroundStyle(.secondary)
      TextField(title, value: binding, format: .number.precision(.fractionLength(0)))
        .textFieldStyle(.roundedBorder).monospacedDigit()
      Slider(value: binding, in: range, step: 1, onEditingChanged: coalesce)
        .accessibilityLabel("\(title) level")
    }
  }
  var gammaControl: some View {
    let binding = Binding<Double>(
      get: { Double(levels[channel].gamma) },
      set: { value in
        guard value.isFinite else { return }
        var record = levels[channel]
        record.gamma = Float((min(9.99, max(0.1, value)) * 100).rounded()) / 100
        levels[channel] = record
      })
    return VStack(spacing: 4) {
      Text("Midtones").foregroundStyle(.secondary)
      TextField("Gamma", value: binding, format: .number.precision(.fractionLength(2)))
        .textFieldStyle(.roundedBorder).monospacedDigit()
      Slider(value: binding, in: 0.1...9.99, step: 0.01, onEditingChanged: coalesce)
        .accessibilityLabel("Midtone gamma")
    }
  }
}

struct LevelsSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Levels").font(.title2.bold())
      if let draft = store.levelsDraft {
        LevelsEditor(store: store, layerID: draft.id, pixelLayer: true)
      }
      HStack {
        Toggle(
          "Preview",
          isOn: Binding(
            get: { store.levelsDraft?.preview ?? false },
            set: {
              store.levelsDraft?.preview = $0
              store.render()
            }))
        Spacer()
        Button("Cancel") { store.cancelLevels() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitLevels() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 380)
  }
}

extension EditorStore {
  func autoCorrect(_ kind: AutoCorrection) {
    guard canBeginLevels, let id = activeLayer?.id else { return }
    performGeometry(.autoCorrection(id, kind))
  }
  var canBeginLevels: Bool {
    guard !editingComponent, !geometryBusy, transformDraft == nil, !hasToneDraft, !editingMask,
      let layer = activeLayer, !document.isLocked(layer.id),
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id], case .raster = layer.content
    else { return false }
    return true
  }
  func beginLevels() {
    guard canBeginLevels, let layer = activeLayer else { return }
    levelsDraft = LevelsDraft(id: layer.id)
  }
  func cancelLevels() {
    levelsDraft = nil
    render()
  }
  func commitLevels() {
    guard let draft = levelsDraft else { return }
    levelsDraft = nil
    performGeometry(.applyAdjustment(draft.id, .levels(draft.levels)))
  }
  func addLevelsLayer() { addToneLayer(.levels(.init()), name: "Levels") }
  func addToneLayer(_ adjustment: Adjustment, name: String) {
    guard !geometryBusy, transformDraft == nil, !hasToneDraft else { return }
    do {
      var layer = Layer(name: name, content: .adjustment(adjustment))
      var mask = try Surface(
        width: document.width, height: document.height,
        depth: document.depth, fill: .white)
      if document.selection != nil {
        let doc = document
        mask.mapPixels { x, y, _ in
          let value = doc.selectionCoverage(x: x, y: y)
          return Pixel(value, value, value)
        }
      }
      layer.mask = mask
      perform(.addLayer(layer))
      propertiesTab = .properties
    } catch { self.error = error.localizedDescription }
  }
  func setLevels(_ id: UUID, _ levels: LevelsAdjustment) {
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .adjustment(.levels) = layer.content
    else { return }
    perform(.replaceContent(id, .adjustment(.levels(levels))))
  }
}
