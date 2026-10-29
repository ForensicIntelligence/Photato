import AppKit
import PhotoCraftCore
import SwiftUI

struct ContentAwareSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: ContentAwareWorkspace
  private func setting<T>(_ key: WritableKeyPath<ContentAwareSettings,T>) -> Binding<T> {
    Binding(get:{ model.state.settings[keyPath:key] },set:{ var next = model.state; next.settings[keyPath:key] = $0; model.change(next) })
  }
  var body: some View {
    VStack(spacing:0) {
      HStack {
        Text("Content-Aware Fill").font(.headline)
        Picker("Tool",selection:$model.tool) { Text("Sampling Brush").tag(ContentAwareStroke.Target.sampling); Text("Selection").tag(ContentAwareStroke.Target.selection) }.frame(width:190)
        if model.tool == .selection { Picker("Shape",selection:$model.kind) { Text("Brush").tag(ContentAwareStroke.Kind.brush); Text("Lasso").tag(ContentAwareStroke.Kind.lasso) }.frame(width:115) }
        Picker("Mode",selection:$model.add) { Text("Add").tag(true); Text("Subtract").tag(false) }.frame(width:140)
        TextField("Size",value:$model.size,format:.number).frame(width:50).textFieldStyle(.roundedBorder).help("Brush diameter in pixels; Option temporarily reverses Add/Subtract")
        Toggle("Hand",isOn:$model.panTool).toggleStyle(.button)
        Spacer(); if model.loading || model.rendering || model.committing { ProgressView().controlSize(.small) }
      }.padding(12).disabled(model.committing)
      Divider()
      HStack(spacing:0) {
        VStack(spacing:4) { Text("Sampling Area").font(.caption); ContentAwareCanvas(model:model) }
        Divider()
        VStack(spacing:4) { Text("Preview").font(.caption); ContentAwareCanvas(model:model,preview:true) }
        Divider()
        ScrollView {
          VStack(alignment:.leading,spacing:14) {
            GroupBox("Sampling Area Overlay") {
              VStack(alignment:.leading,spacing:8) {
                Toggle("Show Sampling Area",isOn:$model.showSampling)
                HStack { Text("Opacity"); Slider(value:$model.overlayOpacity,in:0...1) }
                ColorPicker("Color",selection:Binding(get:{ Color(red:Double(model.overlayColor.r),green:Double(model.overlayColor.g),blue:Double(model.overlayColor.b)) },set:{ if let c = NSColor($0).usingColorSpace(.sRGB) { model.overlayColor = Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent)); model.refreshOverlay() } }),supportsOpacity:false)
                Picker("Indicates",selection:$model.excludedOverlay) { Text("Sampling Area").tag(false); Text("Excluded Area").tag(true) }
                Button("Reset Sampling Area") { model.resetSampling() }
              }.padding(5)
            }
            GroupBox("Sampling Area Options") {
              VStack(alignment:.leading,spacing:8) {
                Picker("Sampling",selection:setting(\.sampling)) { Text("Auto").tag(ContentAwareSettings.Sampling.auto); Text("Rectangular").tag(ContentAwareSettings.Sampling.rectangular); Text("Custom").tag(ContentAwareSettings.Sampling.custom) }.pickerStyle(.radioGroup)
                if model.state.settings.sampling == .rectangular { HStack { Text("Margin (px)"); TextField("Margin",value:setting(\.margin),format:.number).textFieldStyle(.roundedBorder) } }
                if model.state.settings.sampling == .custom {
                  Picker("Saved Sampling",selection:Binding(get:{ model.state.samplingID },set:{ var next = model.state; next.samplingID = $0; model.change(next) })) {
                    Text("Paint Custom Area").tag(UUID?.none)
                    ForEach(model.input?.original.alphaChannels ?? []) { Text($0.name).tag(Optional($0.id)) }
                  }
                }
                Toggle("Sample All Layers",isOn:setting(\.sampleAllLayers))
              }.padding(5)
            }
            GroupBox("Fill Settings") {
              VStack(alignment:.leading,spacing:8) {
                Picker("Color Adaptation",selection:setting(\.colorAdaptation)) {
                  Text("None").tag(ContentAwareSettings.ColorAdaptation.none); Text("Default").tag(ContentAwareSettings.ColorAdaptation.default)
                  Text("High").tag(ContentAwareSettings.ColorAdaptation.high); Text("Very High").tag(ContentAwareSettings.ColorAdaptation.veryHigh)
                }
                Picker("Rotation Adaptation",selection:setting(\.rotation)) { ForEach(ContentAwareSettings.Rotation.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Scale",isOn:setting(\.scale)); Toggle("Mirror",isOn:setting(\.mirror))
                Button("New Variation") { var next = model.state; next.settings.seed &+= 1; model.change(next) }
              }.padding(5)
            }
            GroupBox("Output Settings") {
              Picker("Output To",selection:Binding(get:{ model.state.output },set:{ var next = model.state; next.output = $0; model.change(next) })) { ForEach(ContentAwareOutput.allCases,id:\.self) { Text($0.title).tag($0) } }.padding(5)
            }
            Toggle("Show Original",isOn:$model.showOriginal)
          }.padding(10).disabled(!model.ready)
        }.frame(width:290)
      }.frame(minHeight:460)
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).padding(8) }
      Divider()
      HStack {
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty || !model.ready)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty || !model.ready)
        Button("Reset") { model.reset() }.disabled(!model.ready)
        Button("Fit") { model.zoom = 1; model.pan = .zero }
        Slider(value:$model.zoom,in:0.125...4).frame(width:120).accessibilityLabel("Zoom")
        Text("\(Int(model.zoom*100))%").monospacedDigit()
        Spacer()
        Button("Cancel") { store.cancelContentAwareFill() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitContentAwareFill() }.keyboardShortcut(.defaultAction).disabled(!model.canCommit)
      }.padding(12)
    }.frame(minWidth:1000,idealWidth:1180,minHeight:620,idealHeight:740)
      .onChange(of:model.showSampling) { _,_ in model.refreshOverlay() }
      .onChange(of:model.overlayOpacity) { _,_ in model.refreshOverlay() }
      .onChange(of:model.excludedOverlay) { _,_ in model.refreshOverlay() }
      .onChange(of:model.tool) { _,value in if value == .sampling { model.kind = .brush }; model.panTool = false }
  }
}
