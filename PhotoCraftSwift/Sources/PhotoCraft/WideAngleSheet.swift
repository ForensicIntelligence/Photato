import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct WideAngleSheet:View {
  @Bindable var store:EditorStore
  @State private var model:WideAngleWorkspace
  @State private var importing=false
  @State private var exporting=false
  @State private var exportFile:LUTDocument?
  init(store:EditorStore,model:WideAngleWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? WideAngleWorkspace()) }
  func number(_ key:WritableKeyPath<WideAngleSettings,Double>)->Binding<Double> { .init(get:{model.settings[keyPath:key]},set:{n in var s=model.settings;s[keyPath:key]=n;model.change(s)}) }
  func field(_ title:String,_ key:WritableKeyPath<WideAngleSettings,Double>,_ range:ClosedRange<Double>)->some View {
    VStack(spacing:4) { HStack { Text(title);Spacer();TextField(title,value:number(key),format:.number.precision(.fractionLength(0...2))).frame(width:70) };Slider(value:number(key),in:range,onEditingChanged:model.slider) }
  }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text("Adaptive Wide Angle").font(.headline);Spacer();if model.rendering { ProgressView().controlSize(.small) };Button("Load Settings…") { importing=true };Button("Save Settings…") { do { exportFile=LUTDocument(data:try JSONEncoder().encode(model.settings));exporting=true } catch { model.error=error.localizedDescription } } }
      HStack(alignment:.top,spacing:16) {
        VStack {
          Picker("Tool",selection:$model.tool) { ForEach(WideAngleWorkspace.Tool.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
          WideAnglePreview(model:model)
          HStack { Toggle("Show Constraints",isOn:$model.showConstraints);Toggle("Show Mesh",isOn:$model.showMesh);Spacer() }.controlSize(.small)
        }.frame(minWidth:510)
        ScrollView { VStack(alignment:.leading,spacing:14) {
          Picker("Correction",selection:Binding(get:{model.settings.model},set:{v in var s=model.settings;s.model=v;model.change(s)})) { ForEach(WideAngleSettings.Model.allCases,id:\.self) { Text($0.title).tag($0) } }
          if model.settings.model == .auto { Text("Resolved projection: \(model.resolvedModel.title)").font(.caption).foregroundStyle(.secondary) }
          field("Scale (%)",\.scale,5...400);field("Focal Length (mm)",\.focalLength,0...200);field("Crop Factor",\.cropFactor,0.1...10)
          Text("Zero focal length uses the projection default. Camera and lens metadata are not matched automatically.").font(.caption).foregroundStyle(.secondary)
          Picker("Interpolation",selection:Binding(get:{model.settings.interpolation},set:{v in var s=model.settings;s.interpolation=v;model.change(s)})) { ForEach(Resampling.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
          Divider()
          if model.tool == .polygon {
            Text("Click successive corners, then finish the polygon.").font(.caption)
            Toggle("Closed Polygon",isOn:$model.closePolygon)
            HStack { Button("Finish") { model.finishPolygon() }.disabled(model.polygon.count < (model.closePolygon ? 3:2));Button("Discard Points") { model.polygon=[];model.error=nil }.disabled(model.polygon.isEmpty) }
          } else { Text("Drag across a curved edge to straighten it. Hold Shift to constrain it horizontally or vertically. Drag a point or line to adjust.").font(.caption).foregroundStyle(.secondary) }
          if !model.settings.constraints.isEmpty {
            Picker("Constraint",selection:$model.selected) { ForEach(model.settings.constraints.indices,id:\.self) { Text("\($0+1): \(model.settings.constraints[$0].closed ? "Polygon":"Line")").tag($0) } }.onChange(of:model.selected) { _,_ in model.selectedSegment=0;model.selectedPoint=0 }
            if let c=model.constraint {
              Picker("Edge",selection:$model.selectedSegment) { ForEach(0..<c.segmentCount,id:\.self) { Text("\($0+1)").tag($0) } }
              Picker("Orientation",selection:Binding(get:{c.orientation(min(model.selectedSegment,c.segmentCount-1))},set:{model.orient($0)})) { ForEach(WideAngleSettings.Orientation.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
              if c.orientation(min(model.selectedSegment,c.segmentCount-1)) == .angle { HStack { Text("Angle (°)");TextField("Angle",value:Binding(get:{c.angle(min(model.selectedSegment,c.segmentCount-1))},set:{model.orient(.angle,angle:$0)}),format:.number) } }
              Button("Delete Constraint") { model.remove() }
            }
          } else { Text("Draw a constraint to begin correcting the image.").font(.caption) }
          if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.frame(width:280).padding(.trailing,5) }.frame(width:295)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview);Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(8,model.zoom*1.5) };Button("Fit") { model.zoom=1;model.pan = .zero }
        Button("Reset") { model.polygon=[];model.change(.init()) }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty && model.polygon.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter.wideAngle=model.settings;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(18).frame(width:940,height:720)
    .task { store.wideAngleWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else { return };await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close();if store.wideAngleWorkspace === model { store.wideAngleWorkspace=nil } }
    .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.data]) { result in
      do { let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } };let file=try FileHandle(forReadingFrom:url);defer { try? file.close() };let data=try file.read(upToCount:32769) ?? Data();guard data.count<=32768 else { throw CraftError.invalid("Wide Angle settings exceed 32 KiB.") };model.change(try WideAngleSettings.decodeJSON(data)) } catch { model.error=error.localizedDescription }
    }
    .fileExporter(isPresented:$exporting,document:exportFile,contentType:.json,defaultFilename:"Adaptive Wide Angle.photatowideangle") { if case .failure(let error)=$0 { model.error=error.localizedDescription } }
  }
}
