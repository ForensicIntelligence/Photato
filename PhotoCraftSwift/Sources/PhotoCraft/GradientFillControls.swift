import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct GradientFillDraft {
  let sessionID = UUID()
  var layer: Layer
  var fill: GradientFill
  var creating: Bool
  var preview = true
  var command: Command {
    if creating {
      var layer = layer
      layer.content = .gradientFill(fill)
      return .addGradientFill(layer, true)
    }
    return .setGradientFill(layer.id, fill)
  }
}

extension EditorStore {
  private var gradientFillReady: Bool {
    !editingComponent && !geometryBusy && !hasToneDraft && transformDraft == nil
  }
  var canBeginGradientFill: Bool {
    guard gradientFillReady else { return false }
    let parent = activeLayer.flatMap { $0.isGroup ? $0.id : $0.parentID }
    return parent.map { !document.isLocked($0) } ?? true
  }
  func canEditGradientFill(_ id: UUID) -> Bool {
    guard gradientFillReady, !document.isLocked(id),
      let layer = document.layers.first(where: { $0.id == id }),
      case .gradientFill = layer.content
    else { return false }
    return true
  }
  func beginGradientFill(editing id: UUID? = nil) {
    guard gradientFillReady else { return }
    do {
      if let id {
        guard canEditGradientFill(id), let layer = document.layers.first(where: { $0.id == id }),
          case .gradientFill(let fill) = layer.content
        else { return }
        gradientFillDraft = .init(layer: layer, fill: fill, creating: false)
      } else {
        guard canBeginGradientFill else { return }
        let fill = GradientFill(
          gradient: try gradientOptions.gradient.resolved(
            foreground: brush.color, background: backgroundColor))
        let layer = Layer(name: "Gradient Fill", content: .gradientFill(fill))
        gradientFillDraft = .init(layer: layer, fill: fill, creating: true)
      }
      status = "Gradient Fill · Drag in the image to position · Return to apply · Esc to cancel"
      render()
    } catch { self.error = error.localizedDescription }
  }
  func cancelGradientFill() {
    gradientFillDraft = nil
    status = "Gradient Fill cancelled"
    render()
  }
  func commitGradientFill() {
    guard let draft = gradientFillDraft else { return }
    gradientFillDraft = nil
    performGeometry(draft.command) { [weak self] in self?.propertiesTab = .properties }
  }
  func chooseGradient(_ gradient: GradientDefinition) {
    do {
      gradientFillDraft?.fill.gradient = try gradient.resolved(
        foreground: brush.color, background: backgroundColor)
      render()
    } catch { self.error = error.localizedDescription }
  }
  func dragGradientFill(from initial: GradientFill, x: Double, y: Double) {
    guard let draft = gradientFillDraft, x.isFinite, y.isFinite else { return }
    do {
      var doc = document
      try draft.command.apply(to: &doc)
      guard let layer = doc.layers.first(where: { $0.id == draft.layer.id }) else { return }
      let frame = try initial.frame(for: layer, width: doc.width, height: doc.height)
      var fill = initial
      fill.placement.offsetX += Float(x / Double(frame.width))
      fill.placement.offsetY += Float(y / Double(frame.height))
      try fill.validate()
      gradientFillDraft?.fill = fill
      render()
    } catch { self.error = error.localizedDescription }
  }
}

struct GradientSwatch: View {
  let gradient: GradientDefinition
  var body: some View {
    ZStack {
      Checkerboard()
      Canvas { context, size in
        guard let ramp = try? GradientRamp(gradient) else { return }
        for i in 0..<128 {
          let p = ramp.sample(Float(i) / 127)
          let box = CGRect(
            x: CGFloat(i) * size.width / 128, y: 0, width: size.width / 128,
            height: size.height)
          context.fill(
            Path(box),
            with: .color(
              Color(
                .sRGB, red: Double(p.r), green: Double(p.g), blue: Double(p.b), opacity: Double(p.a)
              )), style: FillStyle(antialiased: false))
        }
      }
    }.clipped().accessibilityLabel(gradient.name)
  }
}

struct GradientFillEditor: View {
  @Bindable var store: EditorStore
  @State private var showStops = CommandLine.arguments.contains("--expand-gradient-editor")
  @State private var showPresets = false
  private func binding<T>(_ key: WritableKeyPath<GradientFill, T>, fallback: T) -> Binding<T> {
    Binding(
      get: { store.gradientFillDraft?.fill[keyPath: key] ?? fallback },
      set: {
        store.gradientFillDraft?.fill[keyPath: key] = $0
        store.render()
      })
  }
  private func value(_ key: WritableKeyPath<GradientFill, Float>, factor: Double = 1) -> Binding<
    Double
  > {
    Binding(
      get: { Double(store.gradientFillDraft?.fill[keyPath: key] ?? 0) * factor },
      set: {
        guard $0.isFinite else { return }
        store.gradientFillDraft?.fill[keyPath: key] = Float($0 / factor)
        store.render()
      })
  }
  private func colorValue(_ index: Int) -> Binding<Color> {
    Binding(
      get: {
        guard let stops = store.gradientFillDraft?.fill.gradient.colors,
          stops.indices.contains(index)
        else { return .black }
        let p = stops[index].color.resolved(foreground: .black, background: .white)
        return Color(.sRGB, red: Double(p.r), green: Double(p.g), blue: Double(p.b))
      },
      set: {
        guard let c = NSColor($0).usingColorSpace(.sRGB), let draft = store.gradientFillDraft,
          draft.fill.gradient.colors.indices.contains(index)
        else { return }
        store.gradientFillDraft?.fill.gradient.colors[index].color = .rgb(
          Pixel(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent)))
        store.render()
      })
  }
  private func stopValue(_ index: Int, opacity: Bool, midpoint: Bool = false, alpha: Bool = false)
    -> Binding<Double>
  {
    Binding(
      get: {
        guard let g = store.gradientFillDraft?.fill.gradient else { return 0 }
        if opacity {
          guard g.opacity.indices.contains(index) else { return 0 }
          return Double(
            alpha
              ? g.opacity[index].opacity
              : midpoint ? g.opacity[index].midpoint : g.opacity[index].position) * 100
        }
        guard g.colors.indices.contains(index) else { return 0 }
        return Double(midpoint ? g.colors[index].midpoint : g.colors[index].position) * 100
      },
      set: {
        guard $0.isFinite, let g = store.gradientFillDraft?.fill.gradient else { return }
        let v = Float(max(0, min(100, $0)) / 100)
        if opacity {
          guard g.opacity.indices.contains(index) else { return }
          if alpha {
            store.gradientFillDraft?.fill.gradient.opacity[index].opacity = v
          } else if midpoint {
            store.gradientFillDraft?.fill.gradient.opacity[index].midpoint = v
          } else {
            store.gradientFillDraft?.fill.gradient.opacity[index].position = v
          }
        } else {
          guard g.colors.indices.contains(index) else { return }
          if midpoint {
            store.gradientFillDraft?.fill.gradient.colors[index].midpoint = v
          } else {
            store.gradientFillDraft?.fill.gradient.colors[index].position = v
          }
        }
        store.render()
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      Text("Gradient Fill").font(.headline)
      if let draft = store.gradientFillDraft {
        HStack {
          GradientSwatch(gradient: draft.fill.gradient).frame(height: 25)
          Button("Presets") { showPresets.toggle() }.fixedSize()
            .popover(isPresented: $showPresets) {
              GradientsPanel(store: store, compact: true).frame(width: 320, height: 310)
            }
        }
        Picker("Style", selection: binding(\.placement.style, fallback: .linear)) {
          ForEach(GradientStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        HStack {
          Text("Angle")
          Slider(value: value(\.placement.angle), in: -180...180)
          TextField(
            "Angle", value: value(\.placement.angle),
            format: .number.precision(.fractionLength(0...2))
          ).frame(width: 58)
          Text("°")
        }
        HStack {
          Text("Scale")
          Slider(value: value(\.placement.scale, factor: 100), in: 1...1000)
          TextField(
            "Scale", value: value(\.placement.scale, factor: 100),
            format: .number.precision(.fractionLength(0...2))
          ).frame(
            width: 58)
          Text("%")
        }
        Picker("Method", selection: binding(\.gradient.method, fallback: .perceptual)) {
          ForEach(GradientMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        HStack {
          Toggle("Reverse", isOn: binding(\.placement.reverse, fallback: false))
          Toggle("Dither", isOn: binding(\.dither, fallback: true))
          Toggle("Align with Layer", isOn: binding(\.aligned, fallback: true))
        }.font(.caption)
        HStack {
          Text("X")
          TextField(
            "Horizontal offset", value: value(\.placement.offsetX, factor: 100),
            format: .number.precision(.fractionLength(0...2)))
          Text("Y")
          TextField(
            "Vertical offset", value: value(\.placement.offsetY, factor: 100),
            format: .number.precision(.fractionLength(0...2)))
          Text("%")
          Button("Reset") {
            store.gradientFillDraft?.fill.placement.offsetX = 0
            store.gradientFillDraft?.fill.placement.offsetY = 0
            store.render()
          }
        }
        DisclosureGroup("Edit Gradient", isExpanded: $showStops) {
          VStack(spacing: 8) {
            HStack {
              Text("Smoothness")
              Slider(value: value(\.gradient.smoothness, factor: 100), in: 0...100)
              TextField(
                "Smoothness", value: value(\.gradient.smoothness, factor: 100), format: .number
              ).frame(width: 48)
              Text("%")
            }
            HStack {
              Text("Color")
              Spacer()
              Text("Location %")
              Text("Midpoint %")
              Spacer().frame(width: 24)
            }.font(.caption)
            ScrollView {
              VStack(spacing: 5) {
                ForEach(draft.fill.gradient.colors.indices, id: \.self) { i in
                  HStack {
                    ColorPicker("Stop \(i + 1)", selection: colorValue(i), supportsOpacity: false)
                      .labelsHidden()
                    Spacer()
                    TextField(
                      "Color location", value: stopValue(i, opacity: false), format: .number
                    ).frame(width: 66)
                    TextField(
                      "Color midpoint", value: stopValue(i, opacity: false, midpoint: true),
                      format: .number
                    ).frame(width: 66)
                    Button {
                      store.gradientFillDraft?.fill.gradient.colors.remove(at: i)
                      store.render()
                    } label: {
                      Image(systemName: "minus.circle")
                    }
                    .disabled(draft.fill.gradient.colors.count <= 1).help("Delete color stop")
                  }
                }
              }
            }.frame(maxHeight: 100)
            Button("Add Color Stop") {
              let c = store.brush.color
              store.gradientFillDraft?.fill.gradient.colors.append(
                .init(0.5, .rgb(Pixel(c.r, c.g, c.b))))
              store.render()
            }.disabled(draft.fill.gradient.colors.count >= GradientDefinition.maxStops)
            HStack {
              Text("Opacity %")
              Spacer()
              Text("Location %")
              Text("Midpoint %")
              Spacer().frame(width: 24)
            }.font(.caption)
            ScrollView {
              VStack(spacing: 5) {
                ForEach(draft.fill.gradient.opacity.indices, id: \.self) { i in
                  HStack {
                    TextField(
                      "Opacity", value: stopValue(i, opacity: true, alpha: true), format: .number
                    ).frame(width: 66)
                    Spacer()
                    TextField(
                      "Opacity location", value: stopValue(i, opacity: true), format: .number
                    ).frame(width: 66)
                    TextField(
                      "Opacity midpoint", value: stopValue(i, opacity: true, midpoint: true),
                      format: .number
                    ).frame(width: 66)
                    Button {
                      store.gradientFillDraft?.fill.gradient.opacity.remove(at: i)
                      store.render()
                    } label: {
                      Image(systemName: "minus.circle")
                    }.help("Delete opacity stop")
                  }
                }
              }
            }.frame(maxHeight: 85)
            Button("Add Opacity Stop") {
              store.gradientFillDraft?.fill.gradient.opacity.append(.init(0.5, 1))
              store.render()
            }.disabled(draft.fill.gradient.opacity.count >= GradientDefinition.maxStops)
          }.padding(.top, 6)
        }
        Text("Drag in the image to reposition the gradient.").font(.caption).foregroundStyle(
          .secondary)
        Divider()
        HStack {
          Toggle(
            "Preview",
            isOn: Binding(
              get: { draft.preview },
              set: {
                store.gradientFillDraft?.preview = $0
                store.render()
              }))
          Spacer()
          Button("Save Preset…") { store.beginSaveGradientPreset() }.disabled(store.gradients.busy)
          Button("Cancel") { store.cancelGradientFill() }.keyboardShortcut(.cancelAction)
          Button("OK") { store.commitGradientFill() }.keyboardShortcut(.defaultAction)
            .disabled((try? draft.fill.validate()) == nil)
        }
      }
    }.textFieldStyle(.roundedBorder).padding(16).frame(width: 390)
      .background(StudioTheme.panel).clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
      .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
  }
}
