import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct CurvesDraft: Identifiable, Sendable {
  let id: UUID
  var curves = CurvesAdjustment()
  var preview = true
}

struct CurvesControls: View {
  @Binding var curves: CurvesAdjustment
  var coalesce: (Bool) -> Void = { _ in }
  var histogram: RGBHistogram?
  var analysisBusy = false
  var analysisError: String?
  @State private var channel = CurvesAdjustment.Channel.rgb
  @State private var selected = 0
  @State private var importing = false
  @State private var exporting = false
  @State private var presetFile: CurvesPresetFile?
  @State private var loadedPreset: CurvesPresetFile?
  @State private var presetError: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Menu {
        ForEach(BuiltInCurvesPreset.allCases, id: \.self) { preset in
          Button(preset.rawValue) {
            curves = preset.curves
            selected = 0
          }
        }
        Divider()
        Button("Load Curves Preset…") { importing = true }
        Button("Save Curves Preset…") {
          presetFile = .init(curves: curves, original: loadedPreset?.original)
          exporting = true
        }
      } label: {
        Text(
          "Preset: \(BuiltInCurvesPreset.allCases.first(where: { $0.curves == curves })?.rawValue ?? "Custom")"
        )
      }
      Picker("Channel", selection: $channel) {
        ForEach(CurvesAdjustment.Channel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.onChange(of: channel) { _, _ in selected = 0 }
      CurvesGraph(
        curve: $curves[channel], selected: $selected, channel: channel,
        histogram: histogram, coalesce: coalesce
      )
      .aspectRatio(1, contentMode: .fit)
      LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
        .frame(height: 10).accessibilityHidden(true)
      if analysisBusy { ProgressView("Calculating histogram…").controlSize(.small) }
      if let analysisError { Text(analysisError).font(.caption).foregroundStyle(.secondary) }
      HStack {
        coordinate("Input", key: \.input)
        coordinate("Output", key: \.output)
      }
      HStack {
        Picker("Point", selection: $selected) {
          ForEach(curves[channel].points.indices, id: \.self) { i in
            Text("\(i + 1)").tag(i)
          }
        }.frame(maxWidth: 100)
        Button("Delete Point") {
          curves[channel].remove(selected)
          normalizeSelection()
        }
        .disabled(curves[channel].points.count <= 2)
        Spacer(minLength: 0)
      }
      HStack {
        Button("Reset Channel") {
          curves[channel] = .init()
          selected = 0
        }
        Button("Reset All") {
          curves = .init()
          selected = 0
        }
      }
    }.controlSize(.small)
      .onChange(of: curves) { _, _ in normalizeSelection() }
      .fileImporter(isPresented: $importing, allowedContentTypes: [CurvesPresetFile.type]) {
        result in
        do {
          let preset = try CurvesPresetFile.load(result.get())
          loadedPreset = preset
          curves = preset.curves
          selected = 0
        } catch { presetError = error.localizedDescription }
      }
      .fileExporter(
        isPresented: $exporting, document: presetFile,
        contentType: CurvesPresetFile.type, defaultFilename: "Curves.acv"
      ) { result in
        if case .failure(let error) = result { presetError = error.localizedDescription }
      }
      .alert(
        "Curves",
        isPresented: Binding(get: { presetError != nil }, set: { if !$0 { presetError = nil } })
      ) {
        Button("OK") { presetError = nil }
      } message: {
        Text(presetError ?? "")
      }
  }
  func normalizeSelection() { selected = min(max(0, selected), curves[channel].points.count - 1) }
  func coordinate(_ title: String, key: WritableKeyPath<CurvePoint, Int>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).foregroundStyle(.secondary)
      TextField(
        title,
        value: Binding<Double>(
          get: {
            let points = curves[channel].points
            return Double(points[min(selected, points.count - 1)][keyPath: key])
          },
          set: { value in
            guard value.isFinite, curves[channel].points.indices.contains(selected) else { return }
            var point = curves[channel].points[selected]
            point[keyPath: key] = Int(min(255, max(0, value)).rounded())
            curves[channel].move(selected, to: point)
          }), format: .number.precision(.fractionLength(0))
      )
      .textFieldStyle(.roundedBorder).monospacedDigit()
      .accessibilityLabel("Curve \(title.lowercased())")
    }
  }
}

struct CurvesGraph: View {
  @Binding var curve: CurveChannel
  @Binding var selected: Int
  let channel: CurvesAdjustment.Channel
  var histogram: RGBHistogram?
  var coalesce: (Bool) -> Void
  @State private var dragging = false
  @FocusState private var focused: Bool
  var color: Color {
    switch channel {
    case .rgb: .white
    case .red: .red
    case .green: .green
    case .blue: .cyan
    }
  }
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let histogram { HistogramChart(histogram: histogram, channel: channel).opacity(0.3) }
        Canvas { context, size in
          var grid = Path()
          for i in 0...4 {
            let t = CGFloat(i) / 4
            grid.move(to: CGPoint(x: size.width * t, y: 0))
            grid.addLine(to: CGPoint(x: size.width * t, y: size.height))
            grid.move(to: CGPoint(x: 0, y: size.height * t))
            grid.addLine(to: CGPoint(x: size.width, y: size.height * t))
          }
          context.stroke(grid, with: .color(.white.opacity(0.18)), lineWidth: 1)
          var diagonal = Path()
          diagonal.move(to: CGPoint(x: 0, y: size.height))
          diagonal.addLine(to: CGPoint(x: size.width, y: 0))
          context.stroke(
            diagonal, with: .color(.white.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
          let table = curve.table()
          var line = Path()
          for i in 0...255 {
            let value = table[Int((Double(i) * 4095 / 255).rounded())]
            let point = CGPoint(
              x: CGFloat(i) / 255 * size.width, y: (1 - CGFloat(value)) * size.height)
            if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
          }
          context.stroke(line, with: .color(color), lineWidth: 1.5)
          for (i, point) in curve.points.enumerated() {
            let center = location(point, size: size)
            let shape = Path(
              ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
            context.fill(shape, with: .color(i == selected ? color : .black))
            context.stroke(shape, with: .color(color), lineWidth: 1)
          }
        }.allowsHitTesting(false)
      }
      .background(.black.opacity(0.25)).contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { value in
          focused = true
          if !dragging {
            let start = value.startLocation
            let near = curve.points.indices.min {
              distance(location(curve.points[$0], size: geometry.size), start)
                < distance(location(curve.points[$1], size: geometry.size), start)
            }
            if let near, distance(location(curve.points[near], size: geometry.size), start) < 10 {
              selected = near
            } else {
              var edited = curve
              guard let index = try? edited.insert(coordinates(start, size: geometry.size)) else {
                return
              }
              coalesce(true)
              dragging = true
              curve = edited
              selected = index
            }
            if !dragging {
              coalesce(true)
              dragging = true
            }
          }
          // A click selects without moving an existing point to the cursor's edge.
          if value.translation != .zero {
            curve.move(selected, to: coordinates(value.location, size: geometry.size))
          }
        }.onEnded { _ in endDrag() }
      )
      .focusable().focused($focused)
      .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .delete]) { press in
        guard curve.points.indices.contains(selected) else { return .ignored }
        if press.key == .delete {
          curve.remove(selected)
          selected = min(selected, curve.points.count - 1)
        } else {
          var point = curve.points[selected]
          let step = press.modifiers.contains(.shift) ? 10 : 1
          if press.key == .upArrow { point.output += step }
          if press.key == .downArrow { point.output -= step }
          if press.key == .leftArrow { point.input -= step }
          if press.key == .rightArrow { point.input += step }
          curve.move(selected, to: point)
        }
        return .handled
      }
      .accessibilityLabel("\(channel.rawValue) curve")
      .accessibilityValue("\(curve.points.count) points; point \(selected + 1) selected")
      .accessibilityHint(
        "Click to add a point; drag or use arrow keys to move it. Input and output fields provide numeric editing."
      )
      .onDisappear { endDrag() }
    }
  }
  func endDrag() {
    if dragging {
      coalesce(false)
      dragging = false
    }
  }
  func location(_ point: CurvePoint, size: CGSize) -> CGPoint {
    CGPoint(
      x: CGFloat(point.input) / 255 * size.width, y: (1 - CGFloat(point.output) / 255) * size.height
    )
  }
  func coordinates(_ point: CGPoint, size: CGSize) -> CurvePoint {
    .init(
      Int((min(1, max(0, point.x / max(1, size.width))) * 255).rounded()),
      Int((min(1, max(0, 1 - point.y / max(1, size.height))) * 255).rounded()))
  }
  func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

struct CurvesEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  @State private var analysis = LevelsAnalysis()
  var request: LevelsAnalysisRequest {
    .init(document: store.document, layerID: layerID, pixelLayer: pixelLayer)
  }
  var body: some View {
    CurvesControls(
      curves: Binding(
        get: {
          if pixelLayer { return store.curvesDraft?.curves ?? .init() }
          if case .adjustment(.curves(let value)) = store.document.layers.first(where: {
            $0.id == layerID
          })?.content {
            return value
          }
          return .init()
        },
        set: { value in
          if pixelLayer {
            store.curvesDraft?.curves = value
            store.render()
          } else {
            store.setCurves(layerID, value)
          }
        }), coalesce: { if !pixelLayer { store.coalesce($0) } }, histogram: analysis.histogram,
      analysisBusy: analysis.busy, analysisError: analysis.error
    )
    .onChange(of: request, initial: true) { _, value in analysis.update(value) }
    .onDisappear { analysis.cancel() }
  }
}

struct CurvesSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Curves").font(.title2.bold())
      if let draft = store.curvesDraft {
        CurvesEditor(store: store, layerID: draft.id, pixelLayer: true)
      }
      HStack {
        Toggle(
          "Preview",
          isOn: Binding(
            get: { store.curvesDraft?.preview ?? false },
            set: {
              store.curvesDraft?.preview = $0
              store.render()
            }))
        Spacer()
        Button("Cancel") { store.cancelCurves() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitCurves() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 380)
  }
}

extension EditorStore {
  var hasToneDraft: Bool {
    layerPanelOptionsDraft != nil || channelPanelOptionsDraft != nil
      || layerVisibilityDraft != nil || confirmingLayerDeletion
      || newLayerDraft != nil
      || newGroupDraft != nil
      || duplicateLayerDraft != nil || levelsDraft != nil
      || curvesDraft != nil
      || hueSaturationDraft != nil
      || colorBalanceDraft != nil || gradientMapDraft != nil || tonalStepsDraft != nil
      || cloneDraft != nil
      || patternFillDraft != nil || gradientFillDraft != nil
      || gradientGesture != nil || gradientStopColorDraft != nil
  }
  var canBeginCurves: Bool { canBeginLevels }
  func beginCurves() {
    guard canBeginCurves, let layer = activeLayer else { return }
    curvesDraft = .init(id: layer.id)
  }
  func cancelCurves() {
    curvesDraft = nil
    render()
  }
  func commitCurves() {
    guard let draft = curvesDraft else { return }
    curvesDraft = nil
    performGeometry(.applyAdjustment(draft.id, .curves(draft.curves)))
  }
  func addCurvesLayer() { addToneLayer(.curves(.init()), name: "Curves") }
  func setCurves(_ id: UUID, _ curves: CurvesAdjustment) {
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .adjustment(.curves) = layer.content
    else { return }
    perform(.replaceContent(id, .adjustment(.curves(curves))))
  }
}

struct CurvesPresetFile: FileDocument {
  static let type = UTType(filenameExtension: "acv") ?? .data
  static var readableContentTypes: [UTType] { [type] }
  var curves: CurvesAdjustment
  var original: Data?
  init(curves: CurvesAdjustment, original: Data? = nil) {
    self.curves = curves
    self.original = original
  }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CraftError.invalid("Invalid Curves preset file.")
    }
    curves = try CurvesPresetCodec.read(data)
    original = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: try CurvesPresetCodec.write(curves, original: original))
  }
  static func load(_ url: URL) throws -> Self {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 32769) ?? Data()
    return .init(curves: try CurvesPresetCodec.read(data), original: data)
  }
}
