import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct HueSaturationDraft: Identifiable, Sendable {
  let id: UUID
  var adjustment = HueSaturationAdjustment()
  var preview = true
}

struct HueSaturationControls: View {
  @Binding var adjustment: HueSaturationAdjustment
  var coalesce: (Bool) -> Void = { _ in }
  @State private var channel = HueSaturationAdjustment.Channel.master
  @State private var importing = false
  @State private var exporting = false
  @State private var presetFile: HueSaturationPresetFile?
  @State private var loadedPreset: HueSaturationPresetFile?
  @State private var presetError: String?
  init(
    adjustment: Binding<HueSaturationAdjustment>, coalesce: @escaping (Bool) -> Void = { _ in },
    channel: HueSaturationAdjustment.Channel = .master
  ) {
    _adjustment = adjustment
    self.coalesce = coalesce
    _channel = State(initialValue: channel)
  }
  var body: some View {
    let transfer = HueSaturationTransfer(adjustment, depth: .u8)
    VStack(alignment: .leading, spacing: 12) {
      Menu {
        ForEach(BuiltInHueSaturationPreset.allCases, id: \.self) { preset in
          Button(preset.rawValue) {
            adjustment = preset.adjustment
            channel = .master
          }
        }
        Divider()
        Button("Load Hue/Saturation Preset…") { importing = true }
        Button("Save Hue/Saturation Preset…") {
          presetFile = .init(adjustment: adjustment, original: loadedPreset?.original)
          exporting = true
        }
      } label: {
        Text(
          "Preset: \(BuiltInHueSaturationPreset.allCases.first(where: { $0.adjustment == adjustment })?.rawValue ?? "Custom")"
        )
      }
      HStack(spacing: 7) {
        ForEach(HueSaturationAdjustment.Channel.allCases.filter { $0 != .master }, id: \.self) {
          target in
          let swatch = adjustment.ranges[target.rangeIndex ?? 0].swatchColor
          let before = swatch.pixel
          Button {
            channel = target
          } label: {
            HStack(spacing: 0) {
              Rectangle().fill(color(before))
              Rectangle().fill(color(transfer.apply(before)))
            }.frame(height: 28).clipShape(Circle())
              .overlay(Circle().stroke(channel == target ? Color.white : .clear, lineWidth: 2))
          }.buttonStyle(.plain).help("\(target.rawValue): original and adjusted color")
            .accessibilityLabel("Edit \(target.rawValue.lowercased())")
            .accessibilityValue("Hue \(swatch.hue) degrees, saturation \(swatch.saturation) percent, lightness \(swatch.lightness) percent")
        }
      }.disabled(adjustment.colorize)
      Picker("Color range", selection: $channel) {
        ForEach(HueSaturationAdjustment.Channel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.disabled(adjustment.colorize)
      control("Hue", key: \.hue, range: adjustment.colorize ? 0...360 : -180...180)
      control("Saturation", key: \.saturation, range: adjustment.colorize ? 0...100 : -100...100)
      control("Lightness", key: \.lightness, range: -100...100)
      Toggle("Colorize", isOn: $adjustment.colorize)
        .onChange(of: adjustment.colorize) { _, enabled in if enabled { channel = .master } }
      if let index = channel.rangeIndex, !adjustment.colorize {
        HueRangeWheel(range: $adjustment.ranges[index], coalesce: coalesce)
          .frame(height: 174)
        HStack(spacing: 6) {
          ForEach(0..<4) { edge in
            VStack(spacing: 4) {
              Text(["Fade in", "Start", "End", "Fade out"][edge]).foregroundStyle(.secondary)
              TextField(
                "Degrees",
                value: Binding<Double>(
                  get: {
                    Double((adjustment.ranges[index].bounds[edge] % 360 + 360) % 360)
                  },
                  set: { value in
                    guard value.isFinite else { return }
                    let current = adjustment.ranges[index].bounds[edge]
                    let degrees = min(359, max(0, value)).rounded()
                    let unwrapped =
                      Int(degrees) + Int(((Double(current) - degrees) / 360).rounded()) * 360
                    adjustment.ranges[index].moveEdge(edge, to: unwrapped)
                  }), format: .number.precision(.fractionLength(0))
              )
              .textFieldStyle(.roundedBorder).monospacedDigit()
              .accessibilityLabel("\(["Fade in", "Start", "End", "Fade out"][edge]) degrees")
            }
          }
        }
        Text(
          "Inner markers set full strength; outer triangles set the falloff. Drag the ring to rotate the range."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      HueSpectrum(transfer: transfer).frame(height: 26)
      HStack {
        Button("Reset Range") {
          if adjustment.colorize {
            adjustment.colorization = .init(saturation: 25)
          } else if let index = channel.rangeIndex {
            adjustment.ranges[index] = .neutral(index)
          } else {
            adjustment.master = .init()
          }
        }
        Button("Reset All") {
          adjustment = .init()
          channel = .master
        }
      }
    }.controlSize(.small)
      .fileImporter(isPresented: $importing, allowedContentTypes: [HueSaturationPresetFile.type]) {
        result in
        do {
          let preset = try HueSaturationPresetFile.load(result.get())
          loadedPreset = preset
          adjustment = preset.adjustment
          channel = .master
        } catch { presetError = error.localizedDescription }
      }
      .fileExporter(
        isPresented: $exporting, document: presetFile,
        contentType: HueSaturationPresetFile.type, defaultFilename: "Hue-Saturation.ahu"
      ) { result in
        if case .failure(let error) = result { presetError = error.localizedDescription }
      }
      .alert(
        "Hue/Saturation",
        isPresented: Binding(get: { presetError != nil }, set: { if !$0 { presetError = nil } })
      ) {
        Button("OK") { presetError = nil }
      } message: {
        Text(presetError ?? "")
      }
  }
  func color(_ p: Pixel) -> Color { Color(red: Double(p.r), green: Double(p.g), blue: Double(p.b)) }
  func control(
    _ title: String, key: WritableKeyPath<HueSaturationValues, Int>, range: ClosedRange<Double>
  ) -> some View {
    let binding = Binding<Double>(
      get: {
        let value = adjustment[channel][keyPath: key]
        return Double(adjustment.colorize && key == \.hue && value < 0 ? value + 360 : value)
      },
      set: { value in
        guard value.isFinite else { return }
        var record = adjustment[channel]
        let number = Int(min(range.upperBound, max(range.lowerBound, value)).rounded())
        record[keyPath: key] =
          adjustment.colorize && key == \.hue && number > 180 ? number - 360 : number
        adjustment[channel] = record
      })
    return VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title)
        Spacer()
        TextField(title, value: binding, format: .number.precision(.fractionLength(0)))
          .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 60)
      }
      Slider(value: binding, in: range, step: 1, onEditingChanged: coalesce).accessibilityLabel(
        title)
    }
  }
}

struct HueSpectrum: View {
  let transfer: HueSaturationTransfer
  var body: some View {
    Canvas { context, size in
      for row in 0..<2 {
        let stops: [Gradient.Stop] = (0...360).map { i in
          let rgb = HSLColor.rgb(hue: Float(i) / 360, saturation: 1, lightness: 0.5)
          let original = Pixel(rgb.x, rgb.y, rgb.z)
          let p = row == 0 ? original : transfer.apply(original)
          return .init(
            color: Color(red: Double(p.r), green: Double(p.g), blue: Double(p.b)),
            location: CGFloat(i) / 360)
        }
        let shape = Path(
          CGRect(
            x: 0, y: CGFloat(row) * size.height / 2, width: size.width, height: size.height / 2))
        context.fill(
          shape,
          with: .linearGradient(
            Gradient(stops: stops), startPoint: .zero,
            endPoint: CGPoint(x: size.width, y: 0)))
      }
    }.accessibilityLabel("Original hue spectrum above, adjusted spectrum below")
  }
}

struct HueRangeWheel: View {
  @Binding var range: HueRange
  var coalesce: (Bool) -> Void
  @State private var dragEdge: Int?
  @State private var dragOrigin: [Int]?
  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 14
        let spectrum = (0...6).map { i in
          let rgb = HSLColor.rgb(hue: Float(i) / 6, saturation: 1, lightness: 0.5)
          return Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
        }
        let ring = Path(
          ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(
          ring, with: .conicGradient(Gradient(colors: spectrum), center: center), lineWidth: 12)
        let weights: [Gradient.Stop] = (0...360).map { degree in
          .init(
            color: .white.opacity(Double(range.weight(Float(degree))) * 0.8),
            location: CGFloat(degree) / 360)
        }
        let inner = Path(
          ellipseIn: CGRect(
            x: center.x - radius + 15, y: center.y - radius + 15, width: (radius - 15) * 2,
            height: (radius - 15) * 2))
        context.stroke(
          inner, with: .conicGradient(Gradient(stops: weights), center: center), lineWidth: 5)
        for edge in 0..<4 {
          let angle = Double(range.bounds[edge]) * .pi / 180
          let distance = radius + (edge == 0 || edge == 3 ? 10 : -12)
          let point = CGPoint(
            x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
          var marker = Path()
          if edge == 0 || edge == 3 {
            for i in 0..<3 {
              let direction = angle + Double(i) * 2 * .pi / 3 + .pi
              let p = CGPoint(x: point.x + cos(direction) * 6, y: point.y + sin(direction) * 6)
              if i == 0 { marker.move(to: p) } else { marker.addLine(to: p) }
            }
            marker.closeSubpath()
          } else {
            marker.addEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
          }
          context.fill(marker, with: .color(.white))
          context.stroke(marker, with: .color(.black), lineWidth: 1)
        }
      }.contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { value in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            if dragOrigin == nil {
              let radius = min(geometry.size.width, geometry.size.height) / 2 - 14
              guard
                hypot(value.startLocation.x - center.x, value.startLocation.y - center.y) > radius
                  - 25
              else { return }
              let degrees = angle(value.startLocation, center: center)
              let closest = (0..<4).min {
                distance(degrees, Double(range.bounds[$0]))
                  < distance(degrees, Double(range.bounds[$1]))
              }!
              dragEdge = distance(degrees, Double(range.bounds[closest])) < 12 ? closest : nil
              dragOrigin = range.bounds
              coalesce(true)
            }
            let degrees = angle(value.location, center: center)
            if let edge = dragEdge {
              let current = range.bounds[edge]
              let unwrapped =
                Int(degrees.rounded()) + Int(((Double(current) - degrees) / 360).rounded()) * 360
              range.moveEdge(edge, to: unwrapped)
            } else if let original = dragOrigin {
              let delta = Int((degrees - angle(value.startLocation, center: center)).rounded())
              let wrapped = original.map { (($0 + delta) % 360 + 360) % 360 }
              if let bounds = try? HueRange.fromWrapped(wrapped) { range.bounds = bounds }
            }
          }.onEnded { _ in endDrag() }
        )
        .onDisappear { endDrag() }
        .accessibilityLabel("Hue range and falloff wheel")
        .accessibilityHint("Use the four degree fields to edit range boundaries numerically.")
    }
  }
  func endDrag() {
    if dragOrigin != nil { coalesce(false) }
    dragOrigin = nil
    dragEdge = nil
  }
  func angle(_ p: CGPoint, center: CGPoint) -> Double {
    let degrees = atan2(p.y - center.y, p.x - center.x) * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
  }
  func distance(_ a: Double, _ b: Double) -> Double {
    let delta = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(delta, 360 - delta)
  }
}

struct HueSaturationEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  var body: some View {
    HueSaturationControls(
      adjustment: Binding(
        get: {
          if pixelLayer { return store.hueSaturationDraft?.adjustment ?? .init() }
          if case .adjustment(.hueSaturation(let value)) = store.document.layers.first(where: {
            $0.id == layerID
          })?.content {
            return value
          }
          return .init()
        },
        set: { value in
          if pixelLayer {
            store.hueSaturationDraft?.adjustment = value
            store.render()
          } else {
            store.setHueSaturation(layerID, value)
          }
        }), coalesce: { if !pixelLayer { store.coalesce($0) } })
  }
}

struct HueSaturationSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Hue/Saturation").font(.title2.bold())
      ScrollView {
        if let draft = store.hueSaturationDraft {
          HueSaturationEditor(store: store, layerID: draft.id, pixelLayer: true)
        }
      }.frame(maxHeight: 570)
      HStack {
        Toggle(
          "Preview",
          isOn: Binding(
            get: { store.hueSaturationDraft?.preview ?? false },
            set: {
              store.hueSaturationDraft?.preview = $0
              store.render()
            }))
        Spacer()
        Button("Cancel") { store.cancelHueSaturation() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitHueSaturation() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 380)
  }
}

extension EditorStore {
  var canBeginHueSaturation: Bool { canBeginLevels }
  func desaturate() {
    guard canBeginHueSaturation, let layer = activeLayer else { return }
    performGeometry(.desaturate(layer.id))
  }
  func beginHueSaturation() {
    guard canBeginHueSaturation, let layer = activeLayer else { return }
    hueSaturationDraft = .init(id: layer.id)
  }
  func cancelHueSaturation() {
    hueSaturationDraft = nil
    render()
  }
  func commitHueSaturation() {
    guard let draft = hueSaturationDraft else { return }
    hueSaturationDraft = nil
    performGeometry(.applyAdjustment(draft.id, .hueSaturation(draft.adjustment)))
  }
  func addHueSaturationLayer() { addToneLayer(.hueSaturation(.init()), name: "Hue/Saturation") }
  func setHueSaturation(_ id: UUID, _ adjustment: HueSaturationAdjustment) {
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .adjustment(.hueSaturation) = layer.content
    else { return }
    perform(.replaceContent(id, .adjustment(.hueSaturation(adjustment))))
  }
}

struct HueSaturationPresetFile: FileDocument {
  static let type = UTType(filenameExtension: "ahu") ?? .data
  static var readableContentTypes: [UTType] { [type] }
  var adjustment: HueSaturationAdjustment
  var original: Data?
  init(adjustment: HueSaturationAdjustment, original: Data? = nil) {
    self.adjustment = adjustment
    self.original = original
  }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CraftError.invalid("Invalid Hue/Saturation preset file.")
    }
    adjustment = try HueSaturationPresetCodec.read(data)
    original = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(
      regularFileWithContents: try HueSaturationPresetCodec.write(adjustment, original: original))
  }
  static func load(_ url: URL) throws -> Self {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 137) ?? Data()
    return .init(adjustment: try HueSaturationPresetCodec.read(data), original: data)
  }
}
