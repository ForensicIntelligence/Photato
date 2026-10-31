import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct LensCorrectionSheet:View {
  @Bindable var store:EditorStore
  @State private var model:LensCorrectionWorkspace
  @State private var tab="Custom"
  @State private var focal=35.0
  @State private var importing=false
  @State private var exporting=false
  @State private var exportFile:LUTDocument?
  @State private var gridColor=Color.white.opacity(0.45)
  init(store:EditorStore,model:LensCorrectionWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? LensCorrectionWorkspace()) }
  func number(_ key:WritableKeyPath<LensCorrectionSettings,Double>)->Binding<Double> { .init(get:{model.settings[keyPath:key]},set:{n in var s=model.settings;s[keyPath:key]=n;model.change(s)}) }
  func flag(_ key:WritableKeyPath<LensCorrectionSettings,Bool>)->Binding<Bool> { .init(get:{model.settings[keyPath:key]},set:{n in var s=model.settings;s[keyPath:key]=n;model.change(s)}) }
  func field(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
    VStack(spacing:3) { HStack { Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...3))).frame(width:65) };Slider(value:value,in:range,onEditingChanged:model.slider) }
  }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text("Lens Correction").font(.headline);Spacer();if model.rendering { ProgressView().controlSize(.small) };Button("Load Settings…") { importing=true };Button("Save Settings…") { do { exportFile=LUTDocument(data:try JSONEncoder().encode(model.settings));exporting=true } catch { model.error=error.localizedDescription } } }
      HStack(alignment:.top,spacing:16) {
        VStack { Picker("Tool",selection:$model.tool) { ForEach(LensCorrectionWorkspace.Tool.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
          LensCorrectionPreview(model:model,gridColor:gridColor)
          HStack { Toggle("Show Grid",isOn:$model.showGrid);Text("Size");Slider(value:$model.gridSize,in:10...200).frame(width:100);ColorPicker("Color",selection:$gridColor).labelsHidden() }
        }.frame(minWidth:510)
        ScrollView { VStack(alignment:.leading,spacing:12) {
          Picker("Corrections",selection:$tab) { Text("Auto Correction").tag("Auto Correction");Text("Custom").tag("Custom") }.pickerStyle(.segmented).labelsHidden()
          if tab == "Custom" { customControls } else { profileControls }
          Divider();Toggle("Auto Scale Image",isOn:flag(\.autoScale))
          if model.settings.autoScale { Text("Resolved scale: \(model.effectiveScale,format:.number.precision(.fractionLength(1)))%").font(.caption) }
          Picker("Edge",selection:Binding(get:{model.settings.edge},set:{n in var s=model.settings;s.edge=n;model.change(s)})) {
            Text("Transparency").tag(LensCorrectionSettings.Edge.transparency);Text("Edge Extension").tag(LensCorrectionSettings.Edge.edgeExtension);Text("Black Color").tag(LensCorrectionSettings.Edge.black);Text("White Color").tag(LensCorrectionSettings.Edge.white);Text("Custom Color").tag(LensCorrectionSettings.Edge.color)
          }
          if model.settings.edge == .color { ColorPicker("Edge Color",selection:Binding(get:{ let c=model.settings.edgeColor;return Color(.sRGB,red:c[0],green:c[1],blue:c[2],opacity:c[3]) },set:{color in guard let c=NSColor(color).usingColorSpace(.sRGB) else { return };var s=model.settings;s.edgeColor=[c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent];model.change(s)})) }
          if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.frame(width:280).padding(.trailing,5) }.frame(width:295)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(8,model.zoom*1.5) };Button("Fit") { model.zoom=1;model.pan = .zero }
        Button("Reset") { model.change(.init()) }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter.lens=model.settings;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(18).frame(width:940,height:720)
    .task { store.lensCorrectionWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else { return };await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close();if store.lensCorrectionWorkspace === model { store.lensCorrectionWorkspace=nil } }
    .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.data]) { result in
      do { let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } };let file=try FileHandle(forReadingFrom:url);defer { try? file.close() };let data=try file.read(upToCount:32769) ?? Data();guard data.count<=32768 else { throw CraftError.invalid("Lens settings exceed32KiB.") };model.change(try LensCorrectionSettings.decodeJSON(data)) } catch { model.error=error.localizedDescription }
    }
    .fileExporter(isPresented:$exporting,document:exportFile,contentType:.json,defaultFilename:"Lens Correction.photatolens") { if case .failure(let error)=$0 { model.error=error.localizedDescription } }
  }
  var customControls:some View {
    Group {
      Text("Geometric Distortion").font(.subheadline.bold());field("Remove Distortion",number(\.distortion),-100...100)
      Divider();Text("Chromatic Aberration").font(.subheadline.bold());field("Fix Red/Cyan Fringe",number(\.redCyan),-100...100);field("Fix Blue/Yellow Fringe",number(\.blueYellow),-100...100)
      Divider();Text("Vignette").font(.subheadline.bold());field("Amount",number(\.vignetteAmount),-100...100);field("Midpoint",number(\.vignetteMidpoint),0...100)
      Divider();Text("Transform").font(.subheadline.bold());field("Vertical Perspective",number(\.vertical),-100...100);field("Horizontal Perspective",number(\.horizontal),-100...100);field("Angle",number(\.angle),-180...180);field("Scale (%)",number(\.scale),50...150)
    }
  }
  func coefficient(_ title:String,_ key:WritableKeyPath<LensCorrectionSettings.Profile,Double>)->some View {
    HStack { Text(title);Spacer();TextField(title,value:Binding(get:{model.settings.profile?[keyPath:key] ?? 0},set:{n in var s=model.settings;s.profile?[keyPath:key]=n;model.change(s)}),format:.number.precision(.fractionLength(0...6))).frame(width:95) }
  }
  var profileControls:some View {
    Group {
      Toggle("Geometric Distortion",isOn:flag(\.correctDistortion));Toggle("Chromatic Aberration",isOn:flag(\.correctCA));Toggle("Vignette",isOn:flag(\.correctVignette))
      Divider();Text("Lens Profile").font(.subheadline.bold())
      Text(model.settings.profile == nil && model.settings.genericFocalLength == nil ? "None":model.settings.resolvedProfile.name).font(.caption)
      HStack { Button("Custom") { var s=model.settings;s.profile=s.resolvedProfile;s.genericFocalLength=nil;model.change(s) };Button("Clear") { var s=model.settings;s.profile=nil;s.genericFocalLength=nil;model.change(s) } }
      HStack { Text("35 mm equivalent");TextField("Focal length",value:$focal,format:.number).frame(width:55);Text("mm") }
      Button("Use Generic Estimate") { var s=model.settings;s.profile=nil;s.genericFocalLength=min(200,max(12,focal.isFinite ? focal:50));model.change(s) }
      Text("Generic estimates are not calibrated camera or lens profiles. Load custom coefficients with Load Settings.").font(.caption).foregroundStyle(.secondary)
      if model.settings.profile != nil {
        coefficient("Radial k1",\.k1);coefficient("Radial k2",\.k2);coefficient("Tangential p1",\.p1);coefficient("Tangential p2",\.p2);coefficient("Red scale offset",\.caRed);coefficient("Blue scale offset",\.caBlue)
        ForEach(0..<3,id:\.self) { i in HStack { Text("Vignette v\(i+1)");Spacer();TextField("Vignette",value:Binding(get:{model.settings.profile?.vignette[i] ?? 0},set:{n in var s=model.settings;s.profile?.vignette[i]=n;model.change(s)}),format:.number).frame(width:95) } }
      }
    }
  }
}
struct LensCorrectionPreview:View {
  @Bindable var model:LensCorrectionWorkspace
  var gridColor:Color
  @State private var pressed=false
  @State private var initialPan=CGSize.zero
  @State private var initialGrid=CGPoint.zero
  @State private var lineStart:CGPoint?
  @State private var lineEnd:CGPoint?
  var body:some View {
    GeometryReader { geometry in
      let scale=min((geometry.size.width-32)/model.documentSize.width,(geometry.size.height-32)/model.documentSize.height)*model.zoom
      let offset=CGPoint(x:(geometry.size.width-model.documentSize.width*scale)/2+model.pan.width,y:(geometry.size.height-model.documentSize.height*scale)/2+model.pan.height)
      let inverse=(try? model.sourceTransform.inverted()) ?? .identity,sourceSize=model.sourceSize
      Canvas { context,size in
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        let rect=CGRect(x:offset.x,y:offset.y,width:model.documentSize.width*scale,height:model.documentSize.height*scale)
        if let image=model.preview ? model.image:model.originalImage { context.draw(Image(decorative:image,scale:1),in:rect) }
        if model.showGrid {
          var grid=Path();let step=max(8,model.gridSize*scale),ox=(offset.x+model.gridOrigin.x*scale).truncatingRemainder(dividingBy:step),oy=(offset.y+model.gridOrigin.y*scale).truncatingRemainder(dividingBy:step)
          for x in stride(from:ox,to:size.width,by:step) { grid.move(to:.init(x:x,y:0));grid.addLine(to:.init(x:x,y:size.height)) }
          for y in stride(from:oy,to:size.height,by:step) { grid.move(to:.init(x:0,y:y));grid.addLine(to:.init(x:size.width,y:y)) }
          context.stroke(grid,with:.color(gridColor),lineWidth:0.5)
        }
        if let a=lineStart,let b=lineEnd { var line=Path();line.move(to:a);line.addLine(to:b);context.stroke(line,with:.color(.orange),lineWidth:2) }
      }.toolCursor { _ in
        switch model.tool {
        case .hand: return pressed ? .closedHand:.openHand
        case .grid: return .symbol("square.grid.3x3")
        case .straighten: return .symbol("level")
        case .distortion: return .symbol("viewfinder")
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        if !pressed { pressed=true;initialPan=model.pan;initialGrid=model.gridOrigin;model.beginGesture() }
        func normalized(_ p:CGPoint)->PathPoint { let q=PathPoint((p.x-offset.x)/scale,(p.y-offset.y)/scale).transformed(inverse);return .init(q.x/sourceSize.width,q.y/sourceSize.height) }
        switch model.tool {
        case .hand:model.pan=CGSize(width:initialPan.width+value.translation.width,height:initialPan.height+value.translation.height)
        case .grid:model.gridOrigin=CGPoint(x:initialGrid.x+value.translation.width/scale,y:initialGrid.y+value.translation.height/scale)
        case .straighten:lineStart=value.startLocation;lineEnd=value.location
        case .distortion:model.distort(from:normalized(value.startLocation),to:normalized(value.location))
        }
      }.onEnded { value in
        if model.tool == .straighten {
          let a=PathPoint((value.startLocation.x-offset.x)/scale,(value.startLocation.y-offset.y)/scale).transformed(inverse),b=PathPoint((value.location.x-offset.x)/scale,(value.location.y-offset.y)/scale).transformed(inverse)
          model.straighten(.init(a.x/sourceSize.width,a.y/sourceSize.height),.init(b.x/sourceSize.width,b.y/sourceSize.height))
        }
        model.endGesture();pressed=false;lineStart=nil;lineEnd=nil
      }).clipped().accessibilityLabel("Lens Correction preview. Choose Straighten and drag a reference line, or Remove Distortion and drag toward or away from the center.")
    }
  }
}
