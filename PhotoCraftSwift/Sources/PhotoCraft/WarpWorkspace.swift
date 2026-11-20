import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

enum CylinderHandle: CaseIterable {
  case topRight, bottomLeft, topRim, bottomRim, wrap, body

  func point(on cylinder: CylinderWarp) -> PathPoint? {
    switch self {
    case .topRight: .init(cylinder.right, cylinder.top)
    case .bottomLeft: .init(cylinder.left, cylinder.bottom)
    case .topRim: cylinder.surface.point(0.5, 0)
    case .bottomRim: cylinder.surface.point(0.5, 1)
    case .wrap:
      .init(cylinder.left + cylinder.halfWidth * (1.2 + 0.65 * cylinder.wrap), (cylinder.top + cylinder.bottom) / 2)
    case .body: nil
    }
  }

}

@MainActor @Observable final class WarpWorkspace: Identifiable {
  let id=UUID(),source:CraftDocument,layer:Layer,width:Int,height:Int
  let sourceSession:UUID?,sourceLifecycle:UUID?
  var settings:WarpDefinition
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var showGuides=true
  var rendering=false
  var error:String?
  var edit:WarpEdit?
  var selectedPoint:Int?
  var splitPosition=0.5
  var undoStates=[WarpDefinition]()
  var redoStates=[WarpDefinition]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var generation=0
  private var closed=false
  private var gestureStart:WarpDefinition?
  init(source:CraftDocument,layer:Layer,session:UUID?=nil,lifecycle:UUID?=nil) {
    self.source=source;self.layer=layer;sourceSession=session;sourceLifecycle=lifecycle;settings=layer.warp ?? WarpDefinition()
    if case .raster(let p)=layer.content { width=p.width;height=p.height } else { width=1;height=1 }
  }
  var ready:Bool { edit != nil && !rendering && !closed && error == nil }
  var controls:WarpMesh? {
    guard settings.cylinder == nil else { return nil }
    return settings.mesh ?? (try? settings.custom(width:width,height:height).mesh)
  }
  func guidePoint(_ s: Double, _ t: Double) -> PathPoint {
    let w = Double(width), h = Double(height)
    let bounds = settings.sourceBounds
    return settings.point((bounds?.x ?? 0) + s * (bounds?.width ?? w),
                          (bounds?.y ?? 0) + t * (bounds?.height ?? h), width: w, height: h)
  }
  func change(_ value:WarpDefinition,remember:Bool=true) {
    guard !closed else{return}
    do { try value.validate() } catch { self.error=error.localizedDescription;return }
    guard value != settings else { return }
    if remember { rememberUndo(settings) };settings=value;refresh()
  }
  private func rememberUndo(_ value:WarpDefinition) { undoStates.append(value);if undoStates.count>100 { undoStates.removeFirst() };redoStates.removeAll() }
  func undo() { endGesture();guard let previous=undoStates.popLast() else { return };redoStates.append(settings);change(previous,remember:false) }
  func redo() { endGesture();guard let next=redoStates.popLast() else { return };undoStates.append(settings);change(next,remember:false) }
  func beginGesture() { if gestureStart == nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { rememberUndo(before) };gestureStart=nil }
  func choose(_ style:WarpStyle) {
    guard style != settings.style else { return }
    do { var value=settings;value.style=style;value.mesh=nil;value.cylinder=nil
      if style == .custom { value=try settings.custom(width:width,height:height) }
      else if style == .cylinder {
        let frame = settings.sourceBounds ?? .init(x: 0, y: 0, width: Double(width), height: Double(height))
        value.bend = 0; value.horizontalDistortion = 0; value.verticalDistortion = 0; value.vertical = false
        value.cylinder = .init(left: frame.x, bottom: frame.y + frame.height, right: frame.x + frame.width,
                               top: frame.y, topDepth: 0.5, bottomDepth: 0.5, wrap: 0.15)
      }
      else if style != .none && value.bend == 0 { value.bend=50 }
      selectedPoint=nil;change(value)
    } catch { self.error=error.localizedDescription }
  }
  func grid(_ count:Int) {
    guard settings.cylinder == nil else { return }
    do { selectedPoint=nil;change(try settings.custom(width:width,height:height,columns:count,rows:count)) }
    catch { self.error=error.localizedDescription }
  }
  func dragCylinder(_ handle: CylinderHandle, from start: PathPoint, to point: PathPoint, constrain: Bool) {
    beginGesture()
    guard var value = gestureStart, var cylinder = value.cylinder else { return }
    let dx = point.x - start.x, dy = point.y - start.y
    let height = cylinder.bottom - cylinder.top, width = cylinder.right - cylinder.left
    switch handle {
    case .topRight, .bottomLeft:
      let sign = handle == .topRight ? 1.0 : -1.0
      var w = max(0.01, width + sign * dx), h = max(0.01, height - sign * dy)
      if constrain {
        let factor = (w - width) * width + (h - height) * height
        let scale = max(0.01 / min(width, height), 1 + factor / (width * width + height * height))
        w = width * scale; h = height * scale
      }
      if handle == .topRight { cylinder.right = cylinder.left + w; cylinder.top = cylinder.bottom - h }
      else { cylinder.left = cylinder.right - w; cylinder.bottom = cylinder.top + h }
    case .topRim:
      let delta = dy / cylinder.halfWidth
      cylinder.topDepth += delta; cylinder.bottomDepth += delta
    case .bottomRim:
      cylinder.bottomDepth += dy / cylinder.halfWidth
    case .wrap:
      cylinder.wrap = max(0, min(1, cylinder.wrap + dx / (0.65 * cylinder.halfWidth)))
    case .body:
      cylinder.left += dx; cylinder.right += dx; cylinder.top += dy; cylinder.bottom += dy
    }
    guard (try? cylinder.validate()) != nil else { return }
    value.cylinder = cylinder
    change(value, remember: false)
  }
  func drag(_ index:Int,to point:PathPoint) {
    do { beginGesture();var value=settings
      if value.mesh == nil { value=try value.custom(width:width,height:height) }
      guard value.mesh!.points.indices.contains(index) else { return }
      value.mesh!.points[index]=point;selectedPoint=index;change(value,remember:false)
    } catch { self.error=error.localizedDescription }
  }
  func split(vertical:Bool,cross:Bool=false) {
    guard settings.cylinder == nil else { return }
    do { var value=settings.mesh == nil ? try settings.custom(width:width,height:height):settings
      try value.mesh!.split(at:splitPosition,vertical:vertical)
      if cross { try value.mesh!.split(at:splitPosition,vertical:!vertical) };selectedPoint=nil;change(value)
    } catch { self.error=error.localizedDescription }
  }
  func remove(vertical:Bool) {
    do { guard var mesh=settings.mesh else { return }
      let knots=vertical ? mesh.us:mesh.vs
      guard knots.count>2 else { throw CraftError.invalid("There are no interior splits in this direction.") }
      let index=(1..<(knots.count-1)).min(by:{abs(knots[$0]-splitPosition)<abs(knots[$1]-splitPosition)})!
      try mesh.removeSplit(index:index,vertical:vertical);var value=settings;value.mesh=mesh;selectedPoint=nil;change(value)
    } catch { self.error=error.localizedDescription }
  }
  func refresh() {
    guard !closed else{return}
    task?.cancel();edit=nil;error=nil;rendering=true;generation += 1
    let token=generation,source=source,layerID=layer.id,value=settings,needOriginal=originalImage == nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (WarpEdit,CGImage,CGImage?) in
          let edit=try SmartObjectIO.prepareWarp(source,layerID:layerID,warp:value)
          let bounds=try RasterPreviewRequest.overview(width:source.width,height:source.height)
          return (edit,try ColorManagement.displayImage(bounds.reducing(Renderer.composite(edit.result)),in:source),needOriginal ? try ColorManagement.displayImage(bounds.reducing(Renderer.composite(source)),in:source):nil)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.edit=result.0;self.image=result.1;if let before=result.2 { self.originalImage=before };self.rendering=false
      } catch { guard let self,!self.closed,self.generation == token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation += 1;task?.cancel();task=nil;rendering=false }
}

struct WarpSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:WarpWorkspace
  func amount(_ key:WritableKeyPath<WarpDefinition,Double>)->Binding<Double> {
    Binding(get:{model.settings[keyPath:key]},set:{ n in var value=model.settings;value[keyPath:key]=n;model.change(value,remember:false) })
  }
  func cylinderAmount(_ key: WritableKeyPath<CylinderWarp, Double>) -> Binding<Double> {
    Binding(get: { model.settings.cylinder?[keyPath: key] ?? 0 }, set: { n in
      var value = model.settings
      value.cylinder?[keyPath: key] = n
      model.change(value, remember: true)
    })
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack { Text("Warp").font(.headline);Spacer();Text(model.layer.name).foregroundStyle(.secondary) }
      HStack(alignment:.top,spacing:18) {
        WarpPreview(model:model).frame(minWidth:460,minHeight:400)
        VStack(alignment:.leading,spacing:10) {
          Picker("Warp",selection:Binding(get:{model.settings.style},set:{model.choose($0)})) { ForEach(WarpStyle.allCases,id:\.self) { Text($0.title).tag($0) } }
          if model.settings.cylinder != nil {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
              ForEach([("Top curvature", \CylinderWarp.topDepth), ("Bottom curvature", \CylinderWarp.bottomDepth),
                       ("Perspective", \CylinderWarp.wrap)], id: \.0) { title, key in
                GridRow {
                  Text(title)
                  TextField(title, value: cylinderAmount(key), format: .percent.precision(.fractionLength(0...2)))
                    .labelsHidden().frame(width: 72)
                }
              }
            }
            DisclosureGroup("Cylinder bounds") {
              Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach([("Left", \CylinderWarp.left), ("Top", \CylinderWarp.top),
                         ("Right", \CylinderWarp.right), ("Bottom", \CylinderWarp.bottom)], id: \.0) { title, key in
                  GridRow {
                    Text(title)
                    TextField(title, value: cylinderAmount(key), format: .number.precision(.fractionLength(0...3)))
                      .labelsHidden().frame(width: 84)
                  }
                }
              }
            }
          } else {
            ForEach([("Bend",\WarpDefinition.bend),("Horizontal",\WarpDefinition.horizontalDistortion),("Vertical",\WarpDefinition.verticalDistortion)],id:\.0) { label,key in
              HStack { Text(label);Spacer();Text(model.settings[keyPath:key].formatted(.number.precision(.fractionLength(0)))+"%") }
              Slider(value:amount(key),in:-100...100,onEditingChanged:{ if $0 { model.beginGesture() } else { model.endGesture() } }).disabled(model.settings.style == .custom || model.settings.style == .none)
            }
            Toggle("Vertical orientation",isOn:Binding(get:{model.settings.vertical},set:{n in var value=model.settings;value.vertical=n;model.change(value)})).disabled(model.settings.style == .custom)
            Menu("Grid") { ForEach([1,3,4,5],id:\.self) { n in Button(n == 1 ? "Default":"\(n) × \(n)") { model.grid(n) } } }
            HStack { Text("Split at");TextField("Position",value:$model.splitPosition,format:.percent).frame(width:65) }
            HStack { Button("Horizontal") { model.split(vertical:false) };Button("Vertical") { model.split(vertical:true) } }.font(.caption)
            HStack { Button("Remove H") { model.remove(vertical:false) }.disabled((model.settings.mesh?.vs.count ?? 0)<=2);Button("Remove V") { model.remove(vertical:true) }.disabled((model.settings.mesh?.us.count ?? 0)<=2) }.font(.caption)
          }
          Picker("Interpolation",selection:Binding(get:{model.settings.interpolation},set:{n in var value=model.settings;value.interpolation=n;model.change(value)})) { ForEach(Resampling.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
          Toggle("Show Guides",isOn:$model.showGuides);Toggle("Preview",isOn:$model.preview)
          Text(model.settings.cylinder == nil
               ? "Drag the control points to reshape. Smart Objects retain their original pixels."
               : "Drag the corners to resize. Hold Shift to keep the proportions.")
            .font(.caption).foregroundStyle(.secondary)
        }.frame(width:260)
      }
      if let error=model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Button("Reset") { model.change(WarpDefinition()) };Spacer()
        if model.rendering { ProgressView().controlSize(.small) }
        Button("Cancel") { store.cancelWarp() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitWarp() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:820,height:610).task { if model.edit == nil && !model.rendering { model.refresh() } }.onDisappear { model.close() }
  }
}
struct WarpPreview:View {
  @Bindable var model:WarpWorkspace
  @State private var dragged:Int?
  @State private var cylinderDrag: CylinderHandle?
  @State private var hoverCylinderHandle: CylinderHandle?

  private func cylinderHit(_ location: CGPoint, cylinder: CylinderWarp,
                           project: (PathPoint) -> CGPoint?) -> CylinderHandle? {
    let handles = CylinderHandle.allCases.compactMap { handle -> (CylinderHandle, Double)? in
      guard let control = handle.point(on: cylinder), let point = project(control) else { return nil }
      let distance = hypot(point.x - location.x, point.y - location.y)
      return distance <= 12 ? (handle, distance) : nil
    }
    if let nearest = handles.min(by: { $0.1 < $1.1 }) { return nearest.0 }
    let shape = cylinder.surface
    let domain = shape.lastVisibleU - shape.firstVisibleU
    let columns = (0...24).map { shape.firstVisibleU + domain * Double($0) / 24 }
    let outline = columns.map { shape.point($0, 0) } + columns.reversed().map { shape.point($0, 1) }
    let points = outline.compactMap(project)
    guard points.count == outline.count, let first = points.first else { return nil }
    let path = Path { path in
      path.move(to: first)
      path.addLines(Array(points.dropFirst()))
      path.closeSubpath()
    }
    return path.contains(location) ? .body : nil
  }

  private struct PreviewCoordinates {
    let origin: CGPoint
    let scale: Double
    let transform: Transform2D
    let projection: ProjectiveTransform?

    init(size: CGSize, source: CraftDocument, layer: Layer) {
      let padding = 40.0
      scale = min((size.width - padding * 2) / Double(source.width),
                  (size.height - padding * 2) / Double(source.height))
      origin = CGPoint(x: (size.width - Double(source.width) * scale) / 2,
                       y: (size.height - Double(source.height) * scale) / 2)
      transform = Transform2D.translation(origin.x, origin.y) * .scale(scale, scale) * layer.coordinateTransform
      projection = layer.sourceProjection
    }

    func display(_ point: PathPoint) -> CGPoint? {
      var local = point
      if let projection {
        guard let mapped = try? projection.point(point.x, point.y) else { return nil }
        local = mapped
      }
      let transformed = transform.point(local.x, local.y)
      return CGPoint(x: transformed.x, y: transformed.y)
    }

    func source(_ location: CGPoint) -> PathPoint? {
      guard let inverse = try? transform.inverted() else { return nil }
      let point = inverse.point(location.x, location.y)
      if let projection { return try? projection.inverted().point(point.x, point.y) }
      return PathPoint(point.x, point.y)
    }
  }

  var body: some View {
    GeometryReader { geometry in preview(size: geometry.size) }
  }

  private func preview(size: CGSize) -> some View {
    let coordinates = PreviewCoordinates(size: size, source: model.source, layer: model.layer)
    let cylinder = model.settings.cylinder
    let mesh = model.controls
    let canvas = Canvas { context, size in
      paint(context, size: size, coordinates: coordinates, cylinder: cylinder, mesh: mesh)
    }
    return canvas.contentShape(Rectangle())
      .gesture(dragGesture(coordinates: coordinates, cylinder: cylinder, mesh: mesh))
      .onContinuousHover { phase in
        if case .active(let location) = phase, let cylinder, model.showGuides {
          hoverCylinderHandle = cylinderHit(location, cylinder: cylinder, project: coordinates.display)
        } else {
          hoverCylinderHandle = nil
        }
      }
      .toolCursor { flags in
        guard cylinder != nil, model.showGuides else { return .arrow }
        return ToolCursor.cylinderWarp(cylinderDrag ?? hoverCylinderHandle, dragging: cylinderDrag != nil, flags: flags)
      }
      .accessibilityLabel(cylinder == nil
                          ? "Warp preview. Drag a control point to reshape the image."
                          : "Cylinder preview. Adjust the curvature, perspective or bounds using the controls.")
  }

  private func paint(_ context: GraphicsContext, size: CGSize, coordinates: PreviewCoordinates,
                     cylinder: CylinderWarp?, mesh: WarpMesh?) {
    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
    if let image = model.preview ? model.image : model.originalImage {
      let canvas = CGRect(origin: coordinates.origin, size: CGSize(width: Double(model.source.width) * coordinates.scale,
                                                                   height: Double(model.source.height) * coordinates.scale))
      context.draw(Image(decorative: image, scale: 1), in: canvas)
    }
    guard model.showGuides, mesh != nil || cylinder != nil else { return }
    let shape = cylinder?.surface
    let guideFractions = (0...6).map { Double($0) / 6 }
    var path = Path()
    for vertical in [true, false] {
      let knots = shape != nil ? [0, 0.5, 1] : model.settings.mesh.map { vertical ? $0.us : $0.vs } ?? guideFractions
      for fixed in knots {
        var beginsLine = true
        for n in 0...64 {
          let varying = Double(n) / 64
          let u = vertical ? fixed : varying, v = vertical ? varying : fixed
          let control = shape.map { $0.point($0.firstVisibleU + u * ($0.lastVisibleU - $0.firstVisibleU), v) }
            ?? model.guidePoint(u, v)
          guard let point = coordinates.display(control) else { beginsLine = true; continue }
          if beginsLine { path.move(to: point); beginsLine = false } else { path.addLine(to: point) }
        }
      }
    }
    context.stroke(path, with: .color(.cyan.opacity(0.75)), lineWidth: 1)
    for (index, control) in (mesh?.points ?? []).enumerated() {
      guard let point = coordinates.display(control) else { continue }
      let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
      context.fill(Path(ellipseIn: rect), with: .color(index == model.selectedPoint ? .orange : .white))
    }
    if let cylinder {
      for handle in CylinderHandle.allCases {
        guard let control = handle.point(on: cylinder), let point = coordinates.display(control) else { continue }
        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        let knob = handle == .topRight || handle == .bottomLeft ? Path(rect) : Path(ellipseIn: rect)
        context.fill(knob, with: .color(handle == cylinderDrag ? .orange : .white))
        context.stroke(knob, with: .color(.black.opacity(0.8)), lineWidth: 1)
      }
    }
  }

  private func dragGesture(coordinates: PreviewCoordinates, cylinder: CylinderWarp?, mesh: WarpMesh?) -> some Gesture {
    DragGesture(minimumDistance: 0).onChanged { value in
      guard model.showGuides else { return }
      if let cylinder {
        if cylinderDrag == nil {
          cylinderDrag = cylinderHit(value.startLocation, cylinder: cylinder, project: coordinates.display)
        }
        applyCylinderDrag(value, coordinates: coordinates)
        return
      }
      guard let mesh else { return }
      if dragged == nil {
        let candidates = mesh.points.enumerated().compactMap { index, control -> (Int, Double)? in
          guard let point = coordinates.display(control) else { return nil }
          let distance = hypot(point.x - value.startLocation.x, point.y - value.startLocation.y)
          return distance <= 16 ? (index, distance) : nil
        }
        dragged = candidates.min { $0.1 < $1.1 }?.0
      }
      if let index = dragged, let control = coordinates.source(value.location) { model.drag(index, to: control) }
    }.onEnded { value in
      if model.showGuides { applyCylinderDrag(value, coordinates: coordinates) }
      model.endGesture(); dragged = nil; cylinderDrag = nil
      hoverCylinderHandle = model.settings.cylinder.flatMap {
        cylinderHit(value.location, cylinder: $0, project: coordinates.display)
      }
    }
  }

  private func applyCylinderDrag(_ value: DragGesture.Value, coordinates: PreviewCoordinates) {
    guard let handle = cylinderDrag, let start = coordinates.source(value.startLocation),
          let end = coordinates.source(value.location) else { return }
    let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    model.dragCylinder(handle, from: start, to: end, constrain: ToolCursor.cylinderConstrained(handle, flags: flags))
  }
}
extension EditorStore {
  var canBeginWarp:Bool { !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingMask && !editingComponent && document.activeLayerID.map{(try? WarpEdit.target(document,layerID:$0)) != nil} == true }
  func beginWarp() { guard canBeginWarp,let id=document.activeLayerID,let layer=try? WarpEdit.target(document,layerID:id) else { return };warpDraft=WarpWorkspace(source:document,layer:layer,session:sessionGeneration,lifecycle:layerPanelGeneration) }
  func cancelWarp() { warpDraft?.close();warpDraft=nil }
  func commitWarp() { guard let draft=warpDraft,draft.ready,let edit=draft.edit else { return }
    guard draft.sourceSession==sessionGeneration,draft.sourceLifecycle==layerPanelGeneration,draft.source==document else{draft.error="The Warp source changed. Cancel and preview again.";return}
    cancelWarp();performGeometry(.warp(edit))
  }
}
extension AppDelegate { @objc func warpLayer() { store?.beginWarp() } }
