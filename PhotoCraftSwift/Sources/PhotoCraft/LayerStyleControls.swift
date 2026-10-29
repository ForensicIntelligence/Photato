import AppKit
import PhotoCraftCore
import SwiftUI

struct LayerStyleDraft: Identifiable, Sendable {
  let id: UUID
  let original: CraftDocument
  var style: LayerStyle
  var selected: Int = 0
  var preview = true
}

extension EditorStore {
  var canBeginLayerStyle: Bool {
    guard canBeginLayerCreation, !editingComponent, !editingMask,
      let layer = activeLayer, !document.isLocked(layer.id),
      document.width <= 8_388_608 / document.height else { return false }
    if case .adjustment = layer.content { return false }
    return true
  }
  var canCopyLayerStyle: Bool { canBeginLayerStyle && activeLayer?.style != nil }
  var canPasteLayerStyle: Bool { canBeginLayerStyle && Self.copiedLayerStyle != nil }
  var canClearLayerStyle: Bool { canBeginLayerStyle && document.layers.contains { groupSelectionIDs.contains($0.id) && $0.style != nil } }
  func beginLayerStyle(_ kind: LayerEffect.Kind? = nil) {
    guard canBeginLayerStyle, let layer = activeLayer else { return }
    layerStyleDraft = .init(id: layer.id, original: document, style: layer.style ?? LayerStyle())
    if let kind {
      if let index = layerStyleDraft?.style.effects.firstIndex(where: { $0.kind == kind }) {
        layerStyleDraft?.selected = index
      } else { addLayerEffect(kind) }
    }
    render()
  }
  func addLayerEffect(_ kind: LayerEffect.Kind) {
    guard var draft = layerStyleDraft, draft.style.effects.count < 32 else { return }
    var effect = LayerEffect(kind)
    if kind == .gradientOverlay { effect.gradient = GradientFill(gradient: .blackToWhite) }
    if kind == .patternOverlay {
      guard let pattern = document.patterns?.first else { return }
      effect.pattern = PatternFill(patternID: pattern.id)
    }
    draft.style.effects.append(effect); draft.selected = draft.style.effects.count - 1
    layerStyleDraft = draft; render()
  }
  func updateLayerEffect(_ index: Int, _ change: (inout LayerEffect) -> Void) {
    guard var draft = layerStyleDraft, draft.style.effects.indices.contains(index) else { return }
    change(&draft.style.effects[index])
    layerStyleDraft = draft; render()
  }
  func removeLayerEffect() {
    guard var draft = layerStyleDraft, draft.style.effects.indices.contains(draft.selected) else { return }
    draft.style.effects.remove(at: draft.selected)
    draft.selected = max(0, draft.selected - 1)
    layerStyleDraft = draft; render()
  }
  func cancelLayerStyle() { layerStyleDraft = nil; render() }
  func commitLayerStyle() {
    guard let draft = layerStyleDraft else { return }
    do {
      guard draft.original == document else { throw CraftError.invalid("The document changed. Cancel and reopen Layer Style.") }
      try draft.style.validate(in: document)
      layerStyleDraft = nil
      perform(.layerStyle([draft.id], draft.style))
    } catch { self.error = error.localizedDescription }
  }
  func copyLayerStyle() { if canCopyLayerStyle { Self.copiedLayerStyle = activeLayer?.style } }
  func pasteLayerStyle() {
    guard canPasteLayerStyle, let style = Self.copiedLayerStyle else { return }
    perform(.layerStyle(groupSelectionIDs, style))
  }
  func clearLayerStyle() { if canClearLayerStyle { perform(.layerStyle(groupSelectionIDs, nil)) } }
  func validateLayerStyleMenu(_ path: String) -> Bool {
    if path.hasSuffix("Copy Layer Style") { return canCopyLayerStyle }
    if path.hasSuffix("Paste Layer Style") { return canPasteLayerStyle }
    if path.hasSuffix("Clear Layer Style") { return canClearLayerStyle }
    if path.hasSuffix("Pattern Overlay…"), document.patterns?.isEmpty != false { return false }
    return canBeginLayerStyle
  }
}

struct LayerStyleSheet: View {
  @Bindable var store: EditorStore
  private var draft: LayerStyleDraft? { store.layerStyleDraft }
  private var selected: Int { draft?.selected ?? 0 }
  private var effect: LayerEffect? {
    guard let draft, draft.style.effects.indices.contains(selected) else { return nil }
    return draft.style.effects[selected]
  }
  private func style<T>(_ key: WritableKeyPath<LayerStyle, T>, _ fallback: T) -> Binding<T> {
    Binding(get: { draft?.style[keyPath: key] ?? fallback }, set: {
      store.layerStyleDraft?.style[keyPath: key] = $0; store.render()
    })
  }
  func value<T>(_ key: WritableKeyPath<LayerEffect, T>, _ fallback: T) -> Binding<T> {
    Binding(get: { effect?[keyPath: key] ?? fallback }, set: {
      guard effect != nil else { return }
      let index = selected, newValue = $0
      store.updateLayerEffect(index) { $0[keyPath: key] = newValue }
    })
  }
  private func numeric(_ label: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
    HStack {
      Text(label).frame(width: 115, alignment: .leading)
      Slider(value: binding, in: range).accessibilityLabel(label)
      TextField(label, value: binding, format: .number.precision(.fractionLength(0...1)))
        .frame(width: 65).textFieldStyle(.roundedBorder)
    }
  }
  private func scalar(_ binding: Binding<Float>) -> Binding<Double> {
    Binding(get: { Double(binding.wrappedValue) * 100 }, set: { binding.wrappedValue = Float($0 / 100) })
  }
  private func colour(_ binding: Binding<Pixel>) -> Binding<Color> {
    Binding(get: { let p = binding.wrappedValue; return Color(red: Double(p.r), green: Double(p.g), blue: Double(p.b)) }, set: {
      guard let c = NSColor($0).usingColorSpace(.sRGB) else { return }
      binding.wrappedValue = Pixel(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
    })
  }
  func gradientColor(_ end: Bool) -> Binding<Pixel> {
    Binding(get: {
      let colors = effect?.gradient?.gradient.colors ?? []
      return (end ? colors.last : colors.first)?.color.resolved(foreground: .black, background: .white) ?? .black
    }, set: { p in
      guard let count = effect?.gradient?.gradient.colors.count, count > 0 else { return }
      store.updateLayerEffect(selected) { $0.gradient?.gradient.colors[end ? count-1 : 0].color = .rgb(p) }
    })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Layer Style").font(.title2.bold())
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading) {
          Toggle("Enable Effects", isOn: style(\.enabled, true))
          List(selection: Binding(get: { Optional(selected) }, set: { if let i = $0 { store.layerStyleDraft?.selected = i } })) {
            ForEach(Array((draft?.style.effects ?? []).enumerated()), id: \.offset) { index, item in
              HStack {
                Toggle("", isOn: Binding(get: { draft?.style.effects.indices.contains(index) == true ? draft!.style.effects[index].enabled : false }, set: {
                  let enabled = $0; store.updateLayerEffect(index) { $0.enabled = enabled }
                })).labelsHidden().accessibilityLabel("Enable \(item.kind.title)")
                Text(item.kind.title)
              }.tag(index)
            }
          }.frame(width: 185, height: 270)
          HStack {
            Menu("Add Effect") {
              ForEach(LayerEffect.Kind.allCases, id: \.self) { kind in
                Button(kind.title) { store.addLayerEffect(kind) }
                  .disabled(kind == .patternOverlay && store.document.patterns?.isEmpty != false)
              }
            }.disabled((draft?.style.effects.count ?? 0) >= 32)
            Button("Remove") {
              guard effect != nil else { return }
              store.removeLayerEffect()
            }.disabled(effect == nil)
          }
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            numeric("Fill Opacity (%)", scalar(style(\.fillOpacity, 1)), 0...100)
            numeric("Effects Scale (%)", style(\.scale, 100), 1...1000)
            numeric("Shared Light Angle", style(\.lightAngle, 120), -180...180)
            numeric("Light Altitude", style(\.lightAltitude, 30), 0...90)
            Divider()
            if let effect {
              Text(effect.kind.title).font(.headline)
              Picker("Blend Mode", selection: value(\.blendMode, .normal)) {
                ForEach(BlendMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
              }
              numeric("Opacity (%)", scalar(value(\.opacity, 1)), 0...100)
              effectControls(effect)
            } else { Text("Choose Add Effect to style this layer.").foregroundStyle(.secondary) }
          }.padding(.trailing, 8)
        }.frame(width: 400, height: 330)
      }
      if let validationError { Text(validationError).foregroundStyle(.red).font(.caption) }
      Divider()
      HStack {
        Toggle("Preview", isOn: Binding(get: { draft?.preview ?? false }, set: { store.layerStyleDraft?.preview = $0; store.render() }))
        if store.rendering { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel") { store.cancelLayerStyle() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitLayerStyle() }.keyboardShortcut(.defaultAction).disabled(validationError != nil)
      }
    }.padding(20)
  }
  @ViewBuilder private func effectControls(_ effect: LayerEffect) -> some View {
    if ![.gradientOverlay, .patternOverlay, .bevelEmboss].contains(effect.kind) {
      ColorPicker("Color", selection: colour(value(\.color, .black)), supportsOpacity: false)
    }
    if [.stroke, .innerShadow, .innerGlow, .outerGlow, .dropShadow, .satin, .bevelEmboss].contains(effect.kind) {
      numeric("Size (pixels)", value(\.size, 5), 0...250)
    }
    if [.innerShadow, .dropShadow, .satin].contains(effect.kind) {
      numeric("Distance (pixels)", value(\.distance, 5), 0...1000)
    }
    if [.innerShadow, .dropShadow, .bevelEmboss, .satin].contains(effect.kind) {
      Toggle("Use Shared Light", isOn: value(\.useGlobalLight, true))
      if !effect.useGlobalLight { numeric("Angle", value(\.angle, 120), -180...180) }
    }
    if [.innerShadow, .innerGlow, .outerGlow, .dropShadow].contains(effect.kind) {
      numeric("Spread / Choke (%)", value(\.spread, 0), 0...100)
    }
    if effect.kind == .stroke {
      Picker("Position", selection: value(\.position, .outside)) {
        ForEach(LayerEffect.StrokePosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
      }
    }
    if effect.kind == .bevelEmboss {
      Text("Inner Bevel · Smooth").foregroundStyle(.secondary)
      numeric("Depth (%)", value(\.depth, 100), 1...1000)
      numeric("Soften", value(\.soften, 0), 0...16)
      ColorPicker("Highlight", selection: colour(value(\.highlightColor, .white)), supportsOpacity: false)
      numeric("Highlight (%)", scalar(value(\.highlightOpacity, 0.5)), 0...100)
      ColorPicker("Shadow", selection: colour(value(\.shadowColor, .black)), supportsOpacity: false)
      numeric("Shadow (%)", scalar(value(\.shadowOpacity, 0.5)), 0...100)
    }
    if effect.kind == .gradientOverlay {
      ColorPicker("Start Color", selection: colour(gradientColor(false)), supportsOpacity: false)
      ColorPicker("End Color", selection: colour(gradientColor(true)), supportsOpacity: false)
      numeric("Gradient Angle", Binding(get: { Double(effect.gradient?.placement.angle ?? 90) }, set: {
        let angle = Float($0); store.updateLayerEffect(selected) { $0.gradient?.placement.angle = angle }
      }), -180...180)
    }
    if effect.kind == .patternOverlay {
      Picker("Pattern", selection: Binding(get: { effect.pattern?.patternID ?? "" }, set: {
        let id = $0; store.updateLayerEffect(selected) { $0.pattern?.patternID = id }
      })) { ForEach(store.document.patterns ?? [], id: \.id) { Text($0.name).tag($0.id) } }
      numeric("Pattern Scale (%)", Binding(get: { Double(effect.pattern?.placement.scale ?? 1) * 100 }, set: {
        let scale = Float($0 / 100); store.updateLayerEffect(selected) { $0.pattern?.placement.scale = scale }
      }), 1...1000)
    }
  }
  private var validationError: String? {
    do { try draft?.style.validate(in: store.document); return nil } catch { return error.localizedDescription }
  }
}

@MainActor extension AppDelegate {
  static var layerStyleMenuPaths: [String] {
    (["Blending Options…"] + LayerEffect.Kind.allCases.map { $0.title + "…" }
      + ["Copy Layer Style", "Paste Layer Style", "Clear Layer Style"]).map { "Layer > Layer Style > " + $0 }
  }
  @objc func layerStyleMenu(_ sender: NSMenuItem) {
    switch sender.identifier?.rawValue.components(separatedBy: " > ").last {
    case "Copy Layer Style": store?.copyLayerStyle()
    case "Paste Layer Style": store?.pasteLayerStyle()
    case "Clear Layer Style": store?.clearLayerStyle()
    default:
      store?.beginLayerStyle(LayerEffect.Kind.allCases.first { $0.title + "…" == sender.title })
    }
  }
}
