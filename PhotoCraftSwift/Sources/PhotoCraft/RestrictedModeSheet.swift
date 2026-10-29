import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

struct RestrictedModeSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: RestrictedModeWorkspace
  @State private var selectedColor = 0
  var body: some View {
    VStack(spacing: 12) {
      HStack { Text(model.request.title).font(.headline); Spacer(); if model.rendering || model.committing { ProgressView().controlSize(.small) } }
      HStack(alignment: .top, spacing: 18) {
        GeometryReader { area in
          ZStack {
            Color(white: 0.12)
            if let image = model.preview ? model.image : model.originalImage {
              Image(decorative: image, scale: 1).resizable().scaledToFit().padding(12).frame(width: area.size.width, height: area.size.height)
            }
          }.clipped().accessibilityLabel(model.request.title + " preview")
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            switch model.request.kind {
            case .indexed: indexedControls
            case .bitmap: bitmapControls
            case .colorTable: tableControls
            }
            if model.request.kind != .colorTable, RestrictedModeInput.needsMerge(model.source) {
              Divider()
              Toggle("Merge visible layers", isOn: binding(\.mergeVisible))
              Text("Replaces the stack with its visible image and discards hidden layers and auxiliary channels. Undo restores the original document.").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.trailing, 4)
        }.frame(width: 330).disabled(model.committing)
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Toggle("Preview", isOn: $model.preview)
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: .command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: [.command, .shift])
        Spacer()
        Button("Cancel") { store.cancelRestrictedMode() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitRestrictedMode() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(16).frame(width: 880, height: 620).background(Color(nsColor: .windowBackgroundColor))
      .onDisappear { model.close(); if store.restrictedModeWorkspace === model { store.restrictedModeWorkspace = nil } }
  }
  private func binding<T>(_ path: WritableKeyPath<RestrictedModeRequest, T>) -> Binding<T> {
    Binding(get: { model.request[keyPath: path] }, set: { value in model.update { $0[keyPath: path] = value } })
  }
  private var indexedControls: some View {
    Group {
      Picker("Palette", selection: binding(\.indexed.palette)) {
        ForEach(IndexedPaletteKind.allCases, id: \.self) { Text($0.displayTitle).tag($0) }
      }
      if [.masterAdaptive, .masterPerceptual, .masterSelective].contains(model.request.indexed.palette) {
        Text("Uses snapshots of this image and \(model.masters.count) other open RGB/Grayscale 8-bit images, captured when this dialog opened.").font(.caption).foregroundStyle(.secondary)
      }
      if model.request.indexed.palette == .previous {
        Text(model.request.previousPalette == nil ? "No previous palette in this document session. Load a custom table instead." : "Uses the last palette accepted in this document session.").font(.caption).foregroundStyle(.secondary)
      }
      if model.request.indexed.palette == .custom { Button("Load Custom Table…") { loadTable(target: .custom) } }
      HStack { Text("Colors"); Spacer(); TextField("Colors", value: binding(\.indexed.colors), format: .number).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 100) }
      Picker("Forced", selection: binding(\.indexed.forced)) {
        Text("None").tag(IndexedForcedColors.none); Text("Black and White").tag(IndexedForcedColors.blackWhite)
        Text("Primaries").tag(IndexedForcedColors.primaries); Text("Web").tag(IndexedForcedColors.web); Text("Custom").tag(IndexedForcedColors.custom)
      }
      if model.request.indexed.forced == .custom { Button("Load Forced Colors…") { loadTable(target: .forced) } }
      Toggle("Transparency", isOn: binding(\.indexed.transparency))
      Toggle("Matte", isOn: Binding(get: { model.request.indexed.matte != nil }, set: { enabled in model.update { $0.indexed.matte = enabled ? .init(255, 255, 255) : nil } }))
      if model.request.indexed.matte != nil {
        ColorPicker("Matte color", selection: Binding(get: { color(model.request.indexed.matte!) }, set: { value in if let rgb = paletteColor(value) { model.update { $0.indexed.matte = rgb } } }), supportsOpacity: false)
      }
      Picker("Dither", selection: binding(\.indexed.dither)) {
        Text("None").tag(IndexedDither.none); Text("Diffusion").tag(IndexedDither.diffusion)
        Text("Pattern").tag(IndexedDither.pattern); Text("Noise").tag(IndexedDither.noise)
      }
      if model.request.indexed.dither == .diffusion {
        HStack { Text("Amount"); Slider(value: binding(\.indexed.amount), in: 0...1); Text("\(Int((model.request.indexed.amount * 100).rounded()))%").monospacedDigit() }
      }
      Toggle("Preserve Exact Colors", isOn: binding(\.indexed.preserveExact))
    }
  }
  private var bitmapControls: some View {
    Group {
      Text("Input: \(model.source.pixelsPerInch, specifier: "%.2f") pixels/inch").foregroundStyle(.secondary)
      HStack { Text("Output pixels/inch"); Spacer(); TextField("Output pixels/inch", value: binding(\.bitmap.outputResolution), format: .number).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 100) }
      Picker("Method", selection: binding(\.bitmap.method)) {
        Text("50% Threshold").tag(BitmapConversionMethod.threshold)
        Text("Pattern Dither").tag(BitmapConversionMethod.pattern)
        Text("Diffusion Dither").tag(BitmapConversionMethod.diffusion)
        Text("Halftone Screen").tag(BitmapConversionMethod.halftone)
        Text("Custom Pattern").tag(BitmapConversionMethod.customPattern)
      }
      if model.request.bitmap.method == .halftone {
        HStack { Text("Frequency (lines/inch)"); Spacer(); TextField("Frequency (lines/inch)", value: binding(\.bitmap.frequency), format: .number).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 100) }
        HStack { Text("Angle (degrees)"); Spacer(); TextField("Angle (degrees)", value: binding(\.bitmap.angle), format: .number).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 100) }
        Picker("Shape", selection: binding(\.bitmap.shape)) {
          ForEach(BitmapHalftoneShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
      }
      if model.request.bitmap.method == .customPattern {
        Button("Load Pattern Image…") { loadPattern() }
        if let pattern = model.request.bitmap.pattern { Text("\(pattern.width) × \(pattern.height) threshold tile").font(.caption) }
        Text("The grayscale image repeats as a threshold tile. Custom-pattern phase and resampling may differ from Photoshop.").font(.caption).foregroundStyle(.secondary)
      }
      Text("Output contains pure black and white pixels. Transparent pixels are composited over white.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private var tableControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(model.request.colors.count) colors").font(.subheadline)
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 2), count: 16), spacing: 2) {
        ForEach(model.request.colors.indices, id: \.self) { i in
          Button { selectedColor = i } label: {
            Rectangle().fill(color(model.request.colors[i])).frame(width: 16, height: 16)
              .overlay { if model.request.transparentIndex == i { Image(systemName: "slash.circle").font(.system(size: 12)).foregroundStyle(.white) } }
              .overlay(Rectangle().stroke(selectedColor == i ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: selectedColor == i ? 2 : 0.5))
          }.buttonStyle(.plain).help("Index \(i)").accessibilityLabel("Color table index \(i)")
        }
      }
      if model.request.colors.indices.contains(selectedColor) {
        ColorPicker("Index \(selectedColor)", selection: Binding(get: { color(model.request.colors[selectedColor]) }, set: { value in
          if let rgb = paletteColor(value) { model.update { $0.colors[selectedColor] = rgb } }
        }), supportsOpacity: false)
        Toggle("Transparent index", isOn: Binding(get: { model.request.transparentIndex == selectedColor }, set: { enabled in model.update { $0.transparentIndex = enabled ? selectedColor : nil } }))
      }
      HStack { Button("Load…") { loadTable(target: .table) }; Button("Save…") { saveTable() } }
      Text("Changing a color changes every pixel using that index. Pixel indices and duplicate entries are preserved.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private enum TableTarget { case table, custom, forced }
  private func loadTable(target: TableTarget) {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedContentTypes = [UTType(filenameExtension: "act") ?? .data]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard [768, 772].contains(size) else { throw CraftError.invalid("Choose a 768- or 772-byte ACT color table.") }
      let table = try ColorTableFile(data: Data(contentsOf: url))
      model.update {
        switch target {
        case .table: $0.colors = table.colors; $0.transparentIndex = table.transparentIndex
        case .custom: $0.indexed.customPalette = table.colors
        case .forced: $0.indexed.forcedColors = table.colors.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
      }; selectedColor = 0
    } catch { model.error = error.localizedDescription }
  }
  private func saveTable() {
    let panel = NSSavePanel(); panel.nameFieldStringValue = "Color Table.act"; panel.allowedContentTypes = [UTType(filenameExtension: "act") ?? .data]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try ColorTableFile(colors: model.request.colors, transparentIndex: model.request.transparentIndex).encoded().write(to: url, options: .atomic) }
    catch { model.error = error.localizedDescription }
  }
  private func loadPattern() {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.png, .tiff]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0, size <= 8_388_608 else { throw CraftError.invalid("Choose a pattern image of at most 8 MiB.") }
      let document = try RasterIO.read(Data(contentsOf: url))
      guard document.width <= 1024, document.height <= 1024 else { throw CraftError.invalid("Pattern images must be at most 1024 × 1024 pixels.") }
      let pixels = try Renderer.composite(document)
      var samples = Data(); samples.reserveCapacity(document.width * document.height)
      for y in 0..<document.height { for x in 0..<document.width {
        let p = pixels.pixel(x: x, y: y); samples.append(UInt8((unit((p.r * 0.299 + p.g * 0.587 + p.b * 0.114) * p.a + 1 - p.a) * 255).rounded()))
      } }
      let pattern = try BitmapThresholdPattern(width: document.width, height: document.height, samples: samples)
      model.update { $0.bitmap.pattern = pattern }
    } catch { model.error = error.localizedDescription }
  }
  private func color(_ rgb: PaletteColor) -> Color { Color(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255, opacity: 1) }
  private func paletteColor(_ color: Color) -> PaletteColor? {
    guard let value = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return .init(UInt8((min(1, max(0, value.redComponent)) * 255).rounded()), UInt8((min(1, max(0, value.greenComponent)) * 255).rounded()), UInt8((min(1, max(0, value.blueComponent)) * 255).rounded()))
  }
}

extension IndexedPaletteKind {
  var displayTitle: String {
    switch self {
    case .exact: "Exact"; case .systemMac: "System (Mac OS)"; case .systemWindows: "System (Windows)"
    case .web: "Web"; case .uniform: "Uniform"; case .localPerceptual: "Local (Perceptual)"
    case .localSelective: "Local (Selective)"; case .localAdaptive: "Local (Adaptive)"
    case .masterPerceptual: "Master (Perceptual)"; case .masterSelective: "Master (Selective)"
    case .masterAdaptive: "Master (Adaptive)"; case .custom: "Custom"; case .previous: "Previous"
    }
  }
}
