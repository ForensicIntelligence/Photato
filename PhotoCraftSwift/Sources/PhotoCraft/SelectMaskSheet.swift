import PhotoCraftCore
import SwiftUI

struct SelectMaskSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: SelectMaskWorkspace
  private func number(_ title: String,_ key: WritableKeyPath<SelectionRefinement,Double>,_ range: ClosedRange<Double>) -> some View {
    VStack(alignment:.leading,spacing:4) {
      HStack {
        Text(title); Spacer()
        TextField(title,value:Binding(get:{ model.state.settings[keyPath:key] },set:{ model.update(key,$0) }),format:.number.precision(.fractionLength(0...1)))
          .textFieldStyle(.roundedBorder).frame(width:65)
      }
      Slider(value:Binding(get:{ model.state.settings[keyPath:key] },set:{ model.update(key,$0) }),in:range,onEditingChanged:model.slider)
        .accessibilityLabel(title)
    }
  }
  var body: some View {
    VStack(spacing:0) {
      HStack {
        Text(model.title).font(.headline)
        Divider().frame(height:20)
        Picker("Tool",selection:$model.tool) {
          Text("Brush").tag(SelectionRefinementStroke.Tool.add)
          Text("Subtract").tag(SelectionRefinementStroke.Tool.subtract)
          if !model.isFocus {
          Text("Refine Edge").tag(SelectionRefinementStroke.Tool.refine)
          Text("Erase Refinement").tag(SelectionRefinementStroke.Tool.eraseRefinement)
          Text("Lasso").tag(SelectionRefinementStroke.Tool.lassoAdd)
          Text("Subtract Lasso").tag(SelectionRefinementStroke.Tool.lassoSubtract)
          }
        }.frame(width:230).onChange(of:model.tool) { _,_ in model.panTool = false }
        Text("Size")
        TextField("Brush Size",value:$model.size,format:.number).frame(width:52).textFieldStyle(.roundedBorder)
        if !model.isFocus{Button("Select Subject") { model.detect(using:store.foregroundDetector) }.disabled(!model.ready)}
        Spacer()
        if model.loading || model.rendering || model.detecting || model.committing { ProgressView().controlSize(.small) }
      }.padding(12)
      Divider()
      HStack(spacing:0) {
        SelectMaskCanvas(model:model).frame(minWidth:420,minHeight:460)
        Divider()
        ScrollView {
          VStack(alignment:.leading,spacing:16) {
            GroupBox("View Mode") {
              VStack(alignment:.leading,spacing:10) {
                Picker("View",selection:$model.view) { ForEach(SelectMaskView.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                  .onChange(of:model.view) { _,_ in model.refresh() }
                if model.isFocus{Toggle("Preview",isOn:Binding(get:{!model.showOriginal},set:{model.showOriginal = !$0;model.refresh()}))}
                else{Toggle("Show Original",isOn:$model.showOriginal).onChange(of:model.showOriginal) { _,_ in model.refresh() }}
                HStack { Text("Opacity"); Slider(value:$model.opacity,in:0...1).onChange(of:model.opacity) { _,_ in model.refresh() } }
              }.padding(5)
            }
            if model.isFocus{FocusAreaControls(model:model)}else{
            GroupBox("Edge Detection") {
              VStack(spacing:10) {
                number("Radius (px)",\.radius,0...250)
                Toggle("Smart Radius",isOn:Binding(get:{ model.state.settings.smartRadius },set:{ var next = model.state; next.settings.smartRadius = $0; model.change(next) }))
              }.padding(5)
            }
            GroupBox("Global Refinements") {
              VStack(spacing:12) {
                number("Smooth",\.smooth,0...100)
                number("Feather (px)",\.feather,0...1000)
                number("Contrast (%)",\.contrast,0...100)
                number("Shift Edge (%)",\.shiftEdge,-100...100)
              }.padding(5)
            }
            }
            GroupBox("Output Settings") {
              VStack(alignment:.leading,spacing:10) {
                if !model.isFocus{
                Toggle("Decontaminate Colors",isOn:Binding(get:{ model.state.settings.decontaminate },set:{ var next = model.state; next.settings.decontaminate = $0; model.change(next) }))
                if model.state.settings.decontaminate { number("Amount (%)",\.amount,0...100) }
                }
                Picker("Output To",selection:Binding(get:{ model.state.output },set:{ var next = model.state; next.output = $0; model.change(next) })) {
                  ForEach(SelectionRefinementOutput.allCases,id:\.self) { output in Text(output.title).tag(output).disabled(output.createsDocument && store.documentController == nil) }
                }
                if model.effectiveOutput != model.state.output { Text("Decontamination creates a new layer with a mask.").font(.caption).foregroundStyle(.secondary) }
              }.padding(5)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
          }.padding(12)
        }.frame(width:292).disabled(!model.ready)
      }
      Divider()
      HStack {
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty || !model.ready)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty || !model.ready)
        Button("Reset") { model.reset() }.disabled(!model.ready)
        Button("Fit") { model.zoom = 1; model.pan = .zero }
        Text("⌥ Subtract · Space Pan · [ ] Brush Size").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { store.cancelSelectMask() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitSelectMask() }.keyboardShortcut(.defaultAction).disabled(!model.ready || model.error != nil || (model.isFocus && !model.canCommit))
      }.padding(12)
    }.frame(width:1040,height:740).background(Color(nsColor:.windowBackgroundColor)).onDisappear { model.close() }
  }
}
