import PhotoCraftCore
import SwiftUI

struct CloneSourcePanel: View {
  @Bindable var state: CloneSources
  var target: EditorStore? = nil
  var embedded = false
  var slot: CloneSlot { state.slot }
  func number(_ key: WritableKeyPath<CloneSlot, Double>, range: ClosedRange<Double>) -> Binding<
    Double
  > {
    Binding(
      get: { slot[keyPath: key] },
      set: { value in
        guard value.isFinite else { return }
        let value = min(range.upperBound, max(range.lowerBound, value))
        if state.linkedScale && (key == \.width || key == \.height) {
          let other: WritableKeyPath<CloneSlot, Double> = key == \.width ? \.height : \.width
          state.slots[state.active][keyPath: other] = min(
            1000, max(1, slot[keyPath: other] * value / slot[keyPath: key]))
        }
        state.slots[state.active][keyPath: key] = value
      })
  }
  func flag(_ key: WritableKeyPath<CloneSlot, Bool>) -> Binding<Bool> {
    Binding(get: { slot[keyPath: key] }, set: { state.slots[state.active][keyPath: key] = $0 })
  }
  func offset(_ horizontal: Bool) -> Binding<Double> {
    Binding(
      get: {
        guard let source = slot.source else { return 0 }
        let a = slot.anchor ?? source
        return horizontal ? source.x - a.x : source.y - a.y
      },
      set: { value in
        guard value.isFinite, abs(value) <= 1_000_000, let source = slot.source else { return }
        let anchor = slot.anchor ?? source
        state.slots[state.active].anchor = anchor
        state.slots[state.active].source =
          horizontal ? PathPoint(anchor.x + value, source.y) : PathPoint(source.x, anchor.y + value)
        state.slots[state.active].target = target ?? slot.target ?? slot.store
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !embedded { Text("Clone Source").font(.headline) }
      HStack {
        ForEach(0..<5, id: \.self) { index in
          Button {
            state.active = index
          } label: {
            VStack(spacing: 3) {
              Image(systemName: "seal")
              Text("\(index + 1)")
            }.frame(maxWidth: .infinity).frame(height: 32)
              .background(
                state.active == index ? StudioTheme.selected : StudioTheme.field,
                in: RoundedRectangle(cornerRadius: 3))
          }.buttonStyle(.plain)
            .help("Clone Source \(index + 1)")
            .accessibilityLabel("Clone Source \(index + 1)")
        }
      }
      Text(slot.store?.document.name ?? "Option-click an image to set this source")
        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
      HStack {
        Text("X:")
        TextField("X offset", value: offset(true), format: .number)
        Text("Y:")
        TextField("Y offset", value: offset(false), format: .number)
      }.disabled(slot.source == nil)
      HStack {
        Text("W:")
        TextField("Width percent", value: number(\.width, range: 1...1000), format: .number)
        Text("%")
        Toggle(isOn: $state.linkedScale) { Image(systemName: "link") }.toggleStyle(.button).help(
          "Link width and height")
        Text("H:")
        TextField("Height percent", value: number(\.height, range: 1...1000), format: .number)
        Text("%")
      }
      HStack {
        Text("Rotation:")
        TextField("Rotation degrees", value: number(\.rotation, range: -180...180), format: .number)
        Text("°")
        Button("Reset") {
          state.slots[state.active].width = 100
          state.slots[state.active].height = 100
          state.slots[state.active].rotation = 0
          state.slots[state.active].flipHorizontal = false
          state.slots[state.active].flipVertical = false
        }
      }
      HStack {
        Toggle("Flip horizontal", isOn: flag(\.flipHorizontal))
        Toggle("Flip vertical", isOn: flag(\.flipVertical))
      }
      Divider()
      Toggle("Show Overlay", isOn: $state.showOverlay)
      HStack {
        Text("Opacity")
        Slider(value: $state.overlayOpacity, in: 0...1)
        Text("\(Int(state.overlayOpacity * 100))%").monospacedDigit().frame(width: 36)
      }.disabled(!state.showOverlay)
      Picker("Overlay mode", selection: $state.overlayBlend) {
        ForEach(CloneOverlayBlend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.disabled(!state.showOverlay)
      HStack {
        Toggle("Clipped", isOn: $state.clippedOverlay)
        Toggle("Auto Hide", isOn: $state.autoHideOverlay)
        Toggle("Invert", isOn: $state.invertOverlay)
      }
      .disabled(!state.showOverlay)
    }.textFieldStyle(.roundedBorder).controlSize(.small).padding(embedded ? 10 : 16)
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
      .frame(width: embedded ? nil : 310)
  }
}

extension WorkspaceView {
  var retouchBrushControl: some View {
    @Bindable var state = store.retouchSettings
    return
      Button("Brush \(Int(store.retouchSettings.brush.size))") { brushPopover.toggle() }
      .popover(isPresented: $brushPopover) {
        VStack(alignment: .leading, spacing: 14) {
          Text(store.tool == .cloneStamp ? "Clone Stamp Brush" : store.tool.rawValue).font(
            .headline)
          numberField("Size", value: $state.brush.size, range: 1...2048, suffix: "px")
          Slider(value: $state.brush.size, in: 1...300)
          percentField("Hardness", value: $state.brush.hardness)
          Slider(value: $state.brush.hardness, in: 0...1)
          numberField(
            "Spacing",
            value: Binding(
              get: { store.retouchSettings.brush.spacing * 100 },
              set: { store.retouchSettings.brush.spacing = $0 / 100 }), range: 1...1000,
            suffix: "%")
          Toggle("Pressure controls size", isOn: $state.brush.pressureSize)
          Toggle("Pressure controls opacity", isOn: $state.brush.pressureOpacity)
        }.padding(16).frame(width: 290)
      }
  }
  var focusOptions: some View {
    @Bindable var state = store.retouchSettings
    return HStack(spacing: 12) {
      retouchBrushControl
      Picker("Mode", selection: $state.brush.mode) {
        ForEach(FocusBlendModes.supported, id: \.self) { Text($0.rawValue).tag($0) }
      }.frame(width: 150).controlSize(.small)
        .accessibilityIdentifier("retouch.focusMode")
      percentField("Strength:", value: $state.focus.strength)
      Toggle("Sample All Layers", isOn: $state.focus.sampleAllLayers)
        .disabled(store.editingMask).controlSize(.small)
      if store.tool == .sharpen {
        Toggle("Protect Detail", isOn: $state.focus.protectDetail).controlSize(.small)
      }
      if store.tool == .smudge {
        Toggle("Finger Painting", isOn: $state.focus.fingerPainting).controlSize(.small)
        Text("⌥ drag to toggle Finger Painting").foregroundStyle(.secondary)
      }
    }.disabled(store.cloneDraft != nil || store.geometryBusy)
  }
  var toningOptions: some View {
    @Bindable var state = store.retouchSettings
    return HStack(spacing: 12) {
      retouchBrushControl
      if store.tool == .sponge {
        Picker("Mode", selection: $state.toning.spongeMode) {
          ForEach(SpongeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.frame(width: 175).controlSize(.small)
        percentField("Flow:", value: $state.brush.flow)
        Toggle("Vibrance", isOn: $state.toning.vibrance).controlSize(.small)
      } else {
        Picker("Range", selection: $state.toning.range) {
          ForEach(RetouchToneRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.frame(width: 175).controlSize(.small)
        percentField("Exposure:", value: $state.toning.exposure)
        Toggle("Protect Tones", isOn: $state.toning.protectTones).controlSize(.small)
        Text("⌥ temporarily swaps Dodge / Burn").foregroundStyle(.secondary)
      }
    }.disabled(store.cloneDraft != nil || store.geometryBusy)
  }
  var spotHealingOptions: some View {
    @Bindable var state = store.retouchSettings
    return HStack(spacing: 12) {
      retouchBrushControl
      Picker("Mode", selection: $state.brush.mode) {
        ForEach(
          [BlendMode.normal, .multiply, .screen, .darken, .lighten, .color, .luminosity], id: \.self
        ) { Text($0.rawValue).tag($0) }
      }.frame(width: 145).controlSize(.small)
      Text("Type:").fixedSize()
      Picker("Type", selection: $state.spotType) {
        ForEach(SpotHealingType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).labelsHidden().frame(width: 350)
      Toggle(
        "Sample All Layers",
        isOn: Binding(
          get: { state.sampling == .all }, set: { state.sampling = $0 ? .all : .current })
      )
      .disabled(store.editingMask).controlSize(.small)
    }.disabled(store.cloneDraft != nil || store.geometryBusy)
  }
  var cloneOptions: some View {
    @Bindable var state = store.retouchSettings
    return HStack(spacing: 10) {
      retouchBrushControl
      Picker("Mode", selection: $state.brush.mode) {
        ForEach(
          store.tool == .healingBrush
            ? [.normal, .multiply, .screen, .darken, .lighten, .color, .luminosity]
            : BlendMode.allCases, id: \.self
        ) { Text($0.rawValue).tag($0) }
      }.frame(width: 140).controlSize(.small)
      percentField("Opacity:", value: $state.brush.opacity)
      percentField("Flow:", value: $state.brush.flow)
      Toggle("Aligned", isOn: $state.aligned).controlSize(.small)
      Picker("Sample", selection: $state.sampling) {
        ForEach(CloneSampling.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.frame(width: 190).controlSize(.small).disabled(store.editingMask)
      Toggle("Ignore Adjustments", isOn: $state.ignoreAdjustments).controlSize(.small)
        .disabled(store.retouchSettings.sampling == .current || store.editingMask)
      Button("Clone Source") { store.workspaceLibrary.selectPanel(.cloneSource, reveal: true) }
      Text("⌥ Click to sample").foregroundStyle(.secondary)
    }.disabled(store.cloneDraft != nil || store.geometryBusy)
  }
}
