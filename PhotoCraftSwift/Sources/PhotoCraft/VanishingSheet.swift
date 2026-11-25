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
  private func healPicker(_ mode: Binding<VanishingOperation.Heal>) -> some View {
    Picker("Heal", selection: mode) {
      ForEach(VanishingOperation.Heal.allCases, id: \.self) { option in
        Text(option.rawValue.capitalized).tag(option)
      }
    }
    .pickerStyle(.menu)
    .help("Luminance blends surrounding light. On also blends surrounding color.")
  }
  private func toolSymbol(_ tool: VanishingWorkspace.Tool) -> String {
    switch tool {
    case .create: return "plus.rectangle"
    case .edit: return "square.and.pencil"
    case .marquee: return "rectangle.dashed"
    case .stamp: return "scope"
    case .brush: return "paintbrush.pointed"
    case .transform: return "arrow.up.left.and.arrow.down.right"
    case .measure: return "ruler"
    case .hand: return "hand.raised"
    }
  }
  private var marqueeControls: some View {
    let floating = model.floatingMarqueeOperation
    return Group {
      if model.tool == .marquee {
        number("Feather (px)",Binding(get:{ model.floatingMarqueeOperation?.marquee?.feather ?? model.marqueeFeather },
          set:{ value in
            if model.floatingMarqueeOperation != nil { model.updateMarqueePatch { $0.marquee?.feather = value } }
            else { model.marqueeFeather = value }
          }),VanishingMarqueeTransfer.featherRange)
        number("Opacity (%)",Binding(get:{ model.floatingMarqueeOperation?.opacity ?? model.marqueeOpacity },
          set:{ value in
            if model.floatingMarqueeOperation != nil { model.updateMarqueePatch { $0.opacity = value } }
            else { model.marqueeOpacity = value }
          }),0...100)
        healPicker(Binding(get:{ model.floatingMarqueeOperation?.heal ?? (model.floatingMarqueeOperation == nil ? model.marqueeHeal : .off) },
          set:{ value in
            if model.floatingMarqueeOperation != nil { model.updateMarqueePatch { $0.heal = value == .off ? nil : value } }
            else { model.marqueeHeal = value }
          }))
        Picker("Move Mode",selection:$model.marqueeMoveMode) {
          ForEach(VanishingWorkspace.MarqueeMoveMode.allCases,id:\.self) { mode in Text(mode.rawValue).tag(mode) }
        }.disabled(model.marquee == nil)
          .help("Destination moves the outline. Source fills it from the dragged sampling area.")
        Button("Float Selection") { model.floatMarquee() }.disabled(model.marquee == nil)
          .keyboardShortcut("t",modifiers:[.command,.option])
      }
      if let floating, model.tool == .transform {
        number("Scale (%)",Binding(get:{ model.floatingMarqueeScale ?? 100 },
          set:{ model.resizeMarqueePatch(to:$0) }),1...400)
        number("Rotation (°)",Binding(get:{ model.floatingMarqueeOperation?.angle ?? floating.angle },
          set:{ angle in model.updateMarqueePatch { $0.angle = angle } }),-180...180)
      }
      Button("Deselect") { model.deselectMarquee() }.disabled(model.activeMarquee == nil)
        .keyboardShortcut("d",modifiers:.command)
    }
  }
  var body:some View {
    VStack(spacing:12) {
      HStack {
        Text("Vanishing Point").font(.headline)
        Spacer()
        if model.rendering { ProgressView().controlSize(.small) }
        if model.exportingScene {
          ProgressView().controlSize(.small).accessibilityLabel("Exporting Vanishing Point scene")
          Button("Cancel Export") { model.cancelSceneExport() }
        }
        Menu("Export") {
          Button("Export to 3DS…") { model.presentSceneExport(.studio) }
            .keyboardShortcut("e",modifiers:[.command,.shift])
          Button("Export for After Effects (.vpe)…") { model.presentSceneExport(.afterEffects) }
        }.disabled(!model.canExportScene)
        Toggle("New Layer",isOn:Binding(get:{model.program.newLayer},set:{v in var p=model.program;p.newLayer=v;model.change(p)}))
      }
      HStack(alignment:.top,spacing:16) {
        VStack {
          HStack(spacing:10) {
            Picker("Tool",selection:$model.tool) {
              ForEach(VanishingWorkspace.Tool.allCases,id:\.self) { tool in
                Image(systemName:toolSymbol(tool)).accessibilityLabel(Text(tool.rawValue))
                  .help(tool.rawValue).tag(tool)
              }
            }.pickerStyle(.segmented).labelsHidden()
            Text(model.tool.rawValue).font(.caption).foregroundStyle(.secondary)
              .frame(width:96,alignment:.leading).accessibilityHidden(true)
          }
          VanishingPreview(model:model)
          HStack(spacing: 8) {
            Toggle("Show Grid", isOn: $model.showGrid)
            Spacer()
            if (model.tool == .create || model.tool == .edit) && model.measurementsLinked, let scene = model.scene {
              let root = scene.measurementRoot(for:model.selected)
              let size = model.program.settings.measurementScale(for:root).pixelsPerUnit
              Text("Grid Size: \(size, format: .number.precision(.fractionLength(0...4)))")
                .foregroundStyle(.secondary)
            } else if model.tool == .create || model.tool == .edit {
              LabeledContent("Grid Size") {
                TextField("Grid Size", value: $model.gridSize, format: .number.precision(.fractionLength(0...4)))
                  .labelsHidden().frame(width: 72)
              }
              Slider(value: $model.gridSize, in: VanishingSettings.gridSizeRange) {
                Text("Grid Size")
              } onEditingChanged: { dragging in
                if dragging { model.beginGesture() } else { model.endGesture() }
              }
              .labelsHidden().frame(width: 120)
            }
          }
          .controlSize(.small)
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
          if model.tool == .measure {
            Toggle("Show Measurements", isOn:$model.showMeasurements)
            Toggle("Link Measurements to Grid", isOn:$model.measurementsLinked)
              .disabled(model.program.settings.planes.isEmpty)
            Picker("Measurement", selection:Binding(get:{ model.selectedMeasurement },set:{ model.selectMeasurement($0) })) {
              Text("None").tag(nil as Int?)
              ForEach(model.measurements.indices,id:\.self) { index in
                Text("Measurement \(index+1)").tag(Optional(index))
              }
            }
            if model.selectedMeasurementLength != nil {
              LabeledContent("Length") {
                TextField("Length",value:Binding(get:{ model.selectedMeasurementLength ?? 0 },
                  set:{ model.calibrateMeasurement(length:$0) }),format:.number.precision(.fractionLength(0...4)))
                  .labelsHidden().frame(width:80).id(model.selectedMeasurement)
              }
              Button("Delete Measurement",role:.destructive) { model.removeMeasurement() }
            }
            Button("Measure Plane Dimensions") { model.measurePlaneDimensions(model.selected) }
              .disabled(model.program.settings.planes.isEmpty)
            Text("Drag between two points or double-click a plane to measure both sides.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if model.tool == .marquee || (model.tool == .transform && model.floatingMarqueeOperation != nil) {
            marqueeControls
          }
          if model.tool == .brush || model.tool == .stamp {
            number("Diameter (px)",$model.diameter,1...500);number("Hardness (%)",$model.hardness,0...100);number("Opacity (%)",$model.opacity,0...100)
            healPicker($model.heal)
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
          if let index=model.selectedPaste,pastes.contains(index) {
            Text("Use Transform to drag this item across a plane.").font(.caption).foregroundStyle(.secondary)
            number("Width (plane fraction)",pasteNumber(index,\.width),0.01...2);number("Rotation (°)",pasteNumber(index,\.angle),-180...180);number("Opacity (%)",pasteNumber(index,\.opacity),0...100)
            healPicker(Binding(get: { model.selectedPasteHeal ?? .off }, set: { model.setSelectedPasteHeal($0) }))
            Button("Delete Pasted Item") { var p=model.program;p.operations.remove(at:index);model.selectedPaste=nil;model.change(p) }
          }
          if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
          if let error=model.sceneExportError { Text(error).font(.caption).foregroundStyle(.red) }
          if let message=model.sceneExportMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.frame(width:280).padding(.trailing,5) }.frame(width:295)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview);Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(8,model.zoom*1.5) };Button("Fit") { model.zoom=1;model.pan = .zero }
        Button("Undo") { model.undo() }.disabled(!model.canUndo).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(!model.canRedo).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer()
        Toggle("Render Measurements",isOn:$model.renderMeasurements)
          .disabled(model.measurements.isEmpty)
          .help("Write the measurement marks onto the target layer when you apply Vanishing Point.")
        Button("Cancel") { store.cancelVanishingPoint() }.keyboardShortcut(.cancelAction);Button("OK") { model.endGesture();store.commitVanishingPoint() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
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
  @FocusState private var focused: Bool
  @State private var pointer: CGPoint?
  @State private var measurementDrag: MeasurementDrag?
  @State private var draftMeasurement: VanishingMeasurement?
  @State private var marqueeDrag: VanishingWorkspace.MarqueeDrag?
  @State private var marqueeOutline: VanishingMarquee?

  private enum MeasurementDrag {
    case draw(plane: Int, from: PathPoint, continuing: Bool)
    case edit(VanishingWorkspace.MeasurementTarget, VanishingMeasurement, ToolCursor.MeasurementConstraint)
  }
  var body:some View {
    GeometryReader { geometry in
      let scale=max(0.001,min((geometry.size.width-32)/model.size.width,(geometry.size.height-32)/model.size.height)*model.zoom)
      let offset=CGPoint(x:(geometry.size.width-model.size.width*scale)/2+model.pan.width,y:(geometry.size.height-model.size.height*scale)/2+model.pan.height)
      let scene=model.scene
      let settings=model.program.settings
      let point: (CGPoint) -> PathPoint = { p in .init((p.x-offset.x)/scale,(p.y-offset.y)/scale) }
      Canvas { context,size in
        func screen(_ p:PathPoint)->CGPoint { .init(x:offset.x+p.x*scale,y:offset.y+p.y*scale) }
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        if let image=model.preview ? model.image:model.originalImage { context.draw(Image(decorative:image,scale:1),in:CGRect(x:offset.x,y:offset.y,width:model.size.width*scale,height:model.size.height*scale)) }
        if model.showGrid,let scene {
          for (i,frame) in scene.frames.enumerated() {
            var grid = Path()
            grid.addLines(frame.corners.map(screen))
            grid.closeSubpath()
            let intervals = scene.gridIntervals(for:i,settings:settings)
            func drawLines(length: Double, horizontal: Bool) {
              let count = length / (horizontal ? intervals.y : intervals.x)
              guard count.isFinite, count > 1 else { return }
              // Thin out small projected intervals to bound preview work.
              let stride = max(1, (count / 384).rounded(.up))
              for index in 1...384 {
                let position = Double(index) * stride / count
                guard position < 1 else { break }
                let start = horizontal ? PathPoint(0,position) : PathPoint(position,0)
                let end = horizontal ? PathPoint(1,position) : PathPoint(position,1)
                grid.move(to: screen(frame.point(start)))
                grid.addLine(to: screen(frame.point(end)))
              }
            }
            drawLines(length: frame.width, horizontal: false)
            drawLines(length: frame.height, horizontal: true)
            context.stroke(grid,with:.color(i==model.selected ? .cyan:.blue.opacity(0.6)),lineWidth:i==model.selected ? 1:0.6)
            for p in frame.corners { let q=screen(p);context.fill(Path(ellipseIn:CGRect(x:q.x-4,y:q.y-4,width:8,height:8)),with:.color(i==model.selected ? .cyan:.blue)) }
          }
        }
        if model.showMeasurements, let scene {
          func drawLabel(_ text: Text, at origin: CGPoint) {
            let label = text.font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(.white)
            let resolved = context.resolve(label)
            let extent = resolved.measure(in:size)
            context.fill(Path(roundedRect:CGRect(x:origin.x-extent.width/2-3,y:origin.y-extent.height/2-2,
              width:extent.width+6,height:extent.height+4),cornerRadius:3),with:.color(.black.opacity(0.8)))
            context.draw(resolved,at:origin)
          }
          func drawMeasurement(_ line: VanishingMeasurement, highlighted: Bool, excluding index: Int?) {
            let frame = scene.frames[line.plane]
            let a = screen(frame.point(line.start)), b = screen(frame.point(line.end))
            var length = Path()
            length.move(to:a); length.addLine(to:b)
            let color: Color = highlighted ? .yellow : .white
            context.stroke(length,with:.color(.black.opacity(0.8)),lineWidth:4)
            context.stroke(length,with:.color(color),lineWidth:1.5)
            for p in [a,b] {
              let handle = Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6))
              context.fill(handle,with:.color(color))
              context.stroke(handle,with:.color(.black),lineWidth:1)
            }
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
            if let value = scene.measurementLength(line,settings:settings) {
              drawLabel(Text(value,format:format),at:CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2-13))
            }
            if let angle = scene.measurementAngle(line,settings:settings,excluding:index) {
              let dx = b.x-a.x, dy = b.y-a.y
              let along = min(25/hypot(dx,dy),0.4)
              let origin = CGPoint(x:a.x+dx*along,y:a.y+dy*along+12)
              drawLabel(Text("\(angle, format:format)°"),at:origin)
            }
          }
          let replaced: Int?
          if draftMeasurement != nil, case .edit(let target, _, _) = measurementDrag {
            replaced = target.index
          } else { replaced = nil }
          for (index,line) in model.measurements.enumerated() where index != replaced {
            drawMeasurement(line,highlighted:model.selectedMeasurement == index,excluding:index)
          }
          if let draftMeasurement { drawMeasurement(draftMeasurement,highlighted:true,excluding:replaced) }
          if let pending = model.pendingMeasurement {
            let anchor = screen(pending.point)
            context.fill(Path(ellipseIn:CGRect(x:anchor.x-3,y:anchor.y-3,width:6,height:6)),with:.color(.yellow))
          }
        }
        if let scene {
          func drawMarquee(_ rect: VanishingMarquee, angle: Double, sampling: Bool) {
            guard let corners = rect.projectedCorners(in:scene,angle:angle) else { return }
            var outline = Path()
            outline.addLines(corners.map(screen))
            outline.closeSubpath()
            context.stroke(outline,with:.color(.black),lineWidth:2)
            context.stroke(outline,with:.color(sampling ? .cyan : .white),
              style:StrokeStyle(lineWidth:1,dash:[4,3]))
          }
          let samples = marqueeDrag.map { $0.action == .copy || $0.action == .fill || $0.action == .duplicateFloating } ?? false
          if let selection = model.activeMarquee,marqueeOutline == nil || samples {
            drawMarquee(selection,angle:model.floatingMarqueeOperation?.angle ?? 0,sampling:false)
          }
          if let marqueeOutline {
            drawMarquee(marqueeOutline,angle:marqueeDrag?.angle ?? 0,sampling:samples)
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
        case .edit: return .symbol("arrow.up.and.down.and.arrow.left.and.right")
        case .marquee,.transform:
          if model.tool == .transform,model.floatingMarqueeOperation == nil {
            return .symbol("arrow.up.and.down.and.arrow.left.and.right")
          }
          let action = marqueeDrag?.action ?? pointer.flatMap { pointer in
            scene.flatMap { model.marqueeAction(at:point(pointer),flags:flags,scene:$0) }
          }
          switch action {
          case .draw:
            return .symbol("rectangle.dashed",flags.contains(.shift) ? .constrain : nil)
          case .move,.moveFloating:
            return marqueeDrag == nil ? .openHand : .closedHand
          case .fill:
            return .symbol("scope")
          case .copy,.duplicateFloating:
            return .selectedPixels(copy:true,constrained:flags.contains(.shift),unsnapped:false)
          case nil:
            return pointer == nil && model.tool == .marquee ? .symbol("rectangle.dashed") : .unavailable
          }
        case .create: return .symbol("plus")
        case .measure:
          if case .edit(let target, _, let constraint) = measurementDrag {
            let moving = target == .body(target.index)
            return .vanishingMeasurement(endpoint:moving ? nil : constraint,moving:moving,available:true,active:true)
          }
          if case .draw = measurementDrag {
            return .vanishingMeasurement(endpoint:nil,moving:false,available:true,active:true)
          }
          guard let scene, let pointer else { return .symbol("ruler") }
          let location = point(pointer)
          let target = model.pendingMeasurement == nil
            ? model.measurementTarget(at:location,radius:7/scale,scene:scene) : nil
          let moving = target.map { $0 == .body($0.index) } ?? false
          let endpoint = target != nil && !moving ? ToolCursor.MeasurementConstraint(flags) : nil
          return .vanishingMeasurement(endpoint:endpoint,moving:moving,
            available:model.pendingMeasurement != nil || scene.plane(at:location) != nil,active:false)
        }
      }.contentShape(Rectangle()).focusable().focused($focused)
      .defaultFocus($focused,true)
      .onKeyPress("r") {
        guard !pressed else { return .ignored }
        model.tool = .measure
        return .handled
      }
      .onKeyPress("m") {
        guard !pressed else { return .ignored }
        model.tool = .marquee
        return .handled
      }
      .onKeyPress(keys:[.leftArrow,.rightArrow,.upArrow,.downArrow],phases:[.down,.repeat]) { press in
        guard !pressed,model.activeMarquee != nil,
          model.tool == .marquee || model.tool == .transform,
          press.modifiers.intersection([.command,.control,.option]).isEmpty else { return .ignored }
        let step = press.modifiers.contains(.shift) ? 10.0 : 1.0
        let dx = press.key == .leftArrow ? -step : press.key == .rightArrow ? step : 0
        let dy = press.key == .upArrow ? -step : press.key == .downArrow ? step : 0
        model.nudgeMarquee(dx:dx,dy:dy)
        return .handled
      }
      .onKeyPress(.delete) {
        guard model.tool == .measure else { return .ignored }
        model.removeMeasurement()
        return .handled
      }
      .onChange(of:model.tool) { _, _ in pointer = nil }
      .onContinuousHover { phase in
        guard model.tool == .measure || model.tool == .marquee || model.tool == .transform else { return }
        switch phase { case .active(let position): pointer = position; case .ended: pointer = nil }
      }
      .simultaneousGesture(SpatialTapGesture(count:2).onEnded { value in
        guard let index = scene?.plane(at:point(value.location)) else { return }
        if model.tool == .measure { model.measurePlaneDimensions(index) }
        if model.tool == .marquee { model.selectMarqueePlane(index) }
      })
      .gesture(DragGesture(minimumDistance:0).onChanged { value in
        if !pressed {
          focused=true
          pressed=true;pan=model.pan;stroke=[];hit=nil;corner=nil;sampled=false;pasteOrigin=nil;model.beginGesture()
          let start=point(value.startLocation)
          if let scene,model.tool == .marquee || (model.tool == .transform && model.floatingMarqueeOperation != nil) {
            marqueeDrag = model.startMarqueeDrag(at:start,flags:NSEvent.modifierFlags,scene:scene)
          }
          if model.tool == .measure, let scene {
            if let pending = model.pendingMeasurement {
              measurementDrag = .draw(plane:pending.plane,from:pending.point,continuing:true)
            } else if let target = model.measurementTarget(at:start,radius:7/scale,scene:scene) {
              model.selectMeasurement(target.index)
              measurementDrag = .edit(target,model.measurements[target.index],
                ToolCursor.MeasurementConstraint(NSEvent.modifierFlags))
            } else if let plane = scene.plane(at:start) {
              model.selected = plane
              model.showMeasurements = true
              model.selectMeasurement(nil)
              measurementDrag = .draw(plane:plane,from:start,continuing:false)
            } else {
              model.selectMeasurement(nil)
            }
          }
          if model.tool == .edit,let scene {
            var best=10.0/scale
            for (i,f) in scene.frames.enumerated() where model.program.settings.planes[i].parent==nil { for (j,p) in f.corners.enumerated() { let distance=hypot(p.x-start.x,p.y-start.y);if distance<best { best=distance;hit=i;corner=j } } }
            if hit==nil { hit=scene.plane(at:start) };if let hit { model.selected=hit }
          }
          if model.tool == .stamp && NSEvent.modifierFlags.contains(.option) { model.setSource(start);sampled=true }
          if model.tool == .transform,let index=model.selectedPaste,model.program.operations.indices.contains(index),let scene { let op=model.program.operations[index];pasteOrigin=scene.frames[op.plane].point(op.at) }
        }
        let p=point(value.location)
        if let scene,let marqueeDrag {
          marqueeOutline = model.projectedMarquee(for:marqueeDrag,to:p,
            constrained:NSEvent.modifierFlags.contains(.shift),scene:scene)
          return
        }
        switch model.tool {
        case .hand:model.pan=CGSize(width:pan.width+value.translation.width,height:pan.height+value.translation.height)
        case .edit:if let hit { if let corner { model.moveCorner(hit,corner,to:p) } else { model.movePlane(hit,dx:value.translation.width/scale,dy:value.translation.height/scale) } }
        case .brush,.stamp:if !sampled,stroke.last.map({hypot($0.x-p.x,$0.y-p.y)>1}) ?? true { if stroke.count<4096 { stroke.append(p) } }
        case .transform:if let pasteOrigin { model.movePaste(to:.init(pasteOrigin.x+value.translation.width/scale,pasteOrigin.y+value.translation.height/scale)) }
        case .measure:
          if let scene {
            switch measurementDrag {
            case .draw(let plane, let start, _):
              draftMeasurement = scene.measurement(plane:plane,from:start,to:p)
            case .edit(let target, let original, let constraint):
              draftMeasurement = model.editedMeasurement(original,target:target,
                from:point(value.startLocation),to:p,constraint:constraint,scene:scene)
            case nil: break
            }
          }
        case .create,.marquee:break
        }
      }.onEnded { value in
        if let scene,let marqueeDrag,hypot(value.translation.width,value.translation.height) > 2,
          let rect = model.projectedMarquee(for:marqueeDrag,to:point(value.location),
            constrained:NSEvent.modifierFlags.contains(.shift),scene:scene) {
          model.finishMarqueeDrag(marqueeDrag,at:rect)
        }
        marqueeDrag = nil
        marqueeOutline = nil
        if model.tool == .create { model.addPoint(.init((value.location.x-offset.x)/scale,(value.location.y-offset.y)/scale)) }
        if (model.tool == .brush || model.tool == .stamp) && !sampled { model.stroke(stroke) }
        if model.tool == .measure, let measurementDrag {
          let end = point(value.location)
          switch measurementDrag {
          case .draw(let plane, let start, let continuing):
            if hypot(end.x-start.x,end.y-start.y) * scale > 2,
              let measurement = scene?.measurement(plane:plane,from:start,to:end) {
              model.updateMeasurement(measurement)
              model.pendingMeasurement = nil
            } else if !continuing && abs(value.translation.width)+abs(value.translation.height) <= 2 {
              model.pendingMeasurement = (plane,start)
            }
          case .edit(let target, let original, let constraint):
            if abs(value.translation.width)+abs(value.translation.height) > 0, let scene,
              let measurement = model.editedMeasurement(original,target:target,
                from:point(value.startLocation),to:end,constraint:constraint,scene:scene) {
              model.updateMeasurement(measurement,at:target.index)
            }
          }
        }
        measurementDrag=nil;draftMeasurement=nil
        model.endGesture();pressed=false;stroke=[];hit=nil;corner=nil;pasteOrigin=nil
      }).clipped().accessibilityLabel("Vanishing Point preview")
        .accessibilityValue(model.activeMarquee == nil ? "No perspective selection" :
          model.floatingMarqueeOperation == nil ? "Perspective selection" : "Floating perspective selection")
    }
  }
}
