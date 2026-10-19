import Foundation

public enum Command: Sendable {
  case addLayer(Layer)
  case newPixelLayer(NewPixelLayerOptions, below: Bool = false)
  case newGroup(NewLayerGroupOptions, children: [UUID] = [], below: Bool = false)
  case addGradientFill(Layer, Bool = false)
  case setGradientFill(UUID, GradientFill)
  case addPatternFill(Layer, RasterPattern, Bool = false)
  case setPatternFill(UUID, PatternFill, RasterPattern?)
  case paste(ClipboardContent, PastePlacement, PathPoint?)
  case cut([UUID])
  case layerVia(UUID, LayerViaOperation)
  case mergeLayers(Set<UUID>, LayerMergeOperation)
  case deleteLayer(UUID)
  case deleteLayers(Set<UUID>)
  case duplicateLayer(UUID)
  case duplicateLayers(Set<UUID>, name: String? = nil)
  case duplicateLayersFrom(CraftDocument, Set<UUID>, name: String? = nil)
  case renameLayer(UUID, String)
  case layerColor(Set<UUID>, LayerColorLabel)
  case layerVisibility([UUID: Bool])
  case visibility(UUID, Bool)
  case lock(UUID, Bool)
  case opacity(UUID, Float)
  case blend(UUID, BlendMode)
  case move(UUID, Int, Int)
  case layoutLayers([LayerTranslation], LayerLayoutOperation)
  case reorder(UUID, Int)
  case relocate(UUID, UUID?, Int)
  case groupLayers([UUID], String)
  case ungroup(UUID)
  case groupProperties(UUID, GroupContent)
  case clipping(UUID, Bool)
  case blendClippedAsGroup(UUID, Bool)
  case replaceContent(UUID, LayerContent)
  case rasterize(UUID, Surface)
  case mask(UUID, Surface?)
  case createMask(UUID, LayerMaskCreation)
  case applyMask(UUID)
  case deleteMask(UUID)
  case maskProperties(UUID, MaskProperties)
  case vectorMask(UUID, VectorMask?)
  case savePath(NamedPath)
  case deletePath(UUID)
  case selection(IntRect?)
  case selectShape(SelectionShape, SelectionMode, Bool, Double)
  case selectionCoverage(SelectionMask?, SelectionMode)
  case magicWand(CloneSample, PathPoint, ColorMatchOptions, SelectionMode, Bool)
  case paintBucket(UUID, BucketFill)
  case paintGradient(UUID, GradientStroke)
  case invertSelection
  case featherSelection(Double)
  case healingBrush(UUID, HealingStroke)
  case focus(UUID, FocusStroke)
  case toning(UUID, ToningStroke)
  case spotHealing(UUID, SpotHealingStroke)
  case cloneStamp(UUID, CloneStroke)
  case stroke(UUID, [StrokePoint], Brush)
  case maskStroke(UUID, [StrokePoint], Brush)
  case maskFill(UUID, Float)
  case invertMask(UUID)
  case clear(UUID)
  case fill(UUID, Pixel)
  case fillComponents(UUID, RGBComponentFill)
  case applyAdjustment(UUID, Adjustment)
  case desaturate(UUID)
  case autoCorrection(UUID, AutoCorrection)
  case crop(IntRect)
  case flip(UUID, Bool)
  case transform(UUID, Transform2D, Resampling)
  case canvasSize(Int, Int, CanvasAnchor, Pixel?)
  case imageSize(Int, Int, Double, Resampling)
  case resolution(Double)
  case rotateCanvas(CanvasTurn)
  public var label: String {
    switch self {
    case .addLayer, .newPixelLayer: "New Layer"
    case .newGroup(_, let children, _): children.isEmpty ? "New Group" : "Group Layers"
    case .addGradientFill: "New Gradient Fill Layer"
    case .setGradientFill: "Gradient Fill"
    case .addPatternFill: "New Pattern Fill Layer"
    case .setPatternFill: "Pattern Fill"
    case .paste(_, let placement, _):
      placement == .into
        ? "Paste Into"
        : placement == .outside
          ? "Paste Outside" : placement == .inPlace ? "Paste in Place" : "Paste"
    case .cut: "Cut"
    case .layerVia(_, let operation): operation.rawValue
    case .mergeLayers(_, let operation): operation.rawValue
    case .deleteLayer: "Delete Layer"
    case .deleteLayers(let ids): ids.count == 1 ? "Delete Layer" : "Delete Layers"
    case .duplicateLayer: "Duplicate Layer"
    case .duplicateLayers(let ids, _), .duplicateLayersFrom(_, let ids, _):
      ids.count == 1 ? "Duplicate Layer" : "Duplicate Layers"
    case .renameLayer: "Rename Layer"
    case .layerColor: "Layer Color"
    case .visibility, .layerVisibility: "Layer Visibility"
    case .lock: "Lock Layer"
    case .opacity: "Layer Opacity"
    case .blend: "Blend Mode"
    case .move: "Move Layer"
    case .layoutLayers(_, let operation): operation.label
    case .reorder, .relocate: "Arrange Layer"
    case .groupLayers: "Group Layers"
    case .ungroup: "Ungroup Layers"
    case .groupProperties: "Group Properties"
    case .clipping(_, let value): value ? "Create Clipping Mask" : "Release Clipping Mask"
    case .blendClippedAsGroup: "Blend Clipped Layers As Group"
    case .replaceContent(_, .adjustment(.levels)): "Levels"
    case .replaceContent(_, .adjustment(.curves)): "Curves"
    case .replaceContent(_, .adjustment(.hueSaturation)): "Hue/Saturation"
    case .replaceContent(_, .adjustment(.colorBalance)): "Color Balance"
    case .replaceContent: "Edit Layer"
    case .rasterize: "Rasterize Layer"
    case .mask: "Layer Mask"
    case .createMask(_, let kind):
      kind == .fromTransparency ? "From Transparency" : "Add Layer Mask"
    case .applyMask: "Apply Layer Mask"
    case .deleteMask: "Delete Layer Mask"
    case .maskProperties: "Mask Properties"
    case .vectorMask: "Vector Mask"
    case .savePath: "Edit Path"
    case .deletePath: "Delete Path"
    case .selection, .selectShape, .selectionCoverage: "Selection"
    case .magicWand: "Magic Wand"
    case .paintBucket: "Paint Bucket"
    case .paintGradient: "Gradient"
    case .invertSelection: "Inverse Selection"
    case .featherSelection: "Feather Selection"
    case .healingBrush: "Healing Brush"
    case .focus(_, let stroke): stroke.tool.rawValue + " Tool"
    case .toning(_, let stroke): stroke.tool.rawValue + " Tool"
    case .spotHealing: "Spot Healing Brush"
    case .cloneStamp: "Clone Stamp"
    case .stroke(_, _, let b): b.erase ? "Eraser" : "Brush"
    case .maskStroke: "Brush on Layer Mask"
    case .maskFill: "Fill Layer Mask"
    case .invertMask: "Invert Layer Mask"
    case .clear: "Clear"
    case .fill, .fillComponents: "Fill"
    case .applyAdjustment(_, .levels): "Levels"
    case .applyAdjustment(_, .curves): "Curves"
    case .applyAdjustment(_, .hueSaturation): "Hue/Saturation"
    case .applyAdjustment(_, .colorBalance): "Color Balance"
    case .applyAdjustment(_, .gradientMap): "Gradient Map"
    case .applyAdjustment(_, .tonalSteps(let settings)): settings.kind.rawValue
    case .desaturate: "Desaturate"
    case .autoCorrection(_, let kind): kind.rawValue
    case .applyAdjustment: "Adjustment"
    case .crop: "Crop"
    case .flip: "Flip Layer"
    case .transform: "Free Transform"
    case .canvasSize: "Canvas Size"
    case .imageSize: "Image Size"
    case .resolution: "Image Resolution"
    case .rotateCanvas: "Image Rotation"
    }
  }
  public func apply(to d: inout CraftDocument) throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      return s
    }
    switch self {
    case .paste(let content, let placement, let center):
      try content.paste(into: &d, placement: placement, center: center)
    case .layerVia(let id, let operation):
      try LayerVia.apply(operation, layerID: id, to: &d)
    case .mergeLayers(let ids, let operation):
      try LayerMerge.apply(operation, layerIDs: ids, to: &d)
    case .cut(let requested):
      let ids = Set(requested)
      guard !ids.isEmpty, ids.allSatisfy({ id in d.layers.contains { $0.id == id } }) else {
        throw CraftError.invalid("Select a layer to cut.")
      }
      if d.selection != nil {
        guard ids.count == 1, let id = ids.first else {
          throw CraftError.unsupported("Cut a pixel selection from one layer at a time.")
        }
        let i = try index(id)
        var pixels = try raster(i)
        let transform = d.layers[i].coordinateTransform
        for y in 0..<pixels.height {
          try Task.checkCancellation()
          for x in 0..<pixels.width {
            let point = transform.point(Double(x) + 0.5, Double(y) + 0.5)
            let coverage = d.selectionCoverage(x: Int(floor(point.x)), y: Int(floor(point.y)))
            if coverage > 0 {
              var value = pixels.pixel(x: x, y: y)
              value.a *= 1 - coverage
              pixels.setPixel(x: x, y: y, value)
            }
          }
        }
        d.layers[i].content = .raster(pixels)
      } else {
        let removed = ids.reduce(into: Set<UUID>()) { $0.formUnion(d.subtreeIDs($1)) }
        guard removed.allSatisfy({ !d.isLocked($0) }) else {
          throw CraftError.invalid("Unlock the selected layers and groups before cutting.")
        }
        d.layers.removeAll { removed.contains($0.id) }
        d.activeLayerID = d.layers.last?.id
      }
    case .addGradientFill(var layer, let createMask):
      guard case .gradientFill(let fill) = layer.content else {
        throw CraftError.invalid("Expected a gradient fill layer.")
      }
      try fill.validate()
      if createMask {
        layer = try layer.creatingPixelMask(
          d.selection == nil ? .revealAll : .revealSelection, in: d)
      }
      try Command.addLayer(layer).apply(to: &d)
    case .setGradientFill(let id, let fill):
      let i = try index(id)
      guard case .gradientFill = d.layers[i].content else {
        throw CraftError.invalid("Select a gradient fill layer.")
      }
      try fill.validate()
      d.layers[i].content = .gradientFill(fill)
    case .addPatternFill(var layer, let pattern, let createMask):
      guard case .patternFill(var fill) = layer.content else {
        throw CraftError.invalid("Expected a pattern fill layer.")
      }
      fill.patternID = try d.installPattern(pattern)
      layer.content = .patternFill(fill)
      if createMask {
        layer = try layer.creatingPixelMask(
          d.selection == nil ? .revealAll : .revealSelection, in: d)
      }
      try Command.addLayer(layer).apply(to: &d)
    case .setPatternFill(let id, var fill, let pattern):
      let i = try index(id)
      guard case .patternFill = d.layers[i].content else {
        throw CraftError.invalid("Select a pattern fill layer.")
      }
      if let pattern { fill.patternID = try d.installPattern(pattern) }
      d.layers[i].content = .patternFill(fill)
    case .addLayer(let layer):
      try d.insertNewLayer(layer)
    case .newPixelLayer(let options, let below):
      try d.insertNewLayer(options.layer(in: d), below: below)
    case .deleteLayers(let ids):
      try LayerDeletion.apply(to: &d, selected: ids)
    case .deleteLayer(let id):
      let i = try index(id)
      let ids = d.subtreeIDs(id)
      d.layers.removeAll { ids.contains($0.id) }
      d.activeLayerID = d.layers.isEmpty ? nil : d.layers[min(i, d.layers.count - 1)].id
    case .duplicateLayer(let id):
      try LayerDuplication.duplicate(in: &d, selected: [id], name: nil)
    case .duplicateLayers(let ids, let name):
      try LayerDuplication.duplicate(in: &d, selected: ids, name: name)
    case .duplicateLayersFrom(let source, let ids, let name):
      try LayerDuplication.transfer(from: source, selected: ids, name: name, into: &d)
    case .renameLayer(let id, let name):
      guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        name.utf16.count <= 65_535
      else {
        throw CraftError.invalid("A layer needs a name.")
      }
      let i = try index(id)
      d.layers[i].name = name
    case .layerColor(let ids, let color):
      try LayerOrganization.setColor(color, selected: ids, in: &d)
    case .layerVisibility(let values):
      try LayerOrganization.setVisibility(values, in: &d)
    case .visibility(let id, let v):
      let i = try index(id, editable: false)
      d.layers[i].visible = v
    case .lock(let id, let v):
      let i = try index(id, editable: false)
      d.layers[i].locked = v
    case .opacity(let id, let v):
      guard v.isFinite, (0...1).contains(v) else {
        throw CraftError.invalid("Opacity must be between 0 and 1.")
      }
      let i = try index(id)
      d.layers[i].opacity = v
    case .blend(let id, let v):
      let i = try index(id)
      d.layers[i].blendMode = v
      if case .group(var group) = d.layers[i].content {
        group.passThrough = false
        d.layers[i].content = .group(group)
      }
    case .layoutLayers(let moves, _):
      try LayerLayout.apply(moves, to: &d)
    case .move(let id, let x, let y):
      guard abs(Double(x)) <= 1_000_000, abs(Double(y)) <= 1_000_000 else {
        throw CraftError.invalid("Position is out of range.")
      }
      let i = try index(id)
      let dx = x - d.layers[i].x
      let dy = y - d.layers[i].y
      let ids = d.subtreeIDs(id)
      for j in d.layers.indices where ids.contains(d.layers[j].id) {
        let old = d.layers[j]
        d.layers[j].x += dx
        d.layers[j].y += dy
        try d.layers[j].movePattern(x: dx, y: dy)
        try d.layers[j].preserveUnlinkedMask(from: old)
        if old.vectorMask?.linked == true {
          d.layers[j].vectorMask?.path = old.vectorMask!.path.transformed(
            .translation(Double(dx), Double(dy)))
        }
      }
    case .reorder(let id, let target):
      let i = try index(id)
      guard d.layers.indices.contains(target) else {
        throw CraftError.invalid("Invalid layer position.")
      }
      let destination = d.layers[target]
      guard destination.parentID == d.layers[i].parentID else {
        throw CraftError.invalid("Use Move Into Group to change a layer's parent.")
      }
      let siblings = d.children(of: destination.parentID)
      let position = siblings.firstIndex { $0.id == destination.id }!
      try d.relocate(id, parent: destination.parentID, position: position)
    case .relocate(let id, let parent, let position):
      _ = try index(id)
      try d.relocate(id, parent: parent, position: position)
    case .groupLayers(let requested, let name):
      try d.createLayerGroup(.init(name: name), children: requested, below: false)
    case .newGroup(let options, let children, let below):
      try d.createLayerGroup(options, children: children, below: below)
    case .ungroup(let id):
      let i = try index(id)
      guard d.layers[i].isGroup else { throw CraftError.invalid("Select a group to ungroup.") }
      let parent = d.layers[i].parentID
      let children = d.children(of: id)
      for j in d.layers.indices where d.layers[j].parentID == id { d.layers[j].parentID = parent }
      d.layers.remove(at: i)
      d.activeLayerID = children.last?.id ?? parent ?? d.layers.last?.id
    case .groupProperties(let id, let properties):
      let i = try index(id, editable: false)
      if d.layers[i].group?.passThrough != properties.passThrough && d.isLocked(id) {
        throw CraftError.invalid("Unlock the group before changing its blending.")
      }
      guard d.layers[i].isGroup else { throw CraftError.invalid("Select a group.") }
      d.layers[i].content = .group(properties)
    case .clipping(let id, let value):
      let i = try index(id)
      if value && d.clippingBase(for: id) == nil {
        throw CraftError.invalid("A clipping mask needs a base layer below it in the same group.")
      }
      d.layers[i].clipped = value
    case .blendClippedAsGroup(let id, let value):
      let i = try index(id)
      d.layers[i].blendClippedAsGroup = value
    case .replaceContent(let id, let c):
      let i = try index(id)
      guard !d.layers[i].isGroup, !Layer(name: "", content: c).isGroup else {
        throw CraftError.invalid("Use group commands to change the layer hierarchy.")
      }
      d.layers[i].content = c
    case .rasterize(let id, let surface):
      let i = try index(id)
      var layer = d.layers[i]
      guard !layer.isGroup else {
        throw CraftError.unsupported("Group rasterization is not available yet; ungroup first.")
      }
      if layer.isCanvasFill {
        let old = layer
        layer.x = 0
        layer.y = 0
        layer.affine = nil
        if old.mask != nil {
          layer.maskProperties = old.effectiveMaskProperties
          layer.maskProperties?.transform = old.maskCoordinateTransform
        }
      }
      layer.content = .raster(try surface.converted(to: d.depth))
      d.layers[i] = try DocumentGeometry.transformLayer(
        layer, by: .identity, in: d, method: .bicubic)
    case .mask(let id, let s):
      let i = try index(id)
      d.layers[i].mask = s
      d.layers[i].maskProperties = nil
      if s != nil && d.layers[i].isGroup {
        var properties = MaskProperties()
        properties.outside = d.selection == nil ? 1 : 0
        properties.transform = try d.layers[i].coordinateTransform.inverted()
        d.layers[i].maskProperties = properties
      }
    case .createMask(let id, let kind):
      let i = try index(id)
      d.layers[i] = try d.layers[i].creatingPixelMask(kind, in: d)
      if kind == .revealSelection || kind == .hideSelection { d.setCoverageSelection(nil) }
    case .applyMask(let id):
      let i = try index(id)
      d.layers[i] = try d.layers[i].applyingPixelMask(in: d)
    case .deleteMask(let id):
      let i = try index(id)
      guard d.layers[i].mask != nil else { throw CraftError.invalid("This layer has no mask.") }
      d.layers[i].mask = nil
      d.layers[i].maskProperties = nil
    case .maskProperties(let id, let properties):
      let i = try index(id)
      guard d.layers[i].mask != nil else { throw CraftError.invalid("This layer has no mask.") }
      try properties.validate()
      d.layers[i].maskProperties = properties
    case .vectorMask(let id, let mask):
      let i = try index(id)
      try mask?.validate()
      d.layers[i].vectorMask = mask
    case .savePath(let path):
      try path.path.validate()
      var paths = d.paths ?? []
      if let i = paths.firstIndex(where: { $0.id == path.id }) {
        paths[i] = path
      } else {
        paths.append(path)
      }
      d.paths = paths
    case .deletePath(let id):
      guard d.paths?.contains(where: { $0.id == id }) == true else {
        throw CraftError.invalid("Path no longer exists.")
      }
      d.paths?.removeAll { $0.id == id }
    case .selection(let s):
      d.selection = s
      d.selectionMask = nil
    case .selectShape(let shape, let mode, let antiAlias, let feather):
      let mask = try SelectionMask.make(
        shape, width: d.width, height: d.height, antiAlias: antiAlias
      )
      .feathered(radius: feather)
      d.setCoverageSelection(try mask.combined(with: d.coverageSelection(), mode: mode))
    case .selectionCoverage(let mask, let mode):
      guard mask == nil || (mask?.width == d.width && mask?.height == d.height) else {
        throw CraftError.invalid("Selection canvas sizes differ.")
      }
      d.setCoverageSelection(try mask?.combined(with: d.coverageSelection(), mode: mode))
    case .magicWand(let source, let seed, let options, let mode, let mask):
      let region = try ColorRegion.selection(
        source: source, width: d.width, height: d.height,
        seed: seed, options: options, mask: mask)
      let combined = try region.combined(with: d.coverageSelection(), mode: mode)
      try Task.checkCancellation()
      d.setCoverageSelection(combined)
    case .paintBucket(let id, let fill):
      let i = try index(id)
      try BucketPainter.paint(
        fill, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .paintGradient(let id, let stroke):
      let i = try index(id)
      try GradientPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .invertSelection:
      guard let mask = try d.coverageSelection() else {
        throw CraftError.invalid("Make a selection first.")
      }
      d.setCoverageSelection(try mask.inverted())
    case .featherSelection(let radius):
      guard let mask = try d.coverageSelection() else {
        throw CraftError.invalid("Make a selection first.")
      }
      d.setCoverageSelection(try mask.feathered(radius: radius))
    case .maskStroke(let id, let points, var brush):
      let i = try index(id)
      try d.layers[i].expandMask(for: points, brush: brush, clipping: d.selection)
      guard var mask = d.layers[i].mask else { throw CraftError.invalid("This layer has no mask.") }
      let value =
        brush.erase
        ? Float(1) : unit(0.2126 * brush.color.r + 0.7152 * brush.color.g + 0.0722 * brush.color.b)
      guard brush.color.isFinite else { throw CraftError.invalid("Invalid mask brush color.") }
      brush.color = Pixel(value, value, value, brush.color.a)
      brush.erase = false
      try Painter.stroke(
        surface: &mask, points: points, brush: brush, selection: d.selection,
        selectionMask: d.selectionMask, transform: d.layers[i].maskCoordinateTransform,
        grayscaleMask: true)
      d.layers[i].mask = mask
    case .maskFill(let id, let value):
      guard value.isFinite, (0...1).contains(value) else {
        throw CraftError.invalid("Invalid mask fill.")
      }
      let i = try index(id)
      if let selection = d.selection { try d.layers[i].expandMask(toDocumentBounds: selection) }
      guard var mask = d.layers[i].mask else { throw CraftError.invalid("This layer has no mask.") }
      let before = d
      let matrix = d.layers[i].maskCoordinateTransform
      mask.mapPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        let cov = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
        let v = unit(p.r) * (1 - cov) + value * cov
        return Pixel(v, v, v)
      }
      d.layers[i].mask = mask
      if d.selection == nil {
        var p = d.layers[i].effectiveMaskProperties
        p.outside = value
        d.layers[i].maskProperties = p
      }
    case .invertMask(let id):
      let i = try index(id)
      guard var mask = d.layers[i].mask else { throw CraftError.invalid("This layer has no mask.") }
      mask.mapPixels { _, _, p in
        let v = 1 - unit(p.r)
        return Pixel(v, v, v)
      }
      d.layers[i].mask = mask
      var properties = d.layers[i].effectiveMaskProperties
      properties.outside = 1 - properties.outside
      d.layers[i].maskProperties = properties
    case .focus(let id, let stroke):
      let i = try index(id)
      try FocusPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .toning(let id, let stroke):
      let i = try index(id)
      try ToningPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .spotHealing(let id, let stroke):
      let i = try index(id)
      try SpotHealingPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .healingBrush(let id, let stroke):
      let i = try index(id)
      try HealingPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .cloneStamp(let id, let stroke):
      let i = try index(id)
      try ClonePainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .stroke(let id, let points, let brush):
      let i = try index(id)
      var s = try raster(i)
      try Painter.stroke(
        surface: &s, points: points, brush: brush, selection: d.selection,
        selectionMask: d.selectionMask, offsetX: d.layers[i].x,
        offsetY: d.layers[i].y, transform: d.layers[i].coordinateTransform)
      d.layers[i].content = .raster(s)
    case .clear(let id):
      let i = try index(id)
      var s = try raster(i)
      let matrix = d.layers[i].coordinateTransform
      let before = d
      s.mapPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        return p.mixing(
          .clear, coverage: before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
      }
      d.layers[i].content = .raster(s)
    case .fill(let id, let color):
      guard color.isFinite else { throw CraftError.invalid("Invalid color.") }
      let i = try index(id)
      var s = try raster(i)
      let matrix = d.layers[i].coordinateTransform
      let before = d
      s.mapPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        return p.mixing(
          color, coverage: before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
      }
      d.layers[i].content = .raster(s)
    case .fillComponents(let id, let fill):
      try fill.validate()
      let i = try index(id)
      var s = try raster(i)
      guard d.depth == .u8, s.depth == .u8 else {
        throw CraftError.unsupported("Component Fill currently requires RGB/8 pixels.")
      }
      let matrix = d.layers[i].coordinateTransform
      try matrix.validated()
      let before = d
      try s.mapStoredPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        return fill.applying(
          to: p, coverage: before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
      }
      d.layers[i].content = .raster(s)
    case .autoCorrection(let id, let kind):
      let i = try index(id)
      _ = try raster(i)
      let histogram = try RGBHistogram.pixelLayer(id, in: d)
      guard histogram.samples > 0 else { break }
      let levels = try kind.levels(from: histogram)
      try Command.applyAdjustment(id, .levels(levels)).apply(to: &d)
    case .applyAdjustment(let id, let a):
      try a.validate()
      let evaluate = try a.spatialEvaluator(depth: d.depth)
      let i = try index(id)
      var s = try raster(i)
      let matrix = d.layers[i].coordinateTransform
      let before = d
      for y in 0..<s.height {
        try Task.checkCancellation()
        for x in 0..<s.width {
          let p = s.pixel(x: x, y: y)
          let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
          let coverage = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
          if coverage == 0 { continue }
          let edited = evaluate(p, Int(floor(q.x)), Int(floor(q.y)))
          let result: Pixel
          if a.usesDocumentToneSpace {
            result = LevelsTransfer.mix(p, with: edited, coverage: coverage, depth: before.depth)
            guard result.isFinite else {
              throw CraftError.invalid("Adjustment result exceeds the floating-point range.")
            }
          } else {
            result = p.mixing(edited, coverage: coverage)
          }
          s.setPixel(x: x, y: y, result)
        }
      }
      d.layers[i].content = .raster(s)
    case .desaturate(let id):
      try Command.applyAdjustment(id, .hueSaturation(.init(master: .init(saturation: -100))))
        .apply(to: &d)
    case .crop(let r):
      guard r.x >= 0, r.y >= 0, r.width > 0, r.height > 0, r.x <= d.width - r.width,
        r.y <= d.height - r.height
      else { throw CraftError.invalid("Crop must lie within the canvas.") }
      guard !d.layers.contains(where: { $0.locked }) else {
        throw CraftError.invalid("Unlock all layers before cropping.")
      }
      for i in d.layers.indices {
        d.layers[i].x -= r.x
        d.layers[i].y -= r.y
        if case .patternFill(var fill) = d.layers[i].content {
          try fill.transform(by: .translation(-Double(r.x), -Double(r.y)))
          d.layers[i].content = .patternFill(fill)
        }
        if let mask = d.layers[i].vectorMask {
          d.layers[i].vectorMask?.path = mask.path.transformed(
            .translation(-Double(r.x), -Double(r.y)))
        }
      }
      d.transformSavedPaths(by: .translation(-Double(r.x), -Double(r.y)))
      d.width = r.width
      d.height = r.height
      d.selection = nil
      d.selectionMask = nil
    case .flip(let id, let horizontal):
      let i = try index(id)
      let s = try raster(i)
      let layer = d.layers[i]
      let delta =
        Transform2D.translation(Double(layer.x), Double(layer.y))
        * (horizontal
          ? Transform2D(a: -1, tx: Double(s.width)) : Transform2D(d: -1, ty: Double(s.height)))
        * .translation(-Double(layer.x), -Double(layer.y))
      d.layers[i] = try DocumentGeometry.transformLayer(layer, by: delta, in: d, method: .nearest)
    case .transform(let id, let delta, let method):
      let i = try index(id)
      guard d.layers[i].canTransform else {
        throw CraftError.unsupported("Select a pixel, type or shape layer to transform.")
      }
      let before = d
      let ids = d.subtreeIDs(id)
      for j in d.layers.indices where ids.contains(d.layers[j].id) {
        d.layers[j] = try DocumentGeometry.transformLayer(
          d.layers[j], by: delta, in: before, method: method)
      }
    case .resolution(let value):
      guard value.isFinite, (1...100_000).contains(value) else {
        throw CraftError.invalid("Invalid image resolution.")
      }
      d.resolution = value
    case .canvasSize(let width, let height, let anchor, let extensionColor):
      _ = try Surface(width: width, height: height, depth: d.depth)
      guard extensionColor?.isFinite != false else {
        throw CraftError.invalid("Invalid canvas extension color.")
      }
      let old = d
      let fractions = anchor.fractions
      let dx = Int((Double(width - d.width) * fractions.0).rounded(.down))
      let dy = Int((Double(height - d.height) * fractions.1).rounded(.down))
      for i in d.layers.indices {
        DocumentGeometry.freezeTextLayout(&d.layers[i], document: old)
        d.layers[i].x += dx
        d.layers[i].y += dy
        if case .patternFill(var fill) = d.layers[i].content {
          try fill.transform(by: .translation(Double(dx), Double(dy)))
          d.layers[i].content = .patternFill(fill)
        }
        if let mask = d.layers[i].vectorMask {
          d.layers[i].vectorMask?.path = mask.path.transformed(.translation(Double(dx), Double(dy)))
        }
      }
      if let color = extensionColor, color.a > 0, width > old.width || height > old.height {
        guard color.isFinite, d.layers.count < 512 else {
          throw CraftError.invalid("Invalid canvas extension or layer limit.")
        }
        var pixels = try Surface(width: width, height: height, depth: d.depth)
        for y in 0..<height {
          try Task.checkCancellation()
          for x in 0..<width where x < dx || y < dy || x >= dx + old.width || y >= dy + old.height {
            pixels.setPixel(x: x, y: y, color)
          }
        }
        d.layers.insert(Layer(name: "Canvas Extension", content: .raster(pixels)), at: 0)
      }
      d.width = width
      d.height = height
      d.transformSavedPaths(by: .translation(Double(dx), Double(dy)))
      try d.mapSelection(from: old, by: .translation(Double(dx), Double(dy)))
    case .imageSize(let width, let height, let resolution, let method):
      _ = try Surface(width: width, height: height, depth: d.depth)
      guard resolution.isFinite, (1...100_000).contains(resolution) else {
        throw CraftError.invalid("Invalid image resolution.")
      }
      let old = d
      let delta = Transform2D.scale(
        Double(width) / Double(d.width), Double(height) / Double(d.height))
      if width != old.width || height != old.height {
        for i in d.layers.indices {
          d.layers[i] = try DocumentGeometry.transformLayer(
            d.layers[i], by: delta, in: old, method: method, includingUnlinkedMasks: true)
        }
      }
      d.width = width
      d.height = height
      d.resolution = resolution
      d.transformSavedPaths(by: delta)
      try d.mapSelection(from: old, by: delta)
    case .rotateCanvas(let turn):
      let old = d
      let delta = turn.transform(width: d.width, height: d.height)
      for i in d.layers.indices {
        d.layers[i] = try DocumentGeometry.transformLayer(
          d.layers[i], by: delta, in: old, method: .nearest, includingUnlinkedMasks: true)
      }
      if turn == .clockwise || turn == .counterclockwise {
        d.width = old.height
        d.height = old.width
      }
      d.transformSavedPaths(by: delta)
      try d.mapSelection(from: old, by: delta)
    }
    try d.validate()
  }
}
public struct HistoryEntry: Sendable {
  public var label: String
  public var document: CraftDocument
}
public struct PreparedEdit: Sendable {
  let original: CraftDocument
  let result: CraftDocument
  let label: String
  /// Restore saved content as one undoable edit while retaining this open document's identity.
  public init(restoring saved: CraftDocument, over current: CraftDocument) throws {
    var restored = saved
    restored.id = current.id
    try restored.validate()
    original = current
    result = restored
    label = "Revert"
  }
  public init(command: Command, document: CraftDocument) throws {
    original = document
    var candidate = document
    try command.apply(to: &candidate)
    result = candidate
    label = command.label
  }
}
public struct EditorSession: Sendable {
  public private(set) var document: CraftDocument
  public private(set) var undoStack: [HistoryEntry] = []
  public private(set) var redoStack: [HistoryEntry] = []
  private var coalescing = false
  private var coalescingHasChanges = false
  public let historyByteLimit: Int
  public let limit: Int
  public init(
    document: CraftDocument, historyLimit: Int = 40, historyByteLimit: Int = 256 * 1024 * 1024
  ) {
    self.document = document
    limit = max(1, min(200, historyLimit))
    self.historyByteLimit = max(0, historyByteLimit)
  }
  public mutating func selectLayer(_ id: UUID) {
    if document.layers.contains(where: { $0.id == id }) { document.activeLayerID = id }
  }
  /// Persisted panel metadata, deliberately outside edit history and coalescing.
  /// Validate the complete request before changing any group; locks protect content,
  /// not whether its rows are expanded in the Layers panel.
  @discardableResult
  public mutating func setGroupExpansion(_ ids: Set<UUID>, expanded: Bool) throws -> Bool {
    let groups = Set(document.layers.filter(\.isGroup).map(\.id))
    guard !ids.isEmpty, ids.isSubset(of: groups) else {
      throw CraftError.invalid("Choose existing layer groups.")
    }
    var changed = false
    for index in document.layers.indices where ids.contains(document.layers[index].id) {
      guard var group = document.layers[index].group, group.expanded != expanded else { continue }
      group.expanded = expanded
      document.layers[index].content = .group(group)
      changed = true
    }
    return changed
  }
  public mutating func beginCoalescing() {
    coalescing = true
    coalescingHasChanges = false
  }
  public mutating func endCoalescing() {
    coalescing = false
    coalescingHasChanges = false
  }
  public mutating func execute(_ command: Command) throws {
    try executePrepared(PreparedEdit(command: command, document: document))
  }
  public mutating func executePrepared(_ prepared: PreparedEdit) throws {
    guard prepared.original == document else {
      throw CraftError.invalid("The document changed while processing. The result was not applied.")
    }
    let candidate = prepared.result
    guard candidate != document else { return }
    if !coalescing || !coalescingHasChanges {
      undoStack.append(HistoryEntry(label: prepared.label, document: document))
    }
    coalescingHasChanges = true
    redoStack = []
    if undoStack.count > limit { undoStack.removeFirst() }
    document = candidate
    trimHistory()
  }
  private mutating func trimHistory() {
    while undoStack.reduce(0, { $0 + $1.document.estimatedBytes }) > historyByteLimit {
      undoStack.removeFirst()
    }
    while redoStack.reduce(0, { $0 + $1.document.estimatedBytes }) > historyByteLimit {
      redoStack.removeFirst()
    }
  }
  public mutating func undo() {
    endCoalescing()
    guard let e = undoStack.popLast() else { return }
    redoStack.append(HistoryEntry(label: e.label, document: document))
    document = e.document
    trimHistory()
  }
  public mutating func redo() {
    endCoalescing()
    guard let e = redoStack.popLast() else { return }
    undoStack.append(HistoryEntry(label: e.label, document: document))
    document = e.document
    trimHistory()
  }
}
