import AppKit
import PhotoCraftCore
import SwiftUI

struct ClassicAdjustmentDraft: Identifiable, Sendable {
  let id: UUID
  var adjustment: ClassicAdjustment
  var preview = true
}
struct ClassicAdjustmentControls: View {
  @Binding var adjustment: ClassicAdjustment
  var coalesce: (Bool) -> Void = { _ in }
  @State private var channel = 0
  @State private var range = 0
  private func exposureNumber(_ title: String, _ key: WritableKeyPath<ExposureAdjustment, Float>, _ limits: ClosedRange<Double>, digits: Int) -> some View {
    let value = Binding<Double>(get: { Double((adjustment.exposureSettings ?? .init())[keyPath:key]) }, set: {
      guard $0.isFinite else { return }
      var settings = adjustment.exposureSettings ?? .init()
      settings[keyPath:key] = Float(min(limits.upperBound,max(limits.lowerBound,$0)))
      adjustment.exposureSettings = settings
    })
    return VStack(spacing:3) {
      HStack { Text(title); Spacer(); TextField(title,value:value,format:.number.precision(.fractionLength(digits)))
        .textFieldStyle(.roundedBorder).monospacedDigit().frame(width:80) }
      Slider(value:value,in:limits,onEditingChanged:coalesce).accessibilityLabel(title)
    }
  }
  private func number(_ title: String, _ binding: Binding<Int>, _ limits: ClosedRange<Double>) -> some View {
    let value = Binding<Double>(get: { Double(binding.wrappedValue) }, set: {
      if $0.isFinite { binding.wrappedValue = Int(min(limits.upperBound,max(limits.lowerBound,$0)).rounded()) }
    })
    return VStack(spacing: 3) {
      HStack { Text(title); Spacer(); TextField(title, value: value, format: .number.precision(.fractionLength(0)))
          .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 60) }
      Slider(value: value, in: limits, step: 1, onEditingChanged: coalesce).accessibilityLabel(title)
    }
  }
  private func color(_ title: String, _ pixel: Binding<Pixel>) -> some View {
    ColorPicker(title, selection: Binding(get: {
      let c = pixel.wrappedValue; return Color(.sRGB,red:Double(c.r),green:Double(c.g),blue:Double(c.b))
    }, set: {
      guard let c = NSColor($0).usingColorSpace(.sRGB) else { return }
      pixel.wrappedValue = Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent))
    }), supportsOpacity: false)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch adjustment.kind {
      case .exposure:
        exposureNumber("Exposure", \.exposure, -20...20, digits:2)
        exposureNumber("Offset", \.offset, -0.5...0.5, digits:4)
        exposureNumber("Gamma Correction", \.gammaCorrection, 0.01...9.99, digits:2)
      case .vibrance:
        number("Vibrance", $adjustment.vibrance, -100...100)
        number("Saturation", $adjustment.saturation, -100...100)
      case .blackWhite:
        ForEach(0..<6, id: \.self) { i in number(ClassicAdjustment.rangeNames[i], Binding(get: { adjustment.weights[i] }, set: { adjustment.weights[i] = $0 }), -200...300) }
        Toggle("Tint", isOn: Binding(get: { adjustment.tint != nil }, set: { adjustment.tint = $0 ? ClassicAdjustment.defaultTint : nil }))
        if adjustment.tint != nil { color("Tint Color", Binding(get: { adjustment.tint ?? ClassicAdjustment.defaultTint }, set: { adjustment.tint = $0 })) }
      case .photoFilter:
        color("Color", $adjustment.color)
        HStack {
          Button("Warming") { adjustment.color = ClassicAdjustment(.photoFilter).color }
          Button("Cooling") { adjustment.color = Pixel(0,0.71,0.92) }
        }
        number("Density (%)", $adjustment.density, 0...100)
        Toggle("Preserve Luminosity", isOn: $adjustment.preserveLuminosity)
      case .channelMixer:
        Toggle("Monochrome", isOn: $adjustment.monochrome)
        if !adjustment.monochrome {
          Picker("Output Channel", selection: $channel) { Text("Red").tag(0); Text("Green").tag(1); Text("Blue").tag(2) }
        } else { Text("Output Channel: Gray").foregroundStyle(.secondary) }
        ForEach(0..<4, id: \.self) { i in
          number(["Red (%)", "Green (%)", "Blue (%)", "Constant (%)"][i], Binding(get: { adjustment.matrix[adjustment.monochrome ? 0 : channel][i] }, set: { adjustment.matrix[adjustment.monochrome ? 0 : channel][i] = $0 }), -200...200)
        }
        Text("Total: \(adjustment.matrix[adjustment.monochrome ? 0 : channel].prefix(3).reduce(0,+))%")
          .foregroundStyle(.secondary)
      case .selectiveColor:
        Picker("Colors", selection: $range) { ForEach(0..<9,id: \.self) { Text(ClassicAdjustment.rangeNames[$0]).tag($0) } }
        ForEach(0..<4,id: \.self) { i in
          number(["Cyan (%)", "Magenta (%)", "Yellow (%)", "Black (%)"][i], Binding(get: { adjustment.adjustments[range][i] }, set: { adjustment.adjustments[range][i] = $0 }), -100...100)
        }
        Picker("Method", selection: $adjustment.relative) { Text("Relative").tag(true); Text("Absolute").tag(false) }.pickerStyle(.segmented)
      }
      Button("Reset") { adjustment = .init(adjustment.kind) }.buttonStyle(.bordered)
    }
  }
}
struct ClassicAdjustmentEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  private var value: ClassicAdjustment {
    if pixelLayer, let draft = store.classicAdjustmentDraft { return draft.adjustment }
    if case .adjustment(.classic(let value)) = store.document.layers.first(where: { $0.id == layerID })?.content { return value }
    return .init(.vibrance)
  }
  var body: some View {
    ClassicAdjustmentControls(adjustment: Binding(get: { value }, set: { value in
      if pixelLayer { store.classicAdjustmentDraft?.adjustment = value; store.render() }
      else { store.setClassicAdjustment(layerID, value) }
    }), coalesce: { if !pixelLayer { store.coalesce($0) } })
  }
}
struct ClassicAdjustmentSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading,spacing:18) {
      if let draft = store.classicAdjustmentDraft {
        Text(draft.adjustment.kind.title).font(.title2.bold())
        ClassicAdjustmentEditor(store:store,layerID:draft.id,pixelLayer:true)
      }
      Divider()
      HStack {
        Toggle("Preview",isOn:Binding(get: { store.classicAdjustmentDraft?.preview ?? false },set: { store.classicAdjustmentDraft?.preview = $0; store.render() }))
        Spacer()
        Button("Cancel") { store.cancelClassicAdjustment() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitClassicAdjustment() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width:380)
  }
}
extension EditorStore {
  func beginClassicAdjustment(_ kind: ClassicAdjustment.Kind) {
    guard canBeginLevels, let layer = activeLayer else { return }
    classicAdjustmentDraft = .init(id:layer.id,adjustment:.init(kind))
    render()
  }
  func cancelClassicAdjustment() { classicAdjustmentDraft = nil; render() }
  func commitClassicAdjustment() {
    guard let draft = classicAdjustmentDraft else { return }
    classicAdjustmentDraft = nil
    performGeometry(.applyAdjustment(draft.id,.classic(draft.adjustment)))
  }
  func addClassicAdjustment(_ kind: ClassicAdjustment.Kind) {
    guard !geometryBusy, transformDraft == nil, !hasToneDraft else { return }
    do { perform(.addLayer(try ClassicAdjustment(kind).layer(in:document))); propertiesTab = .properties }
    catch { self.error = error.localizedDescription }
  }
  func setClassicAdjustment(_ id: UUID, _ value: ClassicAdjustment) {
    guard case .adjustment(.classic(let old)) = document.layers.first(where: { $0.id == id })?.content, old.kind == value.kind else { return }
    perform(.replaceContent(id,.adjustment(.classic(value))))
  }
}
extension AppDelegate {
  @objc func exposureAdjustment() { store?.beginClassicAdjustment(.exposure) }
  @objc func newExposureAdjustment() { store?.addClassicAdjustment(.exposure) }
  @objc func vibrance() { store?.beginClassicAdjustment(.vibrance) }
  @objc func blackWhite() { store?.beginClassicAdjustment(.blackWhite) }
  @objc func photoFilter() { store?.beginClassicAdjustment(.photoFilter) }
  @objc func channelMixer() { store?.beginClassicAdjustment(.channelMixer) }
  @objc func selectiveColor() { store?.beginClassicAdjustment(.selectiveColor) }
  @objc func newBlackWhite() { store?.addClassicAdjustment(.blackWhite) }
  @objc func newPhotoFilter() { store?.addClassicAdjustment(.photoFilter) }
  @objc func newChannelMixer() { store?.addClassicAdjustment(.channelMixer) }
  @objc func newSelectiveColor() { store?.addClassicAdjustment(.selectiveColor) }
}
