import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

struct InkModeSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: InkModeWorkspace
  @State private var selectedInk = 0
  @State private var selectedPoint = 0
  private var index: Int { min(selectedInk, model.request.settings.inks.count - 1) }
  private var ink: DuotoneInk { model.request.settings.inks[index] }
  private var point: Int { min(selectedPoint, ink.curve.count - 1) }
  var body: some View {
    VStack(spacing: 12) {
      HStack { Text(model.request.title).font(.headline); Spacer(); if model.rendering || model.committing { ProgressView().controlSize(.small) } }
      HStack(alignment: .top, spacing: 16) {
        GeometryReader { area in
          ZStack {
            Color(white: 0.12)
            if let image = model.preview ? model.image : model.originalImage {
              Image(decorative: image, scale: 1).resizable().scaledToFit().padding(12)
                .frame(width: area.size.width, height: area.size.height)
            }
          }.clipped().accessibilityLabel("Ink conversion preview")
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if model.request.kind == .duotone { duotoneControls }
            else {
              Text("Convert to Multichannel").font(.headline)
              Text("The image becomes independent ink channels. Layers are flattened, and saved alpha channels are retained.")
              Text(model.source.colorMode == .duotone ? "Each ink uses its density curve to create a separate channel." : "RGB becomes Cyan, Magenta and Yellow. CMYK retains all four plates, including Black.")
                .font(.caption).foregroundStyle(.secondary)
            }
            if InkModeInput.needsMerge(model.source) {
              Divider()
              Toggle("Merge visible layers", isOn: Binding(get: { model.request.mergeVisible }, set: { v in model.update { $0.mergeVisible = v } }))
              Text("This replaces the layer stack with the visible image and discards hidden layers. Cancel preserves the original document.")
                .font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.trailing, 8)
        }.frame(width: 350).disabled(model.committing)
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Toggle("Preview", isOn: $model.preview)
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: .command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: [.command, .shift])
        Spacer()
        Button("Cancel") { store.cancelInkMode() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitInkMode() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(16).frame(width: 900, height: 640)
      .onDisappear { model.close(); if store.inkModeWorkspace === model { store.inkModeWorkspace = nil } }
  }
  private var duotoneControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Type", selection: Binding(get: { model.request.settings.inks.count }, set: { model.setInkCount($0) })) {
        Text("Monotone").tag(1); Text("Duotone").tag(2); Text("Tritone").tag(3); Text("Quadtone").tag(4)
      }
      Picker("Ink", selection: Binding(get: { index }, set: { selectedInk = $0; selectedPoint = 0 })) {
        ForEach(model.request.settings.inks.indices, id: \.self) { i in Text("\(i + 1): \(model.request.settings.inks[i].name)").tag(i) }
      }
      TextField("Ink name", text: Binding(get: { ink.name }, set: { value in editInk { $0.name = value } }))
        .textFieldStyle(.roundedBorder)
      ColorPicker("Ink color", selection: Binding(get: { color(ink.color) }, set: { value in editInk { $0.color = pixel(value) } }), supportsOpacity: false)
      Text("Duotone Curve").font(.headline)
      InkCurveGraph(points: ink.curve, selected: point) { input, output in movePoint(input, output) }
        .frame(height: 155).accessibilityLabel("Ink density curve; use the point fields for precise values")
      Picker("Point", selection: Binding(get: { point }, set: { selectedPoint = $0 })) {
        ForEach(ink.curve.indices, id: \.self) { i in Text("\(Int((ink.curve[i].input * 100).rounded()))% → \(Int((ink.curve[i].output * 100).rounded()))%").tag(i) }
      }
      HStack {
        Text("Input %")
        TextField("Input percent", value: Binding(get: { Double(ink.curve[point].input * 100) }, set: { movePoint(Float($0 / 100), ink.curve[point].output) }), format: .number.precision(.fractionLength(0...2)))
          .disabled(point == 0 || point == ink.curve.count - 1)
        Text("Ink %")
        TextField("Ink percent", value: Binding(get: { Double(ink.curve[point].output * 100) }, set: { movePoint(ink.curve[point].input, Float($0 / 100)) }), format: .number.precision(.fractionLength(0...2)))
      }.textFieldStyle(.roundedBorder)
      HStack {
        Button("Add Point") { addPoint() }.disabled(ink.curve.count >= 256)
        Button("Remove") { let i = point; editInk { $0.curve.remove(at: i) }; selectedPoint = max(0, i - 1) }.disabled(point == 0 || point == ink.curve.count - 1)
        Button("Reset Curve") { editInk { $0.curve = [.init(0, 0), .init(1, 1)] }; selectedPoint = 0 }
      }.controlSize(.small)
      if model.request.settings.inks.count > 1 {
        DisclosureGroup("Overprint Colors") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Preview colors for overlapping inks. Printing plates keep their original densities.").font(.caption).foregroundStyle(.secondary)
            ForEach(overprintMasks, id: \.self) { mask in
              HStack {
                Toggle(overprintName(mask), isOn: Binding(get: { model.request.settings.overprints.contains { $0.mask == mask } }, set: { enabled in
                  model.update { r in r.settings.overprints.removeAll { $0.mask == mask }; if enabled { r.settings.overprints.append(.init(mask: mask, color: defaultOverprint(mask))) } }
                }))
                if let item = model.request.settings.overprints.first(where: { $0.mask == mask }) {
                  ColorPicker("Color", selection: Binding(get: { color(item.color) }, set: { value in
                    model.update { r in if let i = r.settings.overprints.firstIndex(where: { $0.mask == mask }) { r.settings.overprints[i].color = pixel(value) } }
                  }), supportsOpacity: false).labelsHidden().accessibilityLabel("Overprint color \(overprintName(mask))")
                }
              }
            }
          }.padding(.top, 6)
        }
      }
      HStack { Button("Load Settings…") { loadSettings() }; Button("Save Settings…") { saveSettings() } }.controlSize(.small)
    }
  }
  private func editInk(_ change: (inout DuotoneInk) -> Void) { let i = index; model.update { change(&$0.settings.inks[i]) } }
  private func movePoint(_ input: Float, _ output: Float) {
    guard input.isFinite, output.isFinite else { return }
    let i = point, n = ink.curve.count
    editInk { ink in
      let lower: Float = i == 0 ? 0 : ink.curve[i - 1].input.nextUp
      let upper: Float = i == n - 1 ? 1 : ink.curve[i + 1].input.nextDown
      ink.curve[i] = .init(i == 0 ? 0 : i == n - 1 ? 1 : min(upper, max(lower, input)), min(1, max(0, output)))
    }
  }
  private func addPoint() {
    guard let i = (0..<(ink.curve.count - 1)).max(by: { ink.curve[$0 + 1].input - ink.curve[$0].input < ink.curve[$1 + 1].input - ink.curve[$1].input }) else { return }
    editInk { ink in let a = ink.curve[i], b = ink.curve[i + 1]; ink.curve.insert(.init((a.input + b.input) / 2, (a.output + b.output) / 2), at: i + 1) }
    selectedPoint = i + 1
  }
  private var overprintMasks: [Int] { (1..<(1 << model.request.settings.inks.count)).filter { $0.nonzeroBitCount > 1 } }
  private func overprintName(_ mask: Int) -> String { model.request.settings.inks.indices.filter { mask & (1 << $0) != 0 }.map { String($0 + 1) }.joined(separator: " + ") }
  private func defaultOverprint(_ mask: Int) -> Pixel {
    var result = Pixel.white
    for i in model.request.settings.inks.indices where mask & (1 << i) != 0 { let p = model.request.settings.inks[i].color; result.r *= p.r; result.g *= p.g; result.b *= p.b }
    return result
  }
  private func color(_ p: Pixel) -> Color { Color(.sRGB, red: Double(p.r), green: Double(p.g), blue: Double(p.b)) }
  private func pixel(_ color: Color) -> Pixel { let c = NSColor(color).usingColorSpace(.sRGB) ?? .black; return Pixel(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent)) }
  private func loadSettings() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 262_144 else { throw CraftError.invalid("Ink settings exceed 256 KiB.") }; try model.loadSettings(Data(contentsOf: url)); selectedInk = 0; selectedPoint = 0 }
    catch { model.error = error.localizedDescription }
  }
  private func saveSettings() {
    let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Duotone Settings.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try model.settingsData().write(to: url, options: .atomic) } catch { model.error = error.localizedDescription }
  }
}

private struct InkCurveGraph: View {
  let points: [InkCurvePoint]
  let selected: Int
  let move: (Float, Float) -> Void
  var body: some View {
    GeometryReader { area in
      Canvas { context, size in
        var grid = Path()
        for i in 0...4 { let x = size.width * Double(i) / 4, y = size.height * Double(i) / 4; grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height)); grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y)) }
        context.stroke(grid, with: .color(.gray.opacity(0.35)), lineWidth: 1)
        var path = Path()
        for (i, p) in points.enumerated() { let point = CGPoint(x: Double(p.input) * size.width, y: (1 - Double(p.output)) * size.height); if i == 0 { path.move(to: point) } else { path.addLine(to: point) } }
        context.stroke(path, with: .color(.white), lineWidth: 2)
        for (i, p) in points.enumerated() { context.fill(Path(ellipseIn: .init(x: Double(p.input) * size.width - 4, y: (1 - Double(p.output)) * size.height - 4, width: 8, height: 8)), with: .color(i == selected ? .accentColor : .white)) }
      }.background(Color(white: 0.16)).clipped().contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { event in move(Float(event.location.x / max(1, area.size.width)), Float(1 - event.location.y / max(1, area.size.height))) })
    }
  }
}
