import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct ShadowHighlightsSheet:View {
  @Bindable var store:EditorStore
  @State private var model:ClassicToneWorkspace
  init(store:EditorStore) {
    self.store=store
    let draft=store.filterDraft
    _model=State(initialValue:ClassicToneWorkspace(document:store.document,request:.init(draft?.filter.tone ?? .init(.shadowsHighlights),layerID:draft?.id),filterDraft:draft))
  }
  var body:some View {
    ClassicToneSheet(store:store,model:model)
      .task {store.shadowWorkspace=model;if model.image==nil,!model.rendering{model.refresh()}}
  }
}

struct ClassicToneSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:ClassicToneWorkspace
  var kind:ClassicToneSettings.Kind {model.request.settings.kind}
  var body:some View {
    VStack(spacing:12) {
      HStack {Text(kind.title).font(.headline);Spacer();if model.rendering || model.committing || model.sourceBusy {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView {VStack(alignment:.leading,spacing:12) {
          controls
          Divider()
          HStack {
            Button("Reset"){model.update{$0.settings = .init(kind)}}
            Button("Load…"){loadPreset()}
            Button("Save…"){savePreset()}
          }
          Text("Photato JSON presets").font(.caption).foregroundStyle(.secondary)
        }.padding(.trailing,6)}.frame(width:295).disabled(model.committing)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−"){model.fit=false;model.zoom=max(0.125,model.zoom/1.5)}
        Button("+"){model.fit=false;model.zoom=min(8,model.zoom*1.5)}
        Button("100%"){model.fit=false;model.zoom=1};Button("Fit"){model.fit=true}
        Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty || model.committing).keyboardShortcut("z",modifiers:.command)
        Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty || model.committing).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel"){cancel()}.keyboardShortcut(.cancelAction)
        Button("OK"){commit()}.disabled(!model.ready).keyboardShortcut(.defaultAction)
      }.controlSize(.small)
      if let error=model.error {Text(error).foregroundStyle(.red).font(.caption).fixedSize(horizontal:false,vertical:true)}
    }.padding(16).frame(width:900,height:680)
    .onDisappear {
      model.close()
      if store.classicToneWorkspace === model {store.classicToneWorkspace=nil}
      if store.shadowWorkspace === model {store.shadowWorkspace=nil}
    }
  }
  func cancel() {if model.filterDraft != nil {store.cancelFilter()}else{store.cancelClassicTone()}}
  func commit() {
    model.endGesture()
    if model.filterDraft != nil {store.filterDraft?.filter.tone=model.request.settings;store.commitFilter()}
    else {store.commitClassicTone()}
  }
  var preview:some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? (model.maskPreview ? model.maskImage:model.image):model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        Image(decorative:image,scale:1).resizable().interpolation(.none)
          .frame(width:Double(image.width)*scale,height:Double(image.height)*scale)
          .overlay {
            if kind == .replaceColor {
              GeometryReader {area in Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onEnded {value in
                model.sample(.init(value.location.x/area.size.width,value.location.y/area.size.height))
              })}.disabled(model.committing)
            }
          }.padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).clipped().accessibilityLabel("\(kind.title) preview")}
  }
  func choice<T>(_ key:WritableKeyPath<ClassicToneSettings,T>)->Binding<T> {
    Binding(get:{model.request.settings[keyPath:key]},set:{value in model.update{$0.settings[keyPath:key]=value}})
  }
  func number(_ title:String,_ key:WritableKeyPath<ClassicToneSettings,Double>,_ range:ClosedRange<Double>,step:Double=1)->some View {
    VStack(spacing:4) {
      HStack {Text(title);Spacer();TextField(title,value:choice(key),format:.number.precision(.fractionLength(0...2))).frame(width:70).textFieldStyle(.roundedBorder)}
      Slider(value:choice(key),in:range,step:step,onEditingChanged:{editing in if editing{model.beginGesture()}else{model.endGesture()}}).accessibilityLabel(title)
    }
  }
  @ViewBuilder var controls:some View {
    switch kind {
    case .shadowsHighlights:shadows
    case .hdrToning:hdr
    case .matchColor:match
    case .replaceColor:replace
    case .equalize:
      Picker("Equalize",selection:choice(\.equalizeEntireImage)) {
        Text("Equalize selected area only").tag(false)
        Text("Equalize entire image based on selected area").tag(true)
      }.pickerStyle(.radioGroup)
    }
  }
  var shadows:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Shadows").font(.headline)
      number("Amount (%)",\.shadowAmount,0...100)
      if model.showMore {number("Tone (%)",\.shadowTone,0...100);number("Radius (pixels)",\.shadowRadius,0...2500)}
      Divider();Text("Highlights").font(.headline)
      number("Amount (%)",\.highlightAmount,0...100)
      if model.showMore {number("Tone (%)",\.highlightTone,0...100);number("Radius (pixels)",\.highlightRadius,0...2500)}
      Toggle("Show More Options",isOn:$model.showMore)
      if model.showMore {
        Divider();Text("Adjustments").font(.headline)
        number("Color Correction",\.colorCorrection,-100...100)
        number("Midtone Contrast",\.midtone,-100...100)
        number("Black Clip (%)",\.blackClip,0...50,step:0.01)
        number("White Clip (%)",\.whiteClip,0...50,step:0.01)
      }
    }
  }
  var hdr:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Applying HDR Toning combines visible layers into one background. Undo restores the layers.").font(.caption).foregroundStyle(.secondary)
      Picker("Method",selection:choice(\.method)) {ForEach(HDRMergeSettings.Method.allCases,id:\.self){Text($0.title).tag($0)}}
      if model.request.settings.method == .localAdaptation {
        number("Radius",\.radius,1...500)
        number("Strength",\.strength,0.1...4,step:0.01)
      }
      if model.request.settings.method == .localAdaptation || model.request.settings.method == .exposureGamma {
        number("Gamma",\.gamma,0.1...2,step:0.01)
        number("Exposure",\.exposure,-5...5,step:0.01)
      }
      if model.request.settings.method == .localAdaptation {
        number("Detail",\.detail,-100...300)
        number("Shadow",\.shadow,-100...100)
        number("Highlight",\.highlight,-100...100)
        number("Vibrance",\.vibrance,-100...100)
        number("Saturation",\.hdrSaturation,-100...100)
        Text("Toning Curve").font(.headline)
        ClassicToneCurve(model:model).frame(height:190)
        Button("Reset Curve"){model.update{$0.settings.curve=[]}}
      }
    }
  }
  var match:some View {
    VStack(alignment:.leading,spacing:12) {
      Picker("Source",selection:Binding(get:{model.sourceDocumentID},set:{value in model.sourceDocumentID=value;model.sourceLayerID=nil;model.calculateSource()})) {
        Text("None").tag(UUID?.none)
        ForEach(model.sources,id:\.id){Text($0.name).tag(Optional($0.id))}
      }
      if let source=model.selectedSource {
        Picker("Layer",selection:Binding(get:{model.sourceLayerID},set:{model.sourceLayerID=$0;model.calculateSource()})) {
          Text("Merged").tag(UUID?.none)
          ForEach(source.layers.filter{if case .adjustment=$0.content{return false};return true},id:\.id){Text($0.name).tag(Optional($0.id))}
        }
        Toggle("Use Selection in Source",isOn:Binding(get:{model.useSelectionInSource},set:{model.useSelectionInSource=$0;model.calculateSource()}))
      }
      Text(model.request.settings.sourceStatistics==nil ? "No stored source statistics":"Stored source statistics will be applied.").font(.caption).foregroundStyle(.secondary)
      Divider()
      number("Luminance",\.luminance,1...200)
      number("Color Intensity",\.intensity,1...200)
      number("Fade (%)",\.fade,0...100)
      Toggle("Neutralize",isOn:choice(\.neutralize))
      Toggle("Ignore Selection when Applying",isOn:choice(\.ignoreSelection))
      Toggle("Use Selection in Target for Statistics",isOn:choice(\.useSelectionInTarget))
    }
  }
  var replace:some View {
    VStack(alignment:.leading,spacing:12) {
      Picker("Preview",selection:$model.maskPreview){Text("Image").tag(false);Text("Selection").tag(true)}.pickerStyle(.segmented)
      Picker("Sample",selection:$model.sampleMode){Text("Replace").tag("replace");Text("Add").tag("add");Text("Subtract").tag("subtract")}.pickerStyle(.segmented)
      Text("Click the preview to sample a color. \(model.request.settings.samples.count) samples.").font(.caption).foregroundStyle(.secondary)
      ColorPicker("Sample Color",selection:Binding(get:{let p=model.request.settings.samples[0].color;return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b))},set:{value in
        guard let c=NSColor(value).usingColorSpace(.sRGB) else{return}
        model.update{$0.settings.samples=[ToneColorSample(color:Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent)))]}
      }),supportsOpacity:false)
      number("Fuzziness",\.fuzziness,0...200)
      Toggle("Localized Color Clusters",isOn:choice(\.localized))
      if model.request.settings.localized {number("Range (pixels)",\.localRadius,1...16384)}
      Divider();Text("Replacement").font(.headline)
      number("Hue",\.hue,-180...180)
      number("Saturation",\.saturation,-100...100)
      number("Lightness",\.lightness,-100...100)
    }
  }
  func loadPreset() {
    let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
    guard panel.runModal() == .OK,let url=panel.url else{return}
    do {try model.loadPreset(Data(contentsOf:url))}catch{model.error=error.localizedDescription}
  }
  func savePreset() {
    let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="\(kind.title.replacingOccurrences(of:"/",with:"-"))-settings.json"
    guard panel.runModal() == .OK,let url=panel.url else{return}
    do {try model.presetData().write(to:url,options:.atomic)}catch{model.error=error.localizedDescription}
  }
}

private struct ClassicToneCurve:View {
  @Bindable var model:ClassicToneWorkspace
  @State private var selected:Int?
  var points:[[Float]] {model.request.settings.curve.isEmpty ? [[0,0],[1,1]]:model.request.settings.curve}
  var body:some View {
    GeometryReader {g in
      Canvas {context,size in
        var path=Path();for (i,p) in points.enumerated(){let q=CGPoint(x:Double(p[0])*size.width,y:(1-Double(p[1]))*size.height);if i==0{path.move(to:q)}else{path.addLine(to:q)}}
        context.stroke(path,with:.color(.white),lineWidth:2)
        for p in points {let r=CGRect(x:Double(p[0])*size.width-4,y:(1-Double(p[1]))*size.height-4,width:8,height:8);context.fill(Path(ellipseIn:r),with:.color(.accentColor))}
      }.background(Color(white:0.15)).clipped().contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:0).onChanged{value in
          var p=points;let x=Float(min(1,max(0,value.location.x/g.size.width))),y=Float(min(1,max(0,1-value.location.y/g.size.height)))
          if selected==nil {
            model.beginGesture()
            if let nearest=p.indices.min(by:{abs(p[$0][0]-x)<abs(p[$1][0]-x)}),abs(p[nearest][0]-x)<0.05 {selected=nearest}
            else if p.count<32 {p.append([x,y]);p.sort{$0[0]<$1[0]};selected=p.firstIndex{$0[0]==x}}
          }
          if let i=selected,p.indices.contains(i){let lo=i==0 ? Float(0):p[i-1][0]+0.00001,hi=i==p.count-1 ? Float(1):p[i+1][0]-0.00001;p[i]=[min(hi,max(lo,x)),y];model.update{$0.settings.curve=p}}
        }.onEnded{_ in model.endGesture();selected=nil})
        .accessibilityLabel("HDR toning curve. Click to add a point; drag to adjust.")
    }
  }
}
