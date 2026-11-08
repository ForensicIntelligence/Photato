import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

struct BrushDynamicControl:View {
  let title:String
  @Binding var value:BrushDynamic
  var maximum=1.0
  var body:some View {
    VStack(alignment:.leading) {
      HStack { Text(title);Slider(value:$value.jitter,in:0...maximum);Text("\(Int(value.jitter*100))%").monospacedDigit().frame(width:48) }
      Picker("Control",selection:$value.control) { ForEach(BrushControl.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
      if value.control == .fade { Stepper("Fade: \(value.fadeSteps)",value:$value.fadeSteps,in:1...10000) }
      if value.control != .off { HStack { Text("Minimum");Slider(value:$value.minimum,in:0...1);Text("\(Int(value.minimum*100))%") } }
    }.padding(.vertical,4)
  }
}
/// Only sections with an existing enable flag get a sidebar toggle.
/// Locks continue to control preset replacement independently of enable state.
enum BrushSectionToggle: String, CaseIterable, Sendable {
  case shape, scattering, texture, dual, colorDynamics, transfer, pose
  case noise, wetEdges, buildUp, protectTexture
  var keyPath: WritableKeyPath<BrushSettings, Bool> {
    switch self {
    case .shape: \.shape.enabled
    case .scattering: \.scattering.enabled
    case .texture: \.texture.enabled
    case .dual: \.dual.enabled
    case .colorDynamics: \.colorDynamics.enabled
    case .transfer: \.transfer.enabled
    case .pose: \.pose.enabled
    case .noise: \.noise
    case .wetEdges: \.wetEdges
    case .buildUp: \.buildUp
    case .protectTexture: \.protectTexture
    }
  }
  var brushPath: String {
    "settings." + rawValue + ([Self.noise, .wetEdges, .buildUp, .protectTexture].contains(self) ? "" : ".enabled")
  }
  static var apiCapabilities: [String: Any] {
    ["sections": allCases.map { ["section": $0.rawValue, "brushPath": $0.brushPath] },
     "command": "brush.configure", "state": "brush.brush.settings contains the same flags used by the native sidebar and section controls.",
     "history": "Enabling a group changes tool settings only, with no document pixels, dirty state or Undo entry. Preset section locks remain independent; started strokes keep their captured Brush.",
     "availability": "Native controls are disabled during a brush gesture or geometry work. API changes retain existing busy/stale/validation guards. Tip Shape, Smoothing and Symmetry have no new enable flag.",
     "qualification": "Presentation controls over existing native settings; full brush kernels/defaults, physical UI/tablet behavior and Photoshop output remain unqualified."]
  }
}

struct BrushSettingsPanel:View {
  @Bindable var store:EditorStore
  @State var section="tip"
  static let titles=["tip":"Brush Tip Shape","shape":"Shape Dynamics","scattering":"Scattering","texture":"Texture","dual":"Dual Brush","colorDynamics":"Color Dynamics","transfer":"Transfer","pose":"Brush Pose","noise":"Noise","wetEdges":"Wet Edges","buildUp":"Build-up","smoothing":"Smoothing","protectTexture":"Protect Texture","symmetry":"Symmetry"]
  func scalar(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,percent:Bool=false)->some View {
    HStack { Text(title).frame(width:95,alignment:.leading);Slider(value:value,in:range);Text(percent ? "\(Int(value.wrappedValue*100))%":String(format:"%.1f",value.wrappedValue)).monospacedDigit().frame(width:52) }
  }
  func lock(_ name:String)->Binding<Bool> { .init(get:{store.brushOptions.lockedSections.contains(name)},set:{on in var b=store.brushOptions;b.lockedSections.removeAll{$0==name};if on { b.lockedSections.append(name) };store.brushOptions=b}) }
  func sectionEnabled(_ key: String) -> Binding<Bool>? {
    guard let section = BrushSectionToggle(rawValue: key) else { return nil }
    return Binding(get: { store.brushOptions[keyPath: section.keyPath] }, set: { enabled in
      guard store.brushGesture == nil, !store.geometryBusy else { return }
      var settings = store.brushOptions
      guard settings[keyPath: section.keyPath] != enabled else { return }
      settings[keyPath: section.keyPath] = enabled
      store.brushOptions = settings
    })
  }
  var body:some View {
    VStack(spacing:0) {
      HStack(alignment:.top,spacing:0) {
        List(selection:$section) {
          ForEach(BrushSettings.sections+["symmetry"],id:\.self) { key in
            HStack {
              if let enabled = sectionEnabled(key) {
                Toggle("Enable " + (Self.titles[key] ?? key), isOn: enabled)
                  .labelsHidden().toggleStyle(.checkbox)
                  .accessibilityIdentifier("brush.section." + key + ".enabled")
                  .help("Enable or disable " + (Self.titles[key] ?? key))
              }
              Text(Self.titles[key] ?? key)
              Spacer()
              if key != "symmetry" {
                Toggle("Lock",isOn:lock(key)).labelsHidden().toggleStyle(.checkbox)
                  .help("Preserve this section when choosing another brush")
              }
            }.tag(key)
          }
        }.frame(width:180)
        ScrollView { controls.padding(14) }.frame(minWidth:300,maxWidth:.infinity)
      }.disabled(store.brushGesture != nil || store.geometryBusy)
      if store.brushTextureLoading {
        HStack {
          ProgressView().controlSize(.small).accessibilityLabel("Preparing brush texture")
          Text("Preparing brush texture…")
          Spacer()
          Button("Cancel") { store.geometryTask?.cancel() }.accessibilityIdentifier("brush.texture.cancel")
        }.padding(8)
      }
      Divider();BrushStrokePreview(brush:store.brush).frame(height:90).padding(8)
    }.frame(minWidth:510,minHeight:440)
  }
  @ViewBuilder var controls:some View {
    VStack(alignment:.leading,spacing:10) {
      Text(Self.titles[section] ?? section).font(.headline)
      switch section {
      case "tip":
        scalar("Size",$store.brush.size,0.5...2048)
        scalar("Hardness",Binding(get:{Double(store.brush.hardness)},set:{store.brush.hardness=Float($0)}),0...1,percent:true)
        scalar("Angle",$store.brushOptions.angle,-180...180)
        scalar("Roundness",$store.brushOptions.roundness,0.01...1,percent:true)
        Toggle("Spacing",isOn:$store.brushOptions.spacingEnabled)
        scalar("Spacing",$store.brushOptions.spacing,0.01...10,percent:true)
        Toggle("Flip X",isOn:$store.brushOptions.flipX);Toggle("Flip Y",isOn:$store.brushOptions.flipY)
        if let tip=store.brushOptions.tip { Text("Sampled tip: \(tip.width) × \(tip.height)");Button("Use Round Tip"){store.brushOptions.tip=nil} }
        Toggle("Hard pixel edges",isOn:$store.brushOptions.aliased)
      case "shape":
        Toggle("Shape Dynamics",isOn:$store.brushOptions.shape.enabled)
        BrushDynamicControl(title:"Size Jitter",value:$store.brushOptions.shape.size)
        BrushDynamicControl(title:"Angle Jitter",value:$store.brushOptions.shape.angle)
        BrushDynamicControl(title:"Roundness Jitter",value:$store.brushOptions.shape.roundness)
        scalar("Tilt Scale",$store.brushOptions.shape.tiltScale,0...2,percent:true)
        Toggle("Flip X Jitter",isOn:$store.brushOptions.shape.flipX);Toggle("Flip Y Jitter",isOn:$store.brushOptions.shape.flipY);Toggle("Brush Projection",isOn:$store.brushOptions.shape.projection)
      case "scattering":
        Toggle("Scattering",isOn:$store.brushOptions.scattering.enabled)
        BrushDynamicControl(title:"Scatter",value:$store.brushOptions.scattering.amount,maximum:10)
        Toggle("Both Axes",isOn:$store.brushOptions.scattering.bothAxes)
        Stepper("Count: \(store.brushOptions.scattering.count)",value:$store.brushOptions.scattering.count,in:1...16)
        BrushDynamicControl(title:"Count Jitter",value:$store.brushOptions.scattering.countJitter)
      case "texture":
        Toggle("Texture",isOn:$store.brushOptions.texture.enabled)
        BrushPatternTexturePicker(store:store)
        Picker("Generated Pattern",selection:$store.brushOptions.texture.pattern) { ForEach(BrushTexture.Pattern.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)} }.onChange(of:store.brushOptions.texture.pattern){_,_ in store.brushOptions.texture.bitmap=nil}
        if store.brushOptions.texture.bitmap != nil { Button("Use Generated Pattern"){store.brushOptions.texture.bitmap=nil} }
        scalar("Scale",$store.brushOptions.texture.scale,0.01...10,percent:true)
        scalar("Brightness",$store.brushOptions.texture.brightness,-1...1,percent:true);scalar("Contrast",$store.brushOptions.texture.contrast,-1...1,percent:true)
        Toggle("Invert",isOn:$store.brushOptions.texture.invert);Toggle("Texture Each Tip",isOn:$store.brushOptions.texture.eachTip)
        Picker("Mode",selection:$store.brushOptions.texture.mode){ForEach(BrushMaskMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        scalar("Depth",$store.brushOptions.texture.depth,0...1,percent:true)
        BrushDynamicControl(title:"Depth Jitter",value:$store.brushOptions.texture.depthJitter)
      case "dual":
        Toggle("Dual Brush",isOn:$store.brushOptions.dual.enabled)
        Menu("Choose Secondary Tip") { Button("Round"){store.brushOptions.dual.tip=nil};ForEach(store.brushes.file.presets){p in Button(p.name){store.brushOptions.dual.tip=p.brush.settings?.tip;store.brushOptions.dual.size=p.brush.size;store.brushOptions.dual.hardness=Double(p.brush.hardness)}} }
        Picker("Mode",selection:$store.brushOptions.dual.mode){ForEach(BrushMaskMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        scalar("Size",$store.brushOptions.dual.size,0.5...2048);scalar("Hardness",$store.brushOptions.dual.hardness,0...1,percent:true)
        scalar("Spacing",$store.brushOptions.dual.spacing,0.01...10,percent:true);scalar("Scatter",$store.brushOptions.dual.scatter,0...10,percent:true)
        scalar("Angle",$store.brushOptions.dual.angle,-180...180);scalar("Roundness",$store.brushOptions.dual.roundness,0.01...1,percent:true)
        Stepper("Count: \(store.brushOptions.dual.count)",value:$store.brushOptions.dual.count,in:1...16)
        Toggle("Both Axes",isOn:$store.brushOptions.dual.bothAxes);Toggle("Flip",isOn:$store.brushOptions.dual.flip)
      case "colorDynamics":
        Toggle("Color Dynamics",isOn:$store.brushOptions.colorDynamics.enabled);Toggle("Apply Per Tip",isOn:$store.brushOptions.colorDynamics.perTip)
        BrushDynamicControl(title:"Foreground/Background Jitter",value:$store.brushOptions.colorDynamics.foregroundBackground)
        scalar("Hue Jitter",$store.brushOptions.colorDynamics.hue,0...1,percent:true);scalar("Saturation Jitter",$store.brushOptions.colorDynamics.saturation,0...1,percent:true);scalar("Brightness Jitter",$store.brushOptions.colorDynamics.brightness,0...1,percent:true);scalar("Purity",$store.brushOptions.colorDynamics.purity,-1...1,percent:true)
      case "transfer":
        Toggle("Transfer",isOn:$store.brushOptions.transfer.enabled)
        BrushDynamicControl(title:"Opacity Jitter",value:$store.brushOptions.transfer.opacity);BrushDynamicControl(title:"Flow Jitter",value:$store.brushOptions.transfer.flow)
      case "pose":
        Toggle("Brush Pose",isOn:$store.brushOptions.pose.enabled)
        scalar("Tilt X",$store.brushOptions.pose.tiltX,-90...90);scalar("Tilt Y",$store.brushOptions.pose.tiltY,-90...90);Toggle("Override Tilt",isOn:$store.brushOptions.pose.overrideTilt)
        scalar("Rotation",$store.brushOptions.pose.rotation,-180...180);Toggle("Override Rotation",isOn:$store.brushOptions.pose.overrideRotation)
        scalar("Pressure",$store.brushOptions.pose.pressure,0...1,percent:true);Toggle("Override Pressure",isOn:$store.brushOptions.pose.overridePressure)
      case "noise":Toggle("Noise",isOn:$store.brushOptions.noise)
      case "wetEdges":Toggle("Wet Edges",isOn:$store.brushOptions.wetEdges)
      case "buildUp":Toggle("Build-up (Airbrush)",isOn:$store.brushOptions.buildUp);scalar("Dabs / second",$store.brushOptions.buildUpRate,0.1...100)
      case "smoothing":
        scalar("Smoothing",$store.brushOptions.smoothing.amount,0...1,percent:true)
        Toggle("Pulled String Mode",isOn:$store.brushOptions.smoothing.pulledString);Toggle("Stroke Catch-up",isOn:$store.brushOptions.smoothing.catchUp);Toggle("Catch-up on Stroke End",isOn:$store.brushOptions.smoothing.catchUpOnEnd);Toggle("Adjust for Zoom",isOn:$store.brushOptions.smoothing.adjustForZoom)
      case "protectTexture":Toggle("Protect Texture",isOn:$store.brushOptions.protectTexture)
      case "symmetry":
        Picker("Symmetry",selection:$store.brushOptions.symmetry.mode){ForEach(BrushSymmetry.Mode.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
        Stepper("Segments: \(store.brushOptions.symmetry.count)",value:$store.brushOptions.symmetry.count,in:2...12)
        TextField("Center X",value:$store.brushOptions.symmetry.center.x,format:.number);TextField("Center Y",value:$store.brushOptions.symmetry.center.y,format:.number)
        Button("Center on Canvas"){store.brushOptions.symmetry.center = .init(Double(store.document.width)/2,Double(store.document.height)/2)}
      default:EmptyView()
      }
    }.controlSize(.small)
  }
}
struct BrushStrokePreview:View {
  let brush:Brush
  @State var image:CGImage?
  @State var worker:Task<Void,Never>?
  var body:some View {
    ZStack { Color.white;if let image { Image(decorative:image,scale:1).resizable().interpolation(.high).scaledToFit() } }
      .onChange(of:brush,initial:true){_,value in
        worker?.cancel();worker=Task {
          let job=Task.detached { ()throws->CGImage in
            var b=value;b.size=min(40,b.size);b.color = .black;b.erase=false;b.settings?.symmetry.mode = .off;b.settings?.zoom=1
            var surface=try Surface(width:300,height:70,fill:.white)
            let points=(0..<30).map{ i in StrokePoint(x:Double(i)*9+20,y:35+sin(Double(i)/4)*12,pressure:Float(0.3+0.7*sin(Double(i)*Double.pi/29)),time:Double(i)*10) }
            try Painter.stroke(surface:&surface,points:points,brush:b);return try RasterIO.displayImage(surface)
          }
          if let result=try? await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()}),!Task.isCancelled { image=result }
        }
      }.onDisappear{worker?.cancel()}
  }
}
struct BrushesPanel:View {
  @Bindable var store:EditorStore
  @State var name="New Brush"
  @State var group="My Brushes"
  @State var includeSize=true
  @State var includeTool=true
  @State var includeColor=false
  @State var message:String?
  @State var abr=false
  func attempt(_ action:()throws->Void){do{try action();message=nil}catch{message=error.localizedDescription}}
  var body:some View {
    VStack(alignment:.leading) {
      List {
        ForEach(Array(Set(store.brushes.file.presets.map(\.group))).sorted(),id:\.self){group in
          Section(group){ForEach(store.brushes.file.presets.filter{$0.group==group}){p in
            Button {attempt{try store.selectBrush(p.id);name=p.name;self.group=p.group}} label:{HStack{Image(systemName:store.selectedBrushID==p.id ? "checkmark.circle.fill":"circle");Text(p.name);Spacer();Text("\(Int(p.brush.size)) px").foregroundStyle(.secondary)}}.buttonStyle(.plain)
          }}
        }
      }
      BrushStrokePreview(brush:store.brush).frame(height:70)
      TextField("Name",text:$name);TextField("Group",text:$group)
      HStack {Toggle("Size",isOn:$includeSize);Toggle("Tool Settings",isOn:$includeTool);Toggle("Color",isOn:$includeColor)}
      HStack {
        Button("New Preset"){attempt{_ = try store.saveBrush(name:name,group:group,includeSize:includeSize,includeToolSettings:includeTool,includeColor:includeColor)}}
        Button("Rename / Group"){attempt{if let id=store.selectedBrushID {var p=try store.brushes.preset(id);p.name=name;p.group=group;try store.brushes.save(p)}}}.disabled(store.selectedBrushID==nil)
        Button("Delete"){attempt{if let id=store.selectedBrushID{try store.brushes.remove(id);store.selectedBrushID=nil}}}.disabled(store.selectedBrushID==nil)
      }
      HStack {
        Button("Import…"){let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"abr") ?? .data,UTType(filenameExtension:"photatobrushes") ?? .json];panel.begin{result in if result == .OK,let url=panel.url{attempt{let warnings=try store.brushes.importData(BrushLibrary.read(url),abr:url.pathExtension.lowercased()=="abr");message=warnings.isEmpty ? nil:warnings.joined(separator:"\n")}}}}
        Toggle("ABR",isOn:$abr)
        Button("Export Selected…"){let panel=NSSavePanel();let ext=abr ? "abr":"photatobrushes";panel.nameFieldStringValue=name+"."+ext;panel.allowedContentTypes=[UTType(filenameExtension:ext) ?? .data];panel.begin{result in if result == .OK,let url=panel.url{attempt{try store.brushes.exportData(store.selectedBrushID,abr:abr).write(to:url,options:.atomic)}}}}.disabled(store.selectedBrushID==nil)
      }
      if let message=message ?? store.brushes.loadError {Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
    }.padding(12).frame(minWidth:360,minHeight:460).disabled(!store.canUseBrush)
  }
}
struct BrushPanelRoot:View {
  @Bindable var documents:DocumentWindows
  let settings:Bool
  var body:some View { if let document=documents.activeDocument { if settings {BrushSettingsPanel(store:document.store).id(ObjectIdentifier(document.store))}else{BrushesPanel(store:document.store).id(ObjectIdentifier(document.store))} }else{Text("Open an image to use brushes.").padding(30)} }
}
@MainActor extension AppDelegate {
  @objc func showBrushSettings(){showBrushPanel(settings:true)}
  @objc func showBrushes(){showBrushPanel(settings:false)}
  func showBrushPanel(settings:Bool) {
    if (settings ? brushSettingsWindow:brushesWindow)==nil {
      let panel=FloatingPanelWindow(contentRect:NSRect(x:150,y:150,width:settings ? 540:400,height:560),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
      panel.title=settings ? "Brush Settings":"Brushes";panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.hidesOnDeactivate=true;panel.documents=controller.documentWindows;panel.appearance=NSAppearance(named:.darkAqua);panel.tabbingMode = .disallowed
      panel.contentView=NSHostingView(rootView:BrushPanelRoot(documents:controller.documentWindows,settings:settings))
      if settings {brushSettingsWindow=NSWindowController(window:panel)}else{brushesWindow=NSWindowController(window:panel)}
    }
    (settings ? brushSettingsWindow:brushesWindow)?.showWindow(nil)
  }
  @objc func defineBrushPreset(){
    guard let store,store.canUseBrush else{return}
    let alert=NSAlert();alert.messageText="Brush Name";let field=NSTextField(string:"Custom Brush");field.frame=NSRect(x:0,y:0,width:260,height:24);alert.accessoryView=field;alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else{return}
    store.geometryTask=Task{do{_ = try await store.defineBrush(name:field.stringValue);showBrushes()}catch{store.error=error.localizedDescription}}
  }
}
