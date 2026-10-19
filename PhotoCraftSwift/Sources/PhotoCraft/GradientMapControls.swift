import AppKit
import PhotoCraftCore
import SwiftUI

struct GradientMapDraft: Identifiable, Sendable {
  let sessionID = UUID()
  let id: UUID
  var adjustment: GradientMapAdjustment
  var preview = true
}

struct GradientMapEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  @State private var showPresets = false
  @State private var showStops = false
  var adjustment: GradientMapAdjustment {
    if pixelLayer, let draft = store.gradientMapDraft { return draft.adjustment }
    if case .adjustment(.gradientMap(let value)) = store.document.layers.first(where: {
      $0.id == layerID
    })?.content {
      return value
    }
    return .init()
  }
  var settings: Binding<GradientMapAdjustment> {
    Binding(
      get: { adjustment },
      set: { value in
        if pixelLayer {
          store.gradientMapDraft?.adjustment = value
          store.render()
        } else {
          store.setGradientMap(layerID, value)
        }
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        showPresets.toggle()
      } label: {
        HStack {
          GradientSwatch(gradient: adjustment.gradient).frame(height: 26)
          Image(systemName: "chevron.down")
        }
      }.buttonStyle(.plain).help("Choose Gradient Map preset")
        .popover(isPresented: $showPresets) {
          GradientsPanel(store: store, compact: true).frame(width: 320, height: 310)
        }
      HStack {
        Toggle("Dither", isOn: settings.dither)
        Toggle("Reverse", isOn: settings.reverse)
      }
      Picker("Method", selection: settings.gradient.method) {
        ForEach(GradientMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      HStack {
        Button("Edit Gradient…") { showStops.toggle() }
          .popover(isPresented: $showStops) {
            GradientMapStops(
              gradient: settings.gradient, coalesce: { if !pixelLayer { store.coalesce($0) } }
            ).padding(16).frame(width: 390)
              .onDisappear { if !pixelLayer { store.coalesce(false) } }
          }
        Button("Save Preset…") { store.beginSaveGradientPreset() }.disabled(store.gradients.busy)
      }
      if store.document.depth == .f32 {
        Text("Gradient Map is available in 8- and 16-bit documents.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.controlSize(.small).disabled(store.document.depth == .f32)
  }
}

/// Numeric, retained color controls shared by pixel and adjustment-layer maps.
struct GradientMapStops: View {
  @Binding var gradient: GradientDefinition
  var coalesce: (Bool) -> Void = { _ in }
  private func number(_ index: Int, midpoint: Bool) -> Binding<Double> {
    Binding(
      get: {
        guard gradient.colors.indices.contains(index) else { return 0 }
        return Double(midpoint ? gradient.colors[index].midpoint : gradient.colors[index].position)
          * 100
      },
      set: { value in
        guard value.isFinite, gradient.colors.indices.contains(index) else { return }
        if midpoint {
          gradient.colors[index].midpoint = Float(min(100, max(0, value)) / 100)
        } else {
          gradient.colors[index].position = Float(min(100, max(0, value)) / 100)
        }
      })
  }
  private func color(_ index: Int) -> Binding<Color> {
    Binding(
      get: {
        guard gradient.colors.indices.contains(index) else { return .black }
        let p = gradient.colors[index].color.resolved(foreground: .black, background: .white)
        return Color(.sRGB, red: Double(p.r), green: Double(p.g), blue: Double(p.b))
      },
      set: {
        guard gradient.colors.indices.contains(index),
          let color = NSColor($0).usingColorSpace(.sRGB)
        else { return }
        gradient.colors[index].color = .rgb(
          Pixel(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent)))
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Gradient Editor").font(.headline)
      TextField("Name", text: $gradient.name)
      GradientSwatch(gradient: gradient).frame(height: 28)
      HStack {
        Text("Smoothness")
        Slider(
          value: Binding(
            get: { Double(gradient.smoothness) * 100 },
            set: { if $0.isFinite { gradient.smoothness = Float($0 / 100) } }), in: 0...100,
          onEditingChanged: coalesce)
        Text("\(Int(gradient.smoothness * 100)) %").monospacedDigit().frame(width: 48)
      }
      HStack {
        Text("Color")
        Spacer()
        Text("Location %").frame(width: 78)
        Text("Midpoint %").frame(width: 78)
        Spacer().frame(width: 22)
      }.font(.caption)
      ScrollView {
        VStack {
          ForEach(gradient.colors.indices, id: \.self) { i in
            HStack {
              ColorPicker("Color stop \(i + 1)", selection: color(i), supportsOpacity: false)
                .labelsHidden()
              Spacer()
              TextField(
                "Location", value: number(i, midpoint: false),
                format: .number.precision(.fractionLength(0...2))
              ).frame(width: 78)
              TextField(
                "Midpoint", value: number(i, midpoint: true),
                format: .number.precision(.fractionLength(0...2))
              ).frame(width: 78)
              Button {
                gradient.colors.remove(at: i)
              } label: {
                Image(systemName: "minus.circle")
              }
              .disabled(gradient.colors.count <= 1).help("Delete color stop")
            }
          }
        }
      }.frame(height: min(220, CGFloat(gradient.colors.count) * 31))
      Button("Add Color Stop") { gradient.colors.append(.init(0.5, .rgb(.white))) }
        .disabled(gradient.colors.count >= GradientDefinition.maxStops)
      Text("Gradient Map preserves the image’s transparency.").font(.caption).foregroundStyle(
        .secondary)
    }.textFieldStyle(.roundedBorder)
  }
}

struct GradientMapSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Gradient Map").font(.title2.bold())
      if let draft = store.gradientMapDraft {
        GradientMapEditor(store: store, layerID: draft.id, pixelLayer: true)
      }
      Divider()
      HStack {
        Toggle(
          "Preview",
          isOn: Binding(
            get: { store.gradientMapDraft?.preview ?? false },
            set: {
              store.gradientMapDraft?.preview = $0
              store.render()
            }))
        Spacer()
        Button("Cancel") { store.cancelGradientMap() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitGradientMap() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 390)
      .sheet(item: $store.gradientNameDraft) { draft in
        GradientNameSheet(store: store, draft: draft)
      }
  }
}

extension EditorStore {
  var canBeginGradientMap: Bool { document.depth != .f32 && canBeginLevels }
  var canAddGradientMap: Bool {
    document.depth != .f32 && !geometryBusy && transformDraft == nil && !hasToneDraft
  }
  func initialGradientMap() throws -> GradientMapAdjustment {
    .init(
      gradient: try gradientOptions.gradient.resolved(
        foreground: brush.color, background: backgroundColor))
  }
  func beginGradientMap() {
    guard canBeginGradientMap, let layer = activeLayer else { return }
    do { gradientMapDraft = .init(id: layer.id, adjustment: try initialGradientMap()) } catch {
      self.error = error.localizedDescription
    }
  }
  func cancelGradientMap() {
    gradientMapDraft = nil
    render()
  }
  func commitGradientMap() {
    guard let draft = gradientMapDraft else { return }
    gradientMapDraft = nil
    performGeometry(.applyAdjustment(draft.id, .gradientMap(draft.adjustment)))
  }
  func addGradientMapLayer() {
    guard canAddGradientMap else { return }
    do { addToneLayer(.gradientMap(try initialGradientMap()), name: "Gradient Map") } catch {
      self.error = error.localizedDescription
    }
  }
  func setGradientMap(_ id: UUID, _ value: GradientMapAdjustment) {
    guard document.depth != .f32,
      case .adjustment(.gradientMap) = document.layers.first(where: { $0.id == id })?.content
    else { return }
    perform(.replaceContent(id, .adjustment(.gradientMap(value))))
  }
}
