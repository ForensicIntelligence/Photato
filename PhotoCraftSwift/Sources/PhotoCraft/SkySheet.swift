import AppKit
import SwiftUI
import PhotoCraftCore

struct SkySheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:SkyWorkspace
  func value<T>(_ key:WritableKeyPath<SkyReplacementSettings,T>)->Binding<T>{Binding(get:{model.state.settings[keyPath:key]},set:{var next=model.state;next.settings[keyPath:key]=$0;model.change(next)})}
  func slider(_ title:String,_ key:WritableKeyPath<SkyReplacementSettings,Double>,_ range:ClosedRange<Double>)->some View {
    VStack(alignment:.leading,spacing:3){HStack{Text(title);Spacer();TextField(title,value:value(key),format:.number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder).frame(width:55)};Slider(value:value(key),in:range)}
  }
  var body:some View {
    VStack(spacing:0){
      HStack{Text("Sky Replacement").font(.headline);Picker("Tool",selection:$model.tool){ForEach(SkyTool.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:180)
        if model.tool == .brush{Picker("Mode",selection:$model.add){Text("Add").tag(true);Text("Subtract").tag(false)}.frame(width:140);TextField("Size",value:$model.size,format:.number).frame(width:55).textFieldStyle(.roundedBorder);Slider(value:$model.hardness,in:0...1).frame(width:70).help("Hardness");Slider(value:$model.opacity,in:0...1).frame(width:70).help("Opacity")}
        Spacer();if model.loading || model.rendering || model.committing{ProgressView().controlSize(.small)}
      }.padding(12).disabled(model.committing)
      Divider()
      HStack(spacing:0){SkyCanvas(model:model);Divider();ScrollView{
        VStack(alignment:.leading,spacing:14){
          GroupBox("Sky"){
            VStack(alignment:.leading,spacing:8){
              Picker("Image",selection:Binding(get:{model.state.skyID},set:{model.chooseSky($0)})){
                Text(model.state.sourceLayerID==nil ? "Choose a sky…":"Selected layer").tag(UUID?.none)
                ForEach(model.library.skies){Text($0.name).tag(Optional($0.id))}
              }
              HStack{Button("Import…"){model.importSky()};Button("Rename…"){model.beginSkyRename()}.disabled(!model.canRenameSky);Button("Remove"){model.removeSky()}.disabled(model.state.skyID==nil)}
              Button("Use Selected Layer"){if let id=model.original.activeLayerID{model.useLayer(id)}}
                .disabled(!model.hasRasterSource)
              if model.library.skies.isEmpty{Text("Import a sky image to begin, or use a pixel layer from this document.").font(.caption).foregroundStyle(.secondary)}
              if let error=model.library.loadError{Text(error).font(.caption).foregroundStyle(.red)}
            }.padding(5)
          }
          GroupBox("Edge") {VStack(spacing:10){slider("Shift Edge",\.shiftEdge,-100...100);slider("Fade Edge",\.fadeEdge,0...100)
            Toggle("Use Current Selection",isOn:Binding(get:{model.state.useSelection},set:{var next=model.state;next.useSelection=$0;model.change(next)})).disabled(model.original.selection==nil)
            Toggle("Show Mask",isOn:$model.showMask)
          }.padding(5)}
          GroupBox("Sky Adjustments"){VStack(spacing:10){slider("Brightness",\.brightness,-100...100);slider("Temperature",\.temperature,-100...100);slider("Scale",\.scale,10...500);Toggle("Flip",isOn:value(\.flip))}.padding(5)}
          GroupBox("Foreground Adjustments"){VStack(spacing:10){Picker("Lighting Mode",selection:value(\.lightingMode)){Text("Multiply").tag(SkyLightingMode.multiply);Text("Screen").tag(SkyLightingMode.screen)};slider("Foreground Lighting",\.foregroundLighting,0...100);slider("Edge Lighting",\.edgeLighting,0...100);slider("Color Adjustment",\.colorAdjustment,0...100)}.padding(5)}
          Picker("Output To",selection:value(\.output)){Text("New Layers").tag(SkyOutput.layers);Text("Duplicate Layer").tag(SkyOutput.duplicate)}
          Toggle("Preview",isOn:Binding(get:{!model.showOriginal},set:{model.showOriginal = !$0}))
        }.padding(10).disabled(!model.ready)
      }.frame(width:300)}.frame(minHeight:450)
      if let error=model.error{Text(error).foregroundStyle(.red).font(.caption).padding(8)}
      Divider();HStack{
        Button("Undo"){model.undo()}.disabled(!model.ready || model.undoStates.isEmpty);Button("Redo"){model.redo()}.disabled(!model.ready || model.redoStates.isEmpty)
        Button("Reset"){model.reset()}.disabled(!model.ready);Button("Fit"){model.zoom=1;model.pan = .zero};Slider(value:$model.zoom,in:0.125...4).frame(width:100).accessibilityLabel("Zoom");Text("\(Int(model.zoom*100))%").monospacedDigit()
        Spacer();Button("Cancel"){store.cancelSkyReplacement()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitSkyReplacement()}.keyboardShortcut(.defaultAction).disabled(!model.canCommit)
      }.padding(12)
    }.background(Color(nsColor:.windowBackgroundColor)).frame(minWidth:1000,idealWidth:1150,minHeight:640,idealHeight:740)
      .sheet(item:$model.renameDraft){draft in SkyRenameSheet(model:model,draft:draft)}
      .onDisappear{model.close();if store.skyWorkspace === model{store.skyWorkspace=nil}}
  }
}
struct SkyCanvas:NSViewRepresentable {
  @Bindable var model:SkyWorkspace
  func makeNSView(context:Context)->SkyCanvasView{let v=SkyCanvasView();v.model=model;return v}
  func updateNSView(_ v:SkyCanvasView,context:Context){_=model.previewImage;_=model.maskImage;_=model.showOriginal;_=model.showMask;_=model.zoom;_=model.pan;_=model.stroke;_=model.tool;v.model=model;v.needsDisplay=true;v.refreshToolCursor()}
}
@MainActor final class SkyCanvasView:ModifierCursorView {
  override var toolCursor: ToolCursor {
    guard let model else { return .unavailable }
    if (panning && cursorPointerDown) || (!cursorPointerDown && (spaceHeld || model.tool == .hand)) { return cursorPointerDown ? .closedHand:.openHand }
    switch model.tool {
    case .move: return .symbol("arrow.up.and.down.and.arrow.left.and.right")
    case .brush: return .symbol("paintbrush.pointed",(model.stroke?.add ?? (model.add != cursorModifiers.contains(.option))) ? .add:.subtract)
    case .zoom: return EditorTool.zoom.cursor(modifiers:cursorModifiers)
    case .hand: return .openHand
    }
  }

  weak var model:SkyWorkspace?
  private var start:CGPoint?,previous:CGPoint?
  var panning=false
  override var isFlipped:Bool{true}
  override var acceptsFirstResponder:Bool{true}
  var imageRect:CGRect {
    guard let m=model else{return .zero};let w=Double(m.original.width),h=Double(m.original.height),fit=min(max(1,bounds.width-24)/w,max(1,bounds.height-24)/h)*m.zoom
    return .init(x:(bounds.width-w*fit)/2+m.pan.width,y:(bounds.height-h*fit)/2+m.pan.height,width:w*fit,height:h*fit)
  }
  func point(_ p:CGPoint)->PathPoint{guard let m=model else{return .init(0,0)};let r=imageRect;return .init((p.x-r.minX)/max(1,r.width)*Double(m.original.width),(p.y-r.minY)/max(1,r.height)*Double(m.original.height))}
  override func draw(_ dirtyRect:NSRect){
    NSColor(calibratedWhite:0.14,alpha:1).setFill();bounds.fill();guard let m=model,let image=m.showOriginal ? m.originalImage:(m.previewImage ?? m.originalImage) else{return};let r=imageRect
    func draw(_ image:CGImage){NSImage(cgImage:image,size:.init(width:image.width,height:image.height)).draw(in:r,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])}
    draw(image);if m.showMask,let mask=m.maskImage{draw(mask)}
    if let stroke=m.stroke{let path=NSBezierPath();for (i,p) in stroke.points.enumerated(){let q=CGPoint(x:r.minX+p.x*r.width/Double(m.original.width),y:r.minY+p.y*r.height/Double(m.original.height));if i==0{path.move(to:q)}else{path.line(to:q)}};path.lineWidth=max(1,stroke.size*r.width/Double(m.original.width));path.lineCapStyle = .round;(stroke.add ? NSColor.systemRed:NSColor.systemBlue).withAlphaComponent(0.5).setStroke();path.stroke()}
  }
  override func mouseDown(with event:NSEvent){
    beginCursorGesture(event);defer{refreshToolCursor()}
    guard let m=model,m.ready else{return};window?.makeFirstResponder(self);let p=convert(event.locationInWindow,from:nil);guard imageRect.contains(p) else{return};start=p;previous=p;panning=spaceHeld || m.tool == .hand
    if panning{return};switch m.tool{case .move:m.beginMove();case .brush:m.beginStroke(point(p),alternate:event.modifierFlags.contains(.option));case .zoom:m.zoom=min(16,max(0.125,m.zoom*(event.modifierFlags.contains(.option) ? 0.8:1.25)));case .hand:break};needsDisplay=true
  }
  override func mouseDragged(with event:NSEvent){
    updateCursorModifiers(event.modifierFlags)
    guard let m=model,let start else{return};let p=convert(event.locationInWindow,from:nil)
    if panning,let previous{m.pan.width+=p.x-previous.x;m.pan.height+=p.y-previous.y}
    else if m.tool == .move{let scale=Double(m.original.width)/max(1,imageRect.width);m.move(.init(width:(p.x-start.x)*scale,height:(p.y-start.y)*scale))}
    else if m.tool == .brush{m.dragStroke(point(p))};previous=p;needsDisplay=true
  }
  override func mouseUp(with event:NSEvent){defer{endCursorGesture(event)};guard start != nil else{return};if !panning{if model?.tool == .brush{model?.endStroke()}else if model?.tool == .move{model?.endMove()}};start=nil;previous=nil;panning=false;needsDisplay=true}
  override func scrollWheel(with event:NSEvent){guard let m=model else{return};if event.modifierFlags.contains(.option){m.zoom=min(16,max(0.125,m.zoom*exp(-event.scrollingDeltaY*0.01)))}else{m.pan.width-=event.scrollingDeltaX;m.pan.height-=event.scrollingDeltaY};needsDisplay=true}
  override func magnify(with event:NSEvent){if let m=model{m.zoom=min(16,max(0.125,m.zoom*(1+event.magnification)))}}
  override func performKeyEquivalent(with event:NSEvent)->Bool{guard window?.firstResponder === self,event.modifierFlags.contains(.command),event.charactersIgnoringModifiers?.lowercased()=="z" else{return super.performKeyEquivalent(with:event)};if event.modifierFlags.contains(.shift){model?.redo()}else{model?.undo()};return true}
  override func keyDown(with event:NSEvent){if event.charactersIgnoringModifiers==" "{spaceHeld=true}else{super.keyDown(with:event)}}
  override func keyUp(with event:NSEvent){if event.charactersIgnoringModifiers==" "{spaceHeld=false}else{super.keyUp(with:event)}}
}
