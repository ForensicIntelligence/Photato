import Foundation

/// Portable layer references, independent of document UUIDs.
public enum ActionLayerTarget: Codable, Equatable, Sendable {
  case active
  case named(String, occurrence: Int)

  public init(_ id: UUID, in document: CraftDocument, preferActive: Bool = true) {
    if preferActive && id == document.activeLayerID { self = .active; return }
    guard let index = document.layers.firstIndex(where: { $0.id == id }) else {
      self = .named("", occurrence: -1); return
    }
    let name = document.layers[index].name
    self = .named(name, occurrence: document.layers[..<index].filter { $0.name == name }.count)
  }
  public func resolve(in document: CraftDocument) throws -> UUID {
    switch self {
    case .active:
      guard let id = document.activeLayerID else { throw CraftError.invalid("The action requires an active layer.") }; return id
    case .named(let name, let occurrence):
      let matches = document.layers.filter { $0.name == name }
      guard matches.indices.contains(occurrence) else { throw CraftError.invalid("Action layer ‘\(name)’ was not found.") }
      return matches[occurrence].id
    }
  }
}

/// Native action format. Unsupported recording entries remain visible and block playback.
/// This is deliberately not an Adobe .atn file or a Photoshop JavaScript program.
public enum ActionOperation: Codable, Sendable {
  case smartFilterTransfer(RecordedSmartFilterTransfer)
  case canvasEdges(CanvasEdgeOperation, Pixel)
  case flattenImage
  case layerStyles(RecordedStyleEdit)
  case globalLight(GlobalLight)
  indirect case retouch(RecordedRetouchStroke)
  case documentMode(DocumentModeRequest)
  case restrictedMode(RestrictedModeRequest)
  case inkMode(InkModeRequest)
  case clipboardCopy([ActionLayerTarget], merged: Bool)
  case clipboardCut([ActionLayerTarget], background: Pixel?)
  case clipboardPaste(PastePlacement, center: PathPoint?)
  indirect case toneAdjustment(ActionLayerTarget?,ClassicToneSettings)
  indirect case proceduralRender(ActionLayerTarget?,ProceduralRenderSettings,Bool,VectorPath?)
  indirect case createShape(String,ShapeDefinition,Transform2D,[RasterPattern])
  indirect case setShape(ActionLayerTarget,ShapeDefinition,[RasterPattern])
  indirect case appendShape(ActionLayerTarget,ShapeComponent)
  indirect case editType(ActionLayerTarget,TextContent,PathPoint,imported:Bool)
  indirect case selectionCoverage(SelectionMask?,SelectionMode)
  indirect case adjustmentBrush(RecordedAdjustmentBrush)
  indirect case replaceAdjustment(ActionLayerTarget,Adjustment)
  indirect case gradientFill(ActionLayerTarget,GradientFill)
  indirect case createGradientFill(RecordedGradientFill)
  indirect case paintGradient(RecordedGradientStroke)
  case unsupported(String)
  case select(ActionLayerTarget)
  case deselectLayers
  case newLayer(NewPixelLayerOptions, below: Bool)
  case newGroup(NewLayerGroupOptions, children: [ActionLayerTarget], below: Bool)
  case addContent(String, LayerContent)
  case delete([ActionLayerTarget])
  case duplicate([ActionLayerTarget], name: String?)
  case merge([ActionLayerTarget], LayerMergeOperation)
  case rename(ActionLayerTarget, String)
  case visibility(ActionLayerTarget, Bool)
  case lock(ActionLayerTarget, Bool)
  case opacity(ActionLayerTarget, Float)
  case blend(ActionLayerTarget, BlendMode)
  case move(ActionLayerTarget, Int, Int)
  case clipping(ActionLayerTarget, Bool)
  case group([ActionLayerTarget], String)
  case ungroup(ActionLayerTarget)
  case createMask(ActionLayerTarget, LayerMaskCreation)
  case applyMask(ActionLayerTarget)
  case deleteMask(ActionLayerTarget)
  case maskProperties(ActionLayerTarget, MaskProperties)
  case maskFill(ActionLayerTarget, Float)
  case invertMask(ActionLayerTarget)
  case selection(IntRect?)
  case selectShape(SelectionShape, SelectionMode, Bool, Double)
  case invertSelection
  case featherSelection(Double)
  case stroke(ActionLayerTarget, [StrokePoint], Brush, mask: Bool)
  case clear(ActionLayerTarget)
  case fill(ActionLayerTarget, Pixel)
  case style([ActionLayerTarget], LayerStyle?)
  case filters(ActionLayerTarget, SmartFilterStack?)
  case filter(ActionLayerTarget, RasterFilter)
  indirect case blurGalleryMask(ActionLayerTarget,BlurGallerySettings,Int?,Float,BlendMode)
  case adjustment(ActionLayerTarget, Adjustment)
  case desaturate(ActionLayerTarget)
  case autoCorrection(ActionLayerTarget, AutoCorrection)
  case crop(IntRect)
  case flip(ActionLayerTarget, Bool)
  case transform(ActionLayerTarget, Transform2D, Resampling)
  case stackLayers([ActionLayerTarget],LayerStackOperation)
  case moveLayers([ActionLayerTarget],Int,Int,Bool)
  case layerLinks(String,[ActionLayerTarget],Bool?)
  case pixelPaint(PixelPaintKind,ActionPixelPaintTarget,PixelPaintSettings)
  case patternPixelPaint(ActionPixelPaintTarget,RasterPattern,PatternPlacement,PixelPaintSettings)
  indirect case pathPixelPaint(ActionLayerTarget,SelectionMask,PixelPaintSettings,RasterPattern?,PatternPlacement?,Bool)
  case projectLayers([ActionLayerTarget],ProjectiveTransform,Resampling)
  case transformLayers([ActionLayerTarget],Transform2D,Resampling)
  case transformChannel(ActionChannelTarget,ProjectiveTransform,Resampling,Float,Bool)
  case transformPixelMask(ActionLayerTarget,ProjectiveTransform,Resampling)
  case transformPixels(ActionLayerTarget,ProjectiveTransform,Resampling)
  case transformBackgroundPixels(ActionLayerTarget,ProjectiveTransform,Resampling,Pixel)
  case transformCopyPixels(ActionLayerTarget,ProjectiveTransform,Resampling,Pixel?)
  case movePixels(ActionLayerTarget,Double,Double,Bool,Bool,Pixel?)
  case backgroundLayer(BackgroundLayerAction)
  case canvasSize(Int, Int, CanvasAnchor, Pixel?)
  case imageSize(Int, Int, Double, Resampling)
  case fitImage(FitImageOptions)
  case replaceText(RecordedTextReplacement)
  case resolution(Double)
  case rotate(CanvasTurn)

  public var unsupportedReason: String? { if case .unsupported(let reason) = self { return reason }; return nil }
  public init(recording command: Command, in d: CraftDocument) {
    func target(_ id: UUID) -> ActionLayerTarget { .init(id, in: d) }
    func targets(_ ids: Set<UUID>) -> [ActionLayerTarget] { d.layers.filter { ids.contains($0.id) }.map { target($0.id) } }
    func shapePatterns(_ definition:ShapeDefinition,_ supplied:[RasterPattern])->[RasterPattern]{
      let ids=Set([definition.fill.pattern?.patternID,definition.stroke.paint.pattern?.patternID].compactMap{$0})
      return ids.sorted().compactMap{id in supplied.first{$0.id==id} ?? d.pattern(id)}
    }
    switch command {
    case .preparedAction(let edit):self = edit.recording ?? .unsupported("\(command.label) is not yet recordable. Remove or disable this step before playback.")
    case .canvasEdges(let edit):self = .canvasEdges(edit.operation,edit.background)
    case .flattenImage:self = .flattenImage
    case .layerStyles(let edit):self = .layerStyles(RecordedStyleEdit(edit,in:d))
    case .globalLight(let value):self = .globalLight(value)
    case .cloneStamp, .healingBrush, .spotHealing, .toning, .focus:
      self = RecordedRetouchStroke(recording: command, in: d).map(Self.retouch)
        ?? .unsupported("This retouch sample has no portable source provenance.")
    case .documentMode(let request): self = .documentMode(.init(request))
    case .preparedColorProfile(let edit): self = .unsupported("\(edit.title) semantic Action recording is not yet available.")
    case .preparedDocumentMode(let edit): self = edit.recording ?? .unsupported("\(edit.title) has no semantic recording settings.")
    case .cut(let ids, let background): self = .clipboardCut(targets(Set(ids)), background: background)
    case .paste(_, let placement, let center): self = .clipboardPaste(placement, center: center)
    case .toneAdjustment(let request):self = .toneAdjustment((request.layerID ?? d.activeLayerID).map(target),request.settings)
    case .linkedSmartObject:self = .unsupported("Linked source actions require an authorized source recipe; semantic recording is not yet qualified.")
    case .guides:self = .unsupported("Guide identity/selection Actions recording is not yet qualified. Guides remain editable and save natively.")
    case .channelArithmetic:self = .unsupported("Apply Image and Calculations semantic source recording is not yet qualified. The committed pixels/channels remain editable and save natively.")
    case .hdrToning:self = .unsupported("HDR Toning needs the full compositor; semantic Actions playback is not implemented yet.")
    case .proceduralRender(let request):
      self = .proceduralRender((request.layerID ?? d.activeLayerID).map(target),request.settings,request.newLayer,request.settings.kind == .flame ? ProceduralRenderEngine.resolvedPath(request,in:d):nil)
    case .importedType(let edit):self = .editType(target(edit.layerID),edit.content,edit.origin,imported:true)
    case .editType(let id,let content,let origin):self = .editType(target(id),content,origin,imported:false)
    case .shape(let edit):
      switch edit {case .create(let name,let definition,let placement,let patterns):self = .createShape(name,definition,placement,shapePatterns(definition,patterns));case .configure(let id,let definition,let patterns):self = .setShape(target(id),definition,shapePatterns(definition,patterns));case .append(let id,let component):self = .appendShape(target(id),component)}
    case .maskAllObjects: self = .unsupported("Mask All Objects is not yet recordable. The generated masks remain editable and save with the document.")
    case .focusArea(let edit):
      if edit.output == .selection{self = .selectionCoverage(edit.mask,.replace)}else{self = .unsupported("Focus Area mask/layer output is not yet recordable. Use selection output and a separate mask action.")}
    case .adjustmentBrush(let request):self = .adjustmentBrush(.init(request,in:d))
    case .replaceContent(let id, .adjustment(let value)):self = .replaceAdjustment(target(id),value)
    case .setGradientFill(let id, let fill): self = .gradientFill(target(id), fill)
    case .addGradientFill(let layer,let mask):
      self = RecordedGradientFill(layer:layer,maskFromSelection:mask,in:d).map(Self.createGradientFill)
        ?? .unsupported("This Gradient Fill creation template contains metadata not supported by portable recording.")
    case .paintGradient(let id,let stroke):self = .paintGradient(.init(layerID:id,stroke:stroke,in:d))
    case .newPixelLayer(let v, let below): self = .newLayer(v, below: below)
    case .newGroup(let v, let children, let below): self = .newGroup(v, children: children.map(target), below: below)
    case .addLayer(let layer) where layer.smartObject?.linkedSource != nil:
      self = .unsupported("Linked placement actions require an authorized source recipe; semantic recording is not yet qualified.")
    case .addLayer(let layer):
      if case .adjustment(.classic(let value))=layer.content,value.kind == .exposure {
        guard var expected=try? value.layer(in:d,name:layer.name) else {self = .unsupported("Invalid Exposure settings.");return}
        expected.id=layer.id
        guard expected==layer else {self = .unsupported("Exposure creation metadata is not recordable.");return}
        self = .addContent(layer.name,layer.content);return
      }
      var standard = Layer(name: layer.name, content: layer.content); standard.id = layer.id
      guard standard == layer else { self = .unsupported("Adding content with placement or layer metadata is not yet recordable."); return }
      switch layer.content {
      case .adjustment, .text, .shape: self = .addContent(layer.name, layer.content)
      default: self = .unsupported("Adding existing pixel content is not recordable. Use New Layer or import it before playback.")
      }
    case .deleteLayer(let id): self = .delete([target(id)])
    case .deleteLayers(let ids): self = .delete(targets(ids))
    case .duplicateLayer(let id): self = .duplicate([target(id)], name: nil)
    case .duplicateLayers(let ids, let name): self = .duplicate(targets(ids), name: name)
    case .mergeLayers(let ids, let op): self = .merge(targets(ids), op)
    case .preparedLayerMerge(let edit): self = .merge(targets(edit.layerIDs),edit.operation)
    case .renameLayer(let id, let v): self = .rename(target(id), v)
    case .visibility(let id, let v): self = .visibility(target(id), v)
    case .lock(let id, let v): self = .lock(target(id), v)
    case .opacity(let id, let v): self = .opacity(target(id), v)
    case .blend(let id, let v): self = .blend(target(id), v)
    case .move(let id, let x, let y):
      let layer = d.layers.first { $0.id == id }; self = .move(target(id), x - (layer?.x ?? 0), y - (layer?.y ?? 0))
    case .clipping(let id, let v): self = .clipping(target(id), v)
    case .groupLayers(let ids, let name): self = .group(ids.map(target), name)
    case .ungroup(let id): self = .ungroup(target(id))
    case .createMask(let id, let v): self = .createMask(target(id), v)
    case .applyMask(let id): self = .applyMask(target(id))
    case .deleteMask(let id): self = .deleteMask(target(id))
    case .maskProperties(let id, let v): self = .maskProperties(target(id), v)
    case .maskFill(let id, let v): self = .maskFill(target(id), v)
    case .invertMask(let id): self = .invertMask(target(id))
    case .selection(let v): self = .selection(v)
    case .selectShape(let shape, let mode, let aa, let feather): self = .selectShape(shape, mode, aa, feather)
    case .magneticSelection(let mask,let mode):self = .selectionCoverage(mask,mode)
    case .modifiedSelection(let mask,_),.reselectedSelection(let mask),.transformedSelection(let mask):self = .selectionCoverage(mask,.replace)
    case .colorRange(let mask):self = .selectionCoverage(mask,.replace)
    case .selectionCoverage(let mask,let mode):self = .selectionCoverage(mask,mode)
    case .invertSelection: self = .invertSelection
    case .featherSelection(let v): self = .featherSelection(v)
    case .stroke(let id, let points, let brush): self = .stroke(target(id), points, brush, mask: false)
    case .maskStroke(let id, let points, let brush): self = .stroke(target(id), points, brush, mask: true)
    case .clear(let id): self = .clear(target(id))
    case .fill(let id, let v): self = .fill(target(id), v)
    case .layerStyle(let ids, let v): self = .style(targets(ids), v)
    case .smartFilters(let id, let v): self = .filters(target(id), v)
    case .applyFilter(let id, let v): self = .filter(target(id), v)
    case .maskFilter: self = .unsupported("Mask filtering is not yet recordable. Remove or disable this step before playback.")
    case .blurGalleryMask(let edit):
      let index=edit.filterID.flatMap{id in d.layers.first{$0.id==edit.layerID}?.smartFilters?.filters.firstIndex{$0.id==id}}
      self = .blurGalleryMask(target(edit.layerID),edit.settings,index,edit.opacity,edit.blendMode)
    case .applyAdjustment(let id, let v): self = .adjustment(target(id), v)
    case .desaturate(let id): self = .desaturate(target(id))
    case .autoCorrection(let id, let v): self = .autoCorrection(target(id), v)
    case .crop(let v): self = .crop(v)
    case .flip(let id, let v): self = .flip(target(id), v)
    case .transform(let id, let matrix, let method): self = .transform(target(id), matrix, method)
    case .movePixels(let request):self = .movePixels(target(request.layerID),request.dx,request.dy,request.copy,request.constrain,request.backgroundColor)
    case .stackLayers(let request): self = .stackLayers(request.layerIDs.map(target), request.operation)
    case .moveLayers(let request):self = .moveLayers(request.layerIDs.map(target),request.dx,request.dy,request.copy == true)
    case .pixelPaint(let request):
      if let coverage=request.pathCoverage,case .layer(let id)=request.target{self = .pathPixelPaint(.init(id,in:d),coverage,request.settings,request.pattern,request.patternPlacement,request.pathClear == true)}
      else if let pattern=request.pattern{self = .patternPixelPaint(.init(request.target,in:d),pattern,request.patternPlacement ?? .init(),request.settings)}else{self = .pixelPaint(request.kind,.init(request.target,in:d),request.settings)}
    case .layerLinks(let command):switch command{case .link(let ids):self = .layerLinks("link",ids.map(target),nil);case .unlink(let ids):self = .layerLinks("unlink",ids.map(target),nil);case .enabled(let ids,let value):self = .layerLinks("enabled",ids.map(target),value)}
    case .transformLayers(let request):if let matrix=request.projection{self = .projectLayers(request.layerIDs.map(target),matrix,request.interpolation)}else{self = .transformLayers(request.layerIDs.map(target),request.matrix,request.interpolation)}
    case .transformChannel(let request):self = .transformChannel(.init(request.target,in:d),request.matrix,request.interpolation,request.backgroundValue,request.copy)
    case .transformPixelMask(let request):self = .transformPixelMask(target(request.layerID),request.matrix,request.interpolation)
    case .transformPixels(let request):
      if request.copy == true {self = .transformCopyPixels(target(request.layerID),request.matrix,request.interpolation,request.backgroundColor)}else if d.layers.first(where:{$0.id==request.layerID})?.isBackground == true {self = .transformBackgroundPixels(target(request.layerID),request.matrix,request.interpolation,request.backgroundColor ?? .white)}else{self = .transformPixels(target(request.layerID),request.matrix,request.interpolation)}
    case .backgroundLayer(let edit):self = .backgroundLayer(.init(edit,in:d))
    case .canvasSize(let w, let h, let anchor, let fill): self = .canvasSize(w, h, anchor, fill)
    case .imageSize(let w, let h, let dpi, let method): self = .imageSize(w, h, dpi, method)
    case .fitImage(let options): self = .fitImage(options)
    case .resolution(let v): self = .resolution(v)
    case .rotateCanvas(let v): self = .rotate(v)
    default: self = .unsupported("\(command.label) is not yet recordable. Remove or disable this step before playback.")
    }
  }

  public func command(in d: CraftDocument) throws -> Command? {
    func id(_ target: ActionLayerTarget) throws -> UUID { try target.resolve(in: d) }
    func ids(_ targets: [ActionLayerTarget]) throws -> Set<UUID> { try Set(targets.map(id)) }
    switch self {
    case .smartFilterTransfer(let request): return try request.command(in: d)
    case .layerStyles(let edit):return .layerStyles(try edit.resolved(in:d))
    case .globalLight(let value):return .globalLight(value)
    case .replaceText:throw CraftError.unsupported("Text replacement Actions require native shaping playback.")
    case .canvasEdges:
      throw CraftError.unsupported("Canvas edge Actions require native compositor playback.")
    case .flattenImage:
      throw CraftError.unsupported("Flatten Image Actions require the native compositor.")
    case .retouch:
      throw CraftError.unsupported("Retouch Actions require compositor sampling playback.")
    case .documentMode, .restrictedMode, .inkMode, .clipboardCopy, .clipboardCut, .clipboardPaste:
      throw CraftError.unsupported("This action requires compositor/clipboard playback.")
    case .toneAdjustment(let target,let settings):return .toneAdjustment(.init(settings,layerID:try target.map(id)))
    case .proceduralRender(let target,let settings,let newLayer,let path):return .proceduralRender(.init(settings,layerID:try target.map(id),newLayer:newLayer,path:path))
    case .createShape(let name,let definition,let placement,let patterns):return .shape(.create(name,definition,placement,patterns:patterns))
    case .editType(let target,let text,let origin,let imported):
      let layerID=try id(target);return imported ? .importedType(.init(layerID:layerID,content:text,origin:origin)):.editType(layerID,text,originDelta:origin)
    case .setShape(let target,let definition,let patterns):return .shape(.configure(try id(target),definition,patterns:patterns))
    case .appendShape(let target,let component):return .shape(.append(try id(target),component))
    case .adjustmentBrush(let value):return try value.command(in:d)
    case .createGradientFill(let recipe):return try recipe.command(in:d)
    case .paintGradient(let recipe):return try recipe.command(in:d)
    case .gradientFill(let target, let fill):
      let layerID = try id(target)
      guard let layer = d.layers.first(where: { $0.id == layerID }),
        case .gradientFill = layer.content, !d.isLocked(layerID)
      else { throw CraftError.invalid("Recorded Gradient Fill needs an unlocked Gradient Fill layer.") }
      try fill.validate()
      return .setGradientFill(layerID, fill)
    case .replaceAdjustment(let target,let value):
      let layerID=try id(target)
      guard let layer=d.layers.first(where:{$0.id==layerID}),case .adjustment=layer.content else{throw CraftError.invalid("Recorded adjustment replacement needs an adjustment layer.")}
      return .replaceContent(layerID,.adjustment(value))
    case .unsupported(let reason): throw CraftError.unsupported(reason)
    case .select, .deselectLayers: return nil
    case .newLayer(let v, let below): return .newPixelLayer(v, below: below)
    case .newGroup(let v, let children, let below): return .newGroup(v, children: try children.map(id), below: below)
    case .addContent(let name, let content):
      if case .adjustment(.classic(let value))=content,value.kind == .exposure {return .addLayer(try value.layer(in:d,name:name))}
      if case .adjustment(.modern(let value))=content {return .addLayer(try value.layer(in:d,name:name))}
      switch content { case .adjustment, .text, .shape: return .addLayer(Layer(name: name, content: content)); default: throw CraftError.unsupported("Only adjustment, text and shape content can be added by an action.") }
    case .delete(let t): return .deleteLayers(try ids(t))
    case .duplicate(let t, let name): return .duplicateLayers(try ids(t), name: name)
    case .merge(let t, let op): return .mergeLayers(try ids(t), op)
    case .rename(let t, let v): return .renameLayer(try id(t), v)
    case .visibility(let t, let v): return .visibility(try id(t), v)
    case .lock(let t, let v): return .lock(try id(t), v)
    case .opacity(let t, let v): return .opacity(try id(t), v)
    case .blend(let t, let v): return .blend(try id(t), v)
    case .move(let t, let x, let y):
      let layerID = try id(t), layer = d.layers.first { $0.id == layerID }!
      let (dx, ox) = layer.x.addingReportingOverflow(x), (dy, oy) = layer.y.addingReportingOverflow(y)
      guard !ox, !oy else { throw CraftError.invalid("Action movement is out of range.") }
      return .move(layerID, dx, dy)
    case .clipping(let t, let v): return .clipping(try id(t), v)
    case .group(let t, let v): return .groupLayers(try t.map(id), v)
    case .ungroup(let t): return .ungroup(try id(t))
    case .createMask(let t, let v): return .createMask(try id(t), v)
    case .applyMask(let t): return .applyMask(try id(t))
    case .deleteMask(let t): return .deleteMask(try id(t))
    case .maskProperties(let t, let v): return .maskProperties(try id(t), v)
    case .maskFill(let t, let v): return .maskFill(try id(t), v)
    case .invertMask(let t): return .invertMask(try id(t))
    case .selection(let v): return .selection(v)
    case .selectShape(let s, let m, let aa, let f): return .selectShape(s, m, aa, f)
    case .selectionCoverage(let mask,let mode):return .selectionCoverage(mask,mode)
    case .invertSelection: return .invertSelection
    case .featherSelection(let v): return .featherSelection(v)
    case .stroke(let t, let p, let b, let mask): return mask ? .maskStroke(try id(t), p, b) : .stroke(try id(t), p, b)
    case .clear(let t): return .clear(try id(t))
    case .fill(let t, let v): return .fill(try id(t), v)
    case .style(let t, let v): return .layerStyle(try ids(t), v)
    case .filters(let t, let v): return .smartFilters(try id(t), v)
    case .filter(let t, let v): return .applyFilter(try id(t), v)
    case .blurGalleryMask(let target,let settings,let index,let opacity,let mode):
      let layerID=try id(target)
      var filterID:UUID?
      if let index {
        guard let filters=d.layers.first(where:{$0.id==layerID})?.smartFilters?.filters,filters.indices.contains(index),filters[index].filter.kind == .blurGallery else {throw CraftError.invalid("The recorded Blur Gallery filter index is unavailable.")}
        filterID=filters[index].id
      }
      return .blurGalleryMask(.init(layerID:layerID,settings:settings,filterID:filterID,opacity:opacity,blendMode:mode))
    case .adjustment(let t, let v): return .applyAdjustment(try id(t), v)
    case .desaturate(let t): return .desaturate(try id(t))
    case .autoCorrection(let t, let v): return .autoCorrection(try id(t), v)
    case .crop(let v): return .crop(v)
    case .flip(let t, let v): return .flip(try id(t), v)
    case .transform(let t, let m, let r): return .transform(try id(t), m, r)
    case .stackLayers(let targets, let operation): return .stackLayers(.init(layerIDs: try targets.map(id), operation: operation))
    case .moveLayers(let targets,let dx,let dy,let copy):return .moveLayers(.init(layerIDs:try targets.map(id),dx:dx,dy:dy,copy:copy))
    case .pathPixelPaint(let target,let coverage,let settings,let pattern,let placement,let clear):
      var request=PixelPaintRequest(.fill,target:.layer(try target.resolve(in:d)),settings:settings,pattern:pattern,placement:placement)
      request.pathCoverage=coverage;request.pathClear=clear;return .pixelPaint(request)
    case .patternPixelPaint(let target,let pattern,let placement,let settings):return .pixelPaint(.init(.fill,target:try target.resolve(in:d),settings:settings,pattern:pattern,placement:placement))
    case .pixelPaint(let kind,let target,let settings):return .pixelPaint(.init(kind,target:try target.resolve(in:d),settings:settings))
    case .layerLinks(let operation,let targets,let value):let ids=try targets.map(id);switch operation{case "link":return .layerLinks(.link(ids));case "unlink":return .layerLinks(.unlink(ids));case "enabled":guard let value else{throw CraftError.invalid("Missing recorded link participation.")};return .layerLinks(.enabled(ids,value));default:throw CraftError.invalid("Unknown recorded layer-link operation.")}
    case .projectLayers(let targets,let matrix,let method):return .transformLayers(.init(layerIDs:try targets.map(id),projection:matrix,interpolation:method))
    case .transformLayers(let targets,let matrix,let method):return .transformLayers(.init(layerIDs:try targets.map(id),matrix:matrix,interpolation:method))
    case .transformChannel(let t,let m,let r,let background,let copy):return .transformChannel(.init(target:try t.resolve(in:d),matrix:m,interpolation:r,backgroundValue:background,copy:copy))
    case .transformPixelMask(let t,let m,let r):return .transformPixelMask(.init(layerID:try id(t),matrix:m,interpolation:r))
    case .transformPixels(let t,let m,let r):return .transformPixels(.init(layerID:try id(t),matrix:m,interpolation:r))
    case .transformBackgroundPixels(let t,let m,let r,let color):return .transformPixels(.init(layerID:try id(t),matrix:m,interpolation:r,backgroundColor:color))
    case .transformCopyPixels(let t,let m,let r,let color):return .transformPixels(.init(layerID:try id(t),matrix:m,interpolation:r,backgroundColor:color,copy:true))
    case .movePixels(let t,let x,let y,let copy,let constrain,let color):return .movePixels(.init(layerID:try id(t),dx:x,dy:y,copy:copy,constrain:constrain,backgroundColor:color))
    case .backgroundLayer(let edit):return .backgroundLayer(try edit.edit(in:d))
    case .canvasSize(let w, let h, let a, let f): return .canvasSize(w, h, a, f)
    case .imageSize(let w, let h, let dpi, let r): return .imageSize(w, h, dpi, r)
    case .fitImage(let options): return .fitImage(options)
    case .resolution(let v): return .resolution(v)
    case .rotate(let v): return .rotateCanvas(v)
    }
  }
}

public struct RecordedActionStep: Codable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var enabled: Bool
  public var operation: ActionOperation
  public init(name: String, operation: ActionOperation, enabled: Bool = true) {
    id = UUID(); self.name = name; self.operation = operation; self.enabled = enabled
  }
}
public struct RecordedAction: Codable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var set: String
  public var steps: [RecordedActionStep]
  public init(name: String, set: String = "My Actions", steps: [RecordedActionStep] = []) {
    id = UUID(); self.name = name; self.set = set; self.steps = steps
  }
  public func validate() throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !set.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf8.count <= 256, set.utf8.count <= 256, steps.count <= 512,
      Set(steps.map(\.id)).count == steps.count,
      steps.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 1024 }) else {
      throw CraftError.invalid("Invalid action name, set or steps (maximum 512).")
    }
    for step in steps {
      if case .blurGalleryMask(_,let settings,let index,let opacity,_)=step.operation {
        try settings.validate()
        guard opacity.isFinite,(0...1).contains(opacity),index == nil || index!>=0 else {throw CraftError.invalid("Invalid recorded Blur Gallery output.")}
      }
      if case .stackLayers(let targets, _) = step.operation { guard !targets.isEmpty, targets.count <= LayerLimits.maximumLayers else { throw CraftError.invalid("Invalid recorded layer arrangement targets.") } }
      if case .pathPixelPaint(_,let coverage,let settings,let pattern,let placement,_) = step.operation{try settings.validate(.fill);_ = try coverage.coverageSurface();if let pattern{try pattern.validate()};try placement?.validate()}
      if case .fitImage(let options) = step.operation { try options.validate() }
      if case .replaceText(let request) = step.operation { try request.validate() }
      if case .layerStyles(let edit)=step.operation {try edit.validate()}
      if case .globalLight(let value)=step.operation {try value.validate()}
      if case .retouch(let request) = step.operation { try request.validate() }
      if case .documentMode(let request) = step.operation { _ = try DocumentModeDescriptor(mode: request.conversion.mode, depth: request.conversion.depth, profile: request.conversion.profile, intent: request.conversion.intent) }
      if case .restrictedMode(let request) = step.operation { try request.validate() }
      if case .inkMode(let request) = step.operation { try request.validate() }
      if case .clipboardPaste(_, let center) = step.operation, let center {
        guard center.x.isFinite, center.y.isFinite, abs(center.x) <= 1_000_000, abs(center.y) <= 1_000_000 else { throw CraftError.invalid("Invalid recorded paste center.") }
      }
      if case .clipboardCut(_, let background) = step.operation, let background {
        guard [background.r, background.g, background.b].allSatisfy({$0.isFinite && (0...1).contains($0)}), background.a == 1 else { throw CraftError.invalid("Invalid recorded Cut background.") }
      }
      if case .toneAdjustment(_,let settings)=step.operation {try settings.validate();guard settings.kind != .hdrToning else{throw CraftError.unsupported("HDR Toning Actions require full compositor playback.")}}
      if case .proceduralRender(_,let settings,let newLayer,let path)=step.operation {
        try ProceduralRenderRequest(settings,newLayer:newLayer,path:path).validate()
        if settings.kind == .flame && path == nil {throw CraftError.invalid("Recorded Flame requires retained path geometry.")}
      }
      if case .adjustmentBrush(let value)=step.operation {try value.request.validate()}
      if case .replaceAdjustment(_,let value)=step.operation {try value.validate()}
      if case .gradientFill(_, let fill) = step.operation { try fill.validate() }
      if case .createGradientFill(let recipe)=step.operation{try recipe.validate()}
      if case .paintGradient(let recipe)=step.operation{try recipe.validate()}
      if case .adjustment(_,let value)=step.operation {try value.validate()}
      if case .editType(_,let text,let origin,_)=step.operation {try text.validate();guard origin.x.isFinite,origin.y.isFinite,abs(origin.x)<=1_000_000,abs(origin.y)<=1_000_000 else{throw CraftError.invalid("Invalid recorded type origin.")}}
      if case .addContent(_, .adjustment(.hueSaturation(let value)))=step.operation {try value.validate()}
      if case .addContent(_, .adjustment(.source(let value)))=step.operation {try value.validate()}
      if case .addContent(_, .adjustment(.modern(let value)))=step.operation {try value.validate()}
    }
    for step in steps { if case .stroke(_,let points,let brush,_) = step.operation { try BrushPainter.validate(brush,points:points) } }
  }
  public var requiresInitialClipboard: Bool {
    for step in steps where step.enabled {
      switch step.operation { case .clipboardPaste: return true; case .clipboardCopy, .clipboardCut: return false; default: break }
    }
    return false
  }
  public var isLayerSelectionOnly: Bool {
    let enabled = steps.filter(\.enabled)
    return !enabled.isEmpty && enabled.allSatisfy {
      switch $0.operation { case .select, .deselectLayers: true; default: false }
    }
  }
  /// Resolve only layer targets; never scan or rasterize the retained source pixels.
  /// The original document is unchanged if any later target is invalid.
  public func layerSelection(in source: CraftDocument) throws -> UUID? {
    try validate()
    guard isLayerSelectionOnly else { throw CraftError.invalid("Choose a layer-selection-only action.") }
    var view = source
    for (index, step) in steps.enumerated() where step.enabled {
      try Task.checkCancellation()
      do {
        switch step.operation {
        case .select(let target):
          let id = try target.resolve(in: view)
          guard source.layers.contains(where: { $0.id == id }) else { throw CraftError.invalid("Layer selection target no longer exists.") }
          view.activeLayerID = id
        case .deselectLayers: view.activeLayerID = nil
        default: throw CraftError.invalid("The action contains a document edit.")
        }
      } catch is CancellationError { throw CancellationError() }
      catch { throw CraftError.invalid("Action ‘\(name)’, step \(index + 1) (\(step.name)): \(error.localizedDescription)") }
    }
    return view.activeLayerID
  }
  public var writesClipboard: Bool { steps.contains { step in
    guard step.enabled else { return false }
    switch step.operation { case .clipboardCopy, .clipboardCut: return true; default: return false }
  } }
  public var usesMasterPalette: Bool { steps.contains { if $0.enabled, case .restrictedMode(let request) = $0.operation { return request.usesMasterPalette }; return false } }
  public var usesExternalRetouchSources: Bool {
    steps.contains { if $0.enabled, case .retouch(let request) = $0.operation { return request.needsExternalSources }; return false }
  }
  public func apply(to document: inout CraftDocument,
    resolve: ((ActionOperation, inout CraftDocument) throws -> Bool)? = nil,
    validate: @Sendable (CraftDocument) throws -> Void = { _ in }) throws {
    try self.validate()
    guard steps.contains(where: \.enabled) else { throw CraftError.invalid("This action has no enabled steps.") }
    var result = document
    for (index, step) in steps.enumerated() where step.enabled {
      try Task.checkCancellation()
      do {
        if case .select(let target) = step.operation { result.activeLayerID = try target.resolve(in: result) }
        else if case .deselectLayers = step.operation { result.activeLayerID = nil }
        else if try resolve?(step.operation, &result) != true, let command = try step.operation.command(in: result) { try command.apply(to: &result) }
        try result.validate()
        try validate(result)
      } catch is CancellationError { throw CancellationError() }
      catch { throw CraftError.invalid("Action ‘\(name)’, step \(index + 1) (\(step.name)): \(error.localizedDescription)") }
    }
    document = result
  }
}

public struct ActionRecording: Sendable {
  public var action: RecordedAction
  struct Group: Sendable { let historyID: UUID; var steps: [RecordedActionStep] }
  var groups: [Group] = []
  var undone: [Group] = []
  var pending: [RecordedActionStep] = []
  public var snapshot: RecordedAction { var value = action; value.steps = groups.flatMap(\.steps) + pending; return value }
  mutating func append(_ step: RecordedActionStep, historyID: UUID) {
    // A visible blocking entry is retained if recording exceeds the bounded format.
    guard snapshot.steps.count < 511 else {
      if snapshot.steps.count == 511 { pending.append(.init(name: "Recording limit", operation: .unsupported("Recording exceeded 511 steps. Split this action."))) }; return
    }
    if groups.last?.historyID == historyID { groups[groups.count - 1].steps += pending + [step] }
    else { groups.append(.init(historyID: historyID, steps: pending + [step])) }
    pending = []; undone = []
  }
  mutating func navigate(historyID: UUID, redo: Bool) {
    pending = []
    if redo, undone.last?.historyID == historyID { groups.append(undone.removeLast()) }
    else if !redo, groups.last?.historyID == historyID { undone.append(groups.removeLast()) }
  }
}

public struct ActionPlaybackLimits: Sendable {
  public let maximumPixels: Int
  public let maximumLayers: Int
  public let maximumBytes: Int
  public init(maximumPixels: Int, maximumLayers: Int, maximumBytes: Int) {
    self.maximumPixels = maximumPixels; self.maximumLayers = maximumLayers; self.maximumBytes = maximumBytes
  }
  public func validate(_ document: CraftDocument) throws {
    guard document.width * document.height <= maximumPixels, document.layers.count <= maximumLayers, document.estimatedBytes <= maximumBytes else { throw CraftError.invalid("An action step exceeds the playback resource limits.") }
  }
}
