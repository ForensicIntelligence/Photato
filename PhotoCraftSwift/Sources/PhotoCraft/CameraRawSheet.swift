import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct CameraRawSheet: View {
  @Bindable var store: EditorStore
  private var placement: RawPlacementWorkspace?
  @State private var model = CameraRawWorkspace()
  @State private var group = "Light"
  @State private var band = 0
  @State private var wheel = 0
  @State private var curveChannel = 0
  @State private var importing = false
  @State private var exporting = false
  @State private var exportFile: LUTDocument?
  private var groups: [String] { (model.sensorSettings == nil ? [] : ["Sensor"]) + ["Light","Color","Effects","Curve","Color Mixer","Color Grading","Detail"] }
  init(store: EditorStore,workspace: CameraRawWorkspace? = nil,placement: RawPlacementWorkspace? = nil) { self.store = store; self.placement = placement; _model = State(initialValue:workspace ?? CameraRawWorkspace()) }
  private func binding(_ key: String) -> Binding<Double> { Binding(get:{ Double(model.settings[key]) },set:{ var value = model.settings; value[key] = Float($0); model.change(value) }) }
  private func control(_ title: String,_ value: Binding<Double>,_ range: ClosedRange<Double>) -> some View {
    VStack(alignment:.leading,spacing:3) {
      HStack { Text(title); Spacer(); TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:64).textFieldStyle(.roundedBorder) }
      Slider(value:value,in:range,onEditingChanged:model.slider).accessibilityLabel(title)
    }.padding(.vertical,3)
  }
  var body: some View {
    VStack(spacing:0) {
      HStack { Text(model.sensorSettings == nil ? "Camera Raw Filter" : "Camera Raw — Source").font(.headline); Spacer(); if model.rendering { ProgressView().controlSize(.small) }; Button("Load Settings…") { importing = true }; Button("Save Settings…") { do { exportFile = LUTDocument(data:try model.sensorSettings.map { try JSONEncoder().encode($0) } ?? JSONEncoder().encode(model.settings)); exporting = true } catch { model.error = error.localizedDescription } } }.padding(12)
      Divider()
      HStack(spacing:0) {
        GeometryReader { geo in
          ScrollView([.horizontal,.vertical]) {
            if let image = model.preview ? model.image : model.originalImage {
              let fit = min(geo.size.width/CGFloat(image.width),geo.size.height/CGFloat(image.height))
              Image(decorative:image,scale:1).resizable().interpolation(.high)
                .frame(width:CGFloat(image.width)*fit*model.zoom,height:CGFloat(image.height)*fit*model.zoom)
                .frame(minWidth:geo.size.width,minHeight:geo.size.height)
            }
          }.background(Color(white:0.12))
        }
        Divider()
        VStack(spacing:10) {
          histogram.frame(height:90).background(Color(white:0.1)).clipShape(RoundedRectangle(cornerRadius:5))
          Picker("Adjustments",selection:$group) { ForEach(groups,id:\.self) { Text($0) } }.labelsHidden()
          ScrollView { controls.padding(.trailing,5) }
        }.padding(14).frame(width:310)
      }
      Divider()
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).padding(6) }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.zoom = max(0.25,model.zoom/1.25) }; Text("\(Int(model.zoom*100))% fit").monospacedDigit()
        Button("+") { model.zoom = min(8,model.zoom*1.25) }; Button("Fit") { model.zoom = 1 }
        Spacer()
        Button("Reset") { model.reset() }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty)
        Button("Cancel") { if let placement {placement.cancel()} else {model.close(); store.cancelFilter()} }.keyboardShortcut(.cancelAction)
        Button("OK") { guard model.ready else { return }; if let placement {placement.run();return}; store.filterDraft?.filter.cameraRaw = model.settings; store.filterDraft?.rawDevelopment = model.sensorSettings; model.close(); store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.padding(12)
    }.frame(width:min(1180,(NSScreen.main?.visibleFrame.width ?? 1280)-80),height:min(780,(NSScreen.main?.visibleFrame.height ?? 900)-100))
    .task { guard let draft = store.filterDraft else { return }; model.onChange = { store.filterDraft?.filter.cameraRaw = $0 }; model.onSensorChange = { store.filterDraft?.rawDevelopment = $0 }; if draft.rawDevelopment != nil { group = "Sensor" }; await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close() }
    .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.data]) { result in
      do { let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }; let data = try file.read(upToCount:32769) ?? Data(); if model.sensorSettings != nil { model.changeSensor(try RawDevelopment.decodeJSON(data)) } else { model.change(try CameraRawSettings.decodeJSON(data)) } } catch { model.error = error.localizedDescription }
    }
    .fileExporter(isPresented:$exporting,document:exportFile,contentType:.json,defaultFilename:"Camera Raw.photatoraw") { if case .failure(let error) = $0 { model.error = error.localizedDescription } }
  }
  private var histogram: some View {
    Canvas { context,size in
      for channel in 0..<3 {
        var path = Path(); path.move(to:CGPoint(x:0,y:size.height))
        for i in 0..<256 { path.addLine(to:CGPoint(x:Double(i)/255*size.width,y:(1-Double(model.histogram[channel][i]))*size.height)) }
        path.addLine(to:CGPoint(x:size.width,y:size.height)); path.closeSubpath()
        context.fill(path,with:.color([Color.red,.green,.blue][channel].opacity(0.45)))
      }
    }.accessibilityLabel("RGB histogram")
  }
  @ViewBuilder private var controls: some View {
    VStack(alignment:.leading,spacing:8) {
      ForEach(CameraRawSettings.controls.filter { $0.group == group }) { c in control(c.title,binding(c.key),Double(c.minimum)...Double(c.maximum)) }
      if group == "Sensor" { sensorControls }
      if group == "Effects" {
        Picker("Vignette style",selection:Binding(get:{ model.settings.vignetteStyle },set:{ var v = model.settings; v.vignetteStyle = $0; model.change(v) })) {
          Text("Highlight Priority").tag("highlightPriority"); Text("Color Priority").tag("colorPriority"); Text("Paint Overlay").tag("paintOverlay")
        }
      }
      if group == "Color Mixer" { mixer }
      if group == "Color Grading" { grading }
      if group == "Curve" { curves }
    }
  }
  private func sensorNumber(_ key: WritableKeyPath<RawDevelopment,Float>) -> Binding<Double> {
    Binding(get:{ Double((model.sensorSettings ?? .init())[keyPath:key]) },set:{ n in var v = model.sensorSettings ?? .init(); v[keyPath:key] = Float(n); model.changeSensor(v) })
  }
  @ViewBuilder private var sensorControls: some View {
    if let info = model.sensorInfo,let settings = model.sensorSettings {
      Text(info.model).font(.headline)
      Text("\(info.nativeWidth) × \(info.nativeHeight) sensor pixels").font(.caption).foregroundStyle(.secondary)
      Picker("Decoder",selection:Binding(get:{ settings.decoderVersion ?? info.decoderVersion },set:{ var v = settings; v.decoderVersion = $0; model.changeSensor(v) })) {
        ForEach(info.supportedDecoders,id:\.self) { Text($0).tag($0) }
      }
      control("Temperature (K)",Binding(get:{ Double(settings.temperature ?? info.temperature) },set:{ var v = settings; v.temperature = Float($0); model.changeSensor(v) }),2000...50000)
      control("Tint",Binding(get:{ Double(settings.tint ?? info.tint) },set:{ var v = settings; v.tint = Float($0); model.changeSensor(v) }),-150...150)
      Button("As Shot White Balance") { var v = settings; v.temperature = nil; v.tint = nil; model.changeSensor(v) }
      control("Sensor exposure",sensorNumber(\.exposure),-5...5)
      control("Tone boost",sensorNumber(\.boost),0...1)
      control("Shadow boost",sensorNumber(\.shadowBoost),0...2)
      control("Extended range",sensorNumber(\.extendedRange),0...2)
      Toggle("Lens correction",isOn:Binding(get:{ settings.lensCorrection ?? info.lensCorrectionEnabled },set:{ var v = settings; v.lensCorrection = $0; model.changeSensor(v) })).disabled(!info.lensCorrectionSupported)
      Toggle("Highlight recovery",isOn:Binding(get:{ settings.highlightRecovery ?? info.highlightRecoveryEnabled },set:{ var v = settings; v.highlightRecovery = $0; model.changeSensor(v) })).disabled(!info.highlightRecoverySupported)
      Text("Original RAW data is retained. Changes redevelop every shared instance; use New Smart Object via Copy for an independent version.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private var mixer: some View {
    VStack {
      Picker("Color",selection:$band) { ForEach(Array(["Reds","Oranges","Yellows","Greens","Aquas","Blues","Purples","Magentas"].enumerated()),id:\.offset) { Text($0.element).tag($0.offset) } }
      ForEach(0..<3,id:\.self) { index in
        control(["Hue","Saturation","Luminance"][index],Binding(get:{ Double([model.settings.hslHue,model.settings.hslSat,model.settings.hslLum][index][band]) },set:{ n in
          var v = model.settings
          switch index { case 0: v.hslHue[band] = Float(n); case 1: v.hslSat[band] = Float(n); default: v.hslLum[band] = Float(n) }; model.change(v)
        }),-100...100)
      }
    }
  }
  private var grading: some View {
    VStack {
      Picker("Tone",selection:$wheel) { ForEach(Array(["Shadows","Midtones","Highlights","Global"].enumerated()),id:\.offset) { Text($0.element).tag($0.offset) } }
      ForEach(0..<3,id:\.self) { index in
        control(["Hue","Saturation","Luminance"][index],Binding(get:{ let w = [model.settings.gradeShadows,model.settings.gradeMidtones,model.settings.gradeHighlights,model.settings.gradeGlobal][wheel]; return Double([w.hue,w.sat,w.lum][index]) },set:{ n in
          var v = model.settings; var w = [v.gradeShadows,v.gradeMidtones,v.gradeHighlights,v.gradeGlobal][wheel]
          switch index { case 0: w.hue = Float(n); case 1: w.sat = Float(n); default: w.lum = Float(n) }
          switch wheel { case 0: v.gradeShadows = w; case 1: v.gradeMidtones = w; case 2: v.gradeHighlights = w; default: v.gradeGlobal = w }; model.change(v)
        }), index == 0 ? 0...360 : index == 1 ? 0...100 : -100...100)
      }
    }
  }
  private var curves: some View {
    VStack {
      Picker("Point curve",selection:$curveChannel) { ForEach(Array(["RGB","Red","Green","Blue"].enumerated()),id:\.offset) { Text($0.element).tag($0.offset) } }
      CameraRawCurve(points:Binding(get:{ [model.settings.pointCurve,model.settings.pointCurveRed,model.settings.pointCurveGreen,model.settings.pointCurveBlue][curveChannel] },set:{ points in
        var v = model.settings
        switch curveChannel { case 0: v.pointCurve = points; case 1: v.pointCurveRed = points; case 2: v.pointCurveGreen = points; default: v.pointCurveBlue = points }; model.change(v)
      }),editing:model.slider).frame(height:220)
      Text("Drag a point, or click the curve area to add one.").font(.caption).foregroundStyle(.secondary)
      Button("Reset point curve") { var v = model.settings; switch curveChannel { case 0: v.pointCurve = []; case 1: v.pointCurveRed = []; case 2: v.pointCurveGreen = []; default: v.pointCurveBlue = [] }; model.change(v) }
    }
  }
}

private struct CameraRawCurve: View {
  @Binding var points: [[Float]]
  var editing: (Bool) -> Void
  @State private var selected: Int?
  private var display: [[Float]] { points.isEmpty ? [[0,0],[255,255]] : points }
  var body: some View {
    GeometryReader { geo in
      Canvas { context,size in
        var grid = Path()
        for i in 0...4 { let t = Double(i)/4; grid.move(to:CGPoint(x:t*size.width,y:0)); grid.addLine(to:CGPoint(x:t*size.width,y:size.height)); grid.move(to:CGPoint(x:0,y:t*size.height)); grid.addLine(to:CGPoint(x:size.width,y:t*size.height)) }
        context.stroke(grid,with:.color(.gray.opacity(0.4)),lineWidth:1)
        var line = Path()
        for (i,p) in display.enumerated() { let q = CGPoint(x:Double(p[0])/255*size.width,y:(1-Double(p[1])/255)*size.height); if i == 0 { line.move(to:q) } else { line.addLine(to:q) }; context.fill(Path(ellipseIn:CGRect(x:q.x-4,y:q.y-4,width:8,height:8)),with:.color(.white)) }
        context.stroke(line,with:.color(.white),lineWidth:1.5)
      }.background(Color(white:0.15)).gesture(DragGesture(minimumDistance:0).onChanged { event in
        var values = display
        let x = Float(min(255,max(0,event.location.x/geo.size.width*255))), y = Float(min(255,max(0,(1-event.location.y/geo.size.height)*255)))
        if selected == nil {
          editing(true)
          let nearby = values.indices.min { abs(values[$0][0]-x) < abs(values[$1][0]-x) }!
          if abs(values[nearby][0]-x) < 12 || values.count >= 16 { selected = nearby }
          else { let index = values.firstIndex { $0[0] > x } ?? values.count; values.insert([x,y],at:index); selected = index }
        }
        if let i = selected { let lower: Float = i == 0 ? 0 : values[i-1][0]+1, upper: Float = i == values.count-1 ? 255 : values[i+1][0]-1; values[i] = [min(upper,max(lower,x)),y]; points = values }
      }.onEnded { _ in selected = nil; editing(false) })
    }.accessibilityLabel("Point curve editor")
  }
}
