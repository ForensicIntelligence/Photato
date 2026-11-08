import AppKit
import SwiftUI
import PhotoCraftCore

@MainActor struct EraserOptionsView: View {
  @Bindable var store: EditorStore
  @State private var showTip = false
  func percent(_ title: String, get: @escaping () -> Double, set: @escaping (Double) -> Void) -> some View {
    HStack(spacing: 4) {
      Text(title)
      TextField(title, value: Binding(get: { get()*100 }, set: { if $0.isFinite { set(min(100,max(0,$0))/100) } }), format: .number.precision(.fractionLength(0...1)))
        .frame(width: 44).accessibilityLabel(title)
      Text("%")
    }
  }
  var body: some View {
    HStack(spacing: 8) {
      if store.eraserMode != .block {
        Button { showTip.toggle() } label: { Label("\(Int(store.brush.size))",systemImage:store.eraserMode == .pencil ? "pencil.tip":"circle.fill") }
          .help("Eraser size and hardness")
          .popover(isPresented:$showTip) {
            VStack(alignment:.leading) {
              HStack { Text("Size"); TextField("Size",value:Binding(get:{store.brush.size},set:{if $0.isFinite{store.brush.size=min(2048,max(0.5,$0))}}),format:.number).frame(width:70);Text("px") }
              Slider(value:$store.brush.size,in:0.5...2048)
              percent("Hardness",get:{Double(store.brush.hardness)},set:{store.brush.hardness=Float($0)}).disabled(store.eraserMode != .brush)
            }.padding().frame(width:230)
          }
      } else { Text("16 px").help("Block size follows the view zoom; it ignores the brush diameter.") }
      Picker("Mode:",selection:$store.eraserMode) { ForEach(EraserMode.allCases,id:\.self) { Text($0.title).tag($0) } }
        .frame(width:140).accessibilityIdentifier("eraser.mode")
      percent("Opacity:",get:{Double(store.brush.opacity)},set:{store.brush.opacity=Float($0)}).disabled(store.eraserMode == .block)
      percent("Flow:",get:{store.brushOptions.flow},set:{store.brushOptions.flow=$0}).disabled(store.eraserMode != .brush)
      percent("Smoothing:",get:{store.brushOptions.smoothing.amount},set:{store.brushOptions.smoothing.amount=$0})
      if store.eraserMode == .brush { Toggle("Airbrush",isOn:$store.brushOptions.buildUp) }
      Toggle("Erase to History",isOn:.constant(false)).disabled(true).help("Requires a history source; not available yet.")
      Button("Brush Settings") { NSApp.sendAction(#selector(AppDelegate.showBrushSettings),to:nil,from:nil) }.disabled(store.eraserMode == .block)
    }.controlSize(.small).toggleStyle(.checkbox).disabled(store.geometryBusy || store.hasToneDraft)
  }
}
