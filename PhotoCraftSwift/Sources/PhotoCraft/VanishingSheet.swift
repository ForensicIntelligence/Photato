import AppKit
import PhotoCraftCore
import SwiftUI

struct VanishingSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:VanishingWorkspace
  @State private var edge:VanishingPlane.Edge = .top
  @State private var sourceID:UUID?
  func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View { VStack(spacing:3) { HStack { Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:68) };Slider(value:value,in:range) } }
  func planeNumber(_ key:WritableKeyPath<VanishingPlane,Double>)->Binding<Double> { .init(get:{model.program.settings.planes[model.selected][keyPath:key]},set:{n in var p=model.program;p.settings.planes[model.selected][keyPath:key]=n;model.change(p)}) }
  func pasteNumber(_ index:Int,_ key:WritableKeyPath<VanishingOperation,Double>)->Binding<Double> { .init(get:{model.program.operations[index][keyPath:key]},set:{n in var p=model.program;p.operations[index][keyPath:key]=n;model.change(p)}) }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text("Vanishing Point").font(.headline);Spacer();if model.rendering { ProgressView().controlSize(.small) };Toggle("New Layer",isOn:Binding(get:{model.program.newLayer},set:{v in var p=model.program;p.newLayer=v;model.change(p)})) }
      HStack(alignment:.top,spacing:16) {
        VStack {
          Picker("Tool",selection:$model.tool) { ForEach(VanishingWorkspace.Tool.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
          VanishingPreview(model:model)
          HStack { Toggle("Show Grid",isOn:$model.showGrid);Text("Grid Size");Slider(value:$model.gridSize,in:2...40).frame(width:150);Spacer() }.controlSize(.small)
        }.frame(minWidth:550)
        ScrollView { VStack(alignment:.leading,spacing:12) {
          if model.tool == .create { Text("Click four corners around a rectangular surface. The grid follows its perspective.").font(.caption);Button("Clear Points") { model.pending=[];model.error=nil }.disabled(model.pending.isEmpty) }
          if !model.program.settings.planes.isEmpty {
            Picker("Plane",selection:$model.selected) { ForEach(model.program.settings.planes.indices,id:\.self) { Text("Plane \($0+1)").tag($0) } }
            if model.tool == .edit || model.tool == .create {
              if model.program.settings.planes[model.selected].parent != nil {
                number("Angle (°)",planeNumber(\.angle),0...180);number("Depth",planeNumber(\.depth),0.05...10)
                Button("Detach Plane") { model.detach() }
              } else { Text("Drag a corner to fit the surface, or drag inside the plane to move it.").font(.caption).foregroundStyle(.secondary) }
              HStack { Picker("Edge",selection:$edge) { ForEach(VanishingPlane.Edge.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } };Button("Extend") { model.tear(edge) } }
              Button("Delete Plane & Edits") { model.removePlane() }
            }
          }
          if model.tool == .brush || model.tool == .stamp {
            number("Diameter (px)",$model.diameter,1...500);number("Hardness (%)",$model.hardness,0...100);number("Opacity (%)",$model.opacity,0...100)
            Toggle("Clip to Surface",isOn:$model.clip)
            if model.tool == .stamp { Toggle("Aligned",isOn:$model.aligned);Text("Option-click a plane to sample, then drag to clone in perspective.").font(.caption).foregroundStyle(.secondary) }
            else { ColorPicker("Brush Color",selection:Binding(get:{Color(.sRGB,red:Double(model.color.r),green:Double(model.color.g),blue:Double(model.color.b),opacity:Double(model.color.a))},set:{c in if let c=NSColor(c).usingColorSpace(.sRGB) { model.color=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent),Float(c.alphaComponent)) } })) }
          }
          Divider();Text("Paste into Perspective").font(.subheadline.bold())
          Button("Paste Clipboard") { do { let input=try store.clipboard.read();Task { await model.pasteClipboard(input) } } catch { model.error=error.localizedDescription } }.disabled(model.program.settings.planes.isEmpty).keyboardShortcut("v",modifiers:.command)
          Picker("Source Layer",selection:$sourceID) { Text("Choose…").tag(nil as UUID?);ForEach(model.original.layers.filter{if case .raster=$0.content { return true };return false}) { Text($0.name).tag(Optional($0.id)) } }
          Button("Paste Layer Pixels") { if let sourceID { model.pasteLayer(sourceID) } }.disabled(sourceID==nil || model.program.settings.planes.isEmpty)
          let pastes=model.program.operations.indices.filter{model.program.operations[$0].kind == .paste}
          if !pastes.isEmpty {
            Picker("Pasted Item",selection:$model.selectedPaste) { Text("None").tag(nil as Int?);ForEach(pastes,id:\.self) { Text("Item \($0+1)").tag(Optional($0)) } }
          }
          if let index=model.selectedPaste,model.program.operations.indices.contains(index) {
            Text("Use Transform to drag this item across a plane.").font(.caption).foregroundStyle(.secondary)
            number("Width (plane fraction)",pasteNumber(index,\.width),0.01...2);number("Rotation (°)",pasteNumber(index,\.angle),-180...180);number("Opacity (%)",pasteNumber(index,\.opacity),0...100)
            Button("Delete Pasted Item") { var p=model.program;p.operations.remove(at:index);model.selectedPaste=nil;model.change(p) }
          }
          if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.frame(width:280).padding(.trailing,5) }.frame(width:295)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview);Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(8,model.zoom*1.5) };Button("Fit") { model.zoom=1;model.pan = .zero }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty && model.pending.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { store.cancelVanishingPoint() }.keyboardShortcut(.cancelAction);Button("OK") { model.endGesture();store.commitVanishingPoint() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(18).frame(width:980,height:740)
    .task { if model.image==nil,!model.rendering { await model.prepare() } }
    .onDisappear { model.close();if store.vanishingWorkspace === model { store.vanishingWorkspace=nil } }
  }
}
struct VanishingPreview:View {
  @Bindable var model:VanishingWorkspace
  @State private var pressed=false
  @State private var pan=CGSize.zero
  @State private var hit:Int?
  @State private var corner:Int?
  @State private var stroke=[PathPoint]()
  @State private var sampled=false
  @State private var pasteOrigin:PathPoint?
  var body:some View {
    GeometryReader { geometry in
      let scale=max(0.001,min((geometry.size.width-32)/model.size.width,(geometry.size.height-32)/model.size.height)*model.zoom)
      let offset=CGPoint(x:(geometry.size.width-model.size.width*scale)/2+model.pan.width,y:(geometry.size.height-model.size.height*scale)/2+model.pan.height)
      let scene=model.scene
      Canvas { context,size in
        func screen(_ p:PathPoint)->CGPoint { .init(x:offset.x+p.x*scale,y:offset.y+p.y*scale) }
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        if let image=model.preview ? model.image:model.originalImage { context.draw(Image(decorative:image,scale:1),in:CGRect(x:offset.x,y:offset.y,width:model.size.width*scale,height:model.size.height*scale)) }
        if model.showGrid,let scene {
          for (i,frame) in scene.frames.enumerated() {
            var grid=Path();let n=max(2,Int(model.gridSize))
            for j in 0...n { let u=Double(j)/Double(n);grid.move(to:screen(frame.point(.init(u,0))));grid.addLine(to:screen(frame.point(.init(u,1))));grid.move(to:screen(frame.point(.init(0,u))));grid.addLine(to:screen(frame.point(.init(1,u)))) }
            context.stroke(grid,with:.color(i==model.selected ? .cyan:.blue.opacity(0.6)),lineWidth:i==model.selected ? 1:0.6)
            for p in frame.corners { let q=screen(p);context.fill(Path(ellipseIn:CGRect(x:q.x-4,y:q.y-4,width:8,height:8)),with:.color(i==model.selected ? .cyan:.blue)) }
          }
        }
        let points=model.pending.isEmpty ? stroke:model.pending
        var path=Path();for (i,p) in points.enumerated() { let q=screen(p);if i==0 { path.move(to:q) } else { path.addLine(to:q) };if !model.pending.isEmpty { context.fill(Path(ellipseIn:CGRect(x:q.x-3,y:q.y-3,width:6,height:6)),with:.color(.orange)) } };context.stroke(path,with:.color(.orange),lineWidth:2)
        if let source=model.cloneSource { let p=screen(source);var cross=Path();cross.move(to:.init(x:p.x-7,y:p.y));cross.addLine(to:.init(x:p.x+7,y:p.y));cross.move(to:.init(x:p.x,y:p.y-7));cross.addLine(to:.init(x:p.x,y:p.y+7));context.stroke(cross,with:.color(.yellow),lineWidth:1.5) }
      }.toolCursor { flags in
        switch model.tool {
        case .hand: return pressed ? .closedHand:.openHand
        case .stamp: return .symbol((pressed ? sampled:flags.contains(.option)) ? "scope":"paintbrush.pointed")
        case .brush: return .symbol("paintbrush.pointed")
        case .edit,.transform: return .symbol("arrow.up.and.down.and.arrow.left.and.right")
        case .create: return .symbol("plus")
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        func point(_ p:CGPoint)->PathPoint { .init((p.x-offset.x)/scale,(p.y-offset.y)/scale) }
        if !pressed {
          pressed=true;pan=model.pan;stroke=[];hit=nil;corner=nil;sampled=false;pasteOrigin=nil;model.beginGesture()
          let start=point(value.startLocation)
          if model.tool == .edit,let scene {
            var best=10.0/scale
            for (i,f) in scene.frames.enumerated() where model.program.settings.planes[i].parent==nil { for (j,p) in f.corners.enumerated() { let distance=hypot(p.x-start.x,p.y-start.y);if distance<best { best=distance;hit=i;corner=j } } }
            if hit==nil { hit=scene.plane(at:start) };if let hit { model.selected=hit }
          }
          if model.tool == .stamp && NSEvent.modifierFlags.contains(.option) { model.setSource(start);sampled=true }
          if model.tool == .transform,let index=model.selectedPaste,model.program.operations.indices.contains(index),let scene { let op=model.program.operations[index];pasteOrigin=scene.frames[op.plane].point(op.at) }
        }
        let p=point(value.location)
        switch model.tool {
        case .hand:model.pan=CGSize(width:pan.width+value.translation.width,height:pan.height+value.translation.height)
        case .edit:if let hit { if let corner { model.moveCorner(hit,corner,to:p) } else { model.movePlane(hit,dx:value.translation.width/scale,dy:value.translation.height/scale) } }
        case .brush,.stamp:if !sampled,stroke.last.map({hypot($0.x-p.x,$0.y-p.y)>1}) ?? true { if stroke.count<4096 { stroke.append(p) } }
        case .transform:if let pasteOrigin { model.movePaste(to:.init(pasteOrigin.x+value.translation.width/scale,pasteOrigin.y+value.translation.height/scale)) }
        case .create:break
        }
      }.onEnded { value in
        if model.tool == .create { model.addPoint(.init((value.location.x-offset.x)/scale,(value.location.y-offset.y)/scale)) }
        if (model.tool == .brush || model.tool == .stamp) && !sampled { model.stroke(stroke) }
        model.endGesture();pressed=false;stroke=[];hit=nil;corner=nil;pasteOrigin=nil
      }).clipped().accessibilityLabel("Vanishing Point preview. Define four plane corners, paint or clone in perspective, or transform a pasted image.")
    }
  }
}
