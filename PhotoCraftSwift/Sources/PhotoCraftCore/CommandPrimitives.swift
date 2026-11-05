import Foundation

// Keep each family out of line: a broad switch reserves space for every branch,
// even when a simple nested command uses only one of them. Case bodies and
// transaction validation retain their original order and behavior.
extension Command {
  @inline(never)
  func applyClipboardPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int, allowLarge: Bool = false) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      guard allowLarge || s.width <= Surface.maximumDensePixels / s.height else {
        throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")
      }
      return s
    }
    switch self {
    case .paste(let content, let placement, let center):
      try content.paste(into: &d, placement: placement, center: center)
    case .layerVia(let id, let operation):
      try LayerVia.apply(operation, layerID: id, to: &d)
    case .cut(let requested, let background):
      let ids = Set(requested)
      guard !ids.isEmpty, ids.allSatisfy({ id in d.layers.contains { $0.id == id } }) else {
        throw CraftError.invalid("Select a layer to cut.")
      }
      guard background?.isFinite != false, background == nil || background!.a == 1 else { throw CraftError.invalid("Cut background must be an opaque finite color.") }
      if ids.count==1,let id=ids.first,d.layers.first(where:{$0.id==id})?.isBackground == true {try BackgroundLayer.apply(.clear(id,background ?? .white),to:&d);return}
      if d.selection != nil || d.restrictedMode != nil || (ids.count==1 && d.layers.contains(where:{$0.id==ids.first && $0.isBackground})) {
        guard ids.count == 1, let id = ids.first else {
          throw CraftError.unsupported("Cut a pixel selection from one layer at a time.")
        }
        let i = try index(id)
        var pixels = try raster(i)
        let transform = d.layers[i].coordinateTransform
        let flatBackground: Pixel?
        switch d.restrictedMode {
        case .bitmap: flatBackground = background ?? .white
        case .indexed(let raster): flatBackground = raster.transparentIndex == nil ? background ?? .white : nil
        case nil: flatBackground = d.layers[i].isBackground ? background ?? .white:nil
        }
        for y in 0..<pixels.height {
          try Task.checkCancellation()
          for x in 0..<pixels.width {
            let point = transform.point(Double(x) + 0.5, Double(y) + 0.5)
            let coverage = d.selectionCoverage(x: Int(floor(point.x)), y: Int(floor(point.y)))
            if coverage > 0 {
              var value = pixels.pixel(x: x, y: y)
              if let fill = flatBackground { value = Pixel(value.r * (1 - coverage) + fill.r * coverage, value.g * (1 - coverage) + fill.g * coverage, value.b * (1 - coverage) + fill.b * coverage, 1) }
              else { value.a *= 1 - coverage }
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
    case .setGradientFill(let id, let fill):
      let i = try index(id)
      guard case .gradientFill = d.layers[i].content else {
        throw CraftError.invalid("Select a gradient fill layer.")
      }
      try fill.validate()
      d.layers[i].content = .gradientFill(fill)
    case .setPatternFill(let id, var fill, let pattern):
      let i = try index(id)
      guard case .patternFill = d.layers[i].content else {
        throw CraftError.invalid("Select a pattern fill layer.")
      }
      if let pattern { fill.patternID = try d.installPattern(pattern) }
      d.layers[i].content = .patternFill(fill)
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyLayerStructurePrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    switch self {
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
      let i = try index(id, editable: false)
      guard !d.layers[i].isBackground || name==d.layers[i].name else{throw CraftError.invalid("Convert Background to a regular layer before renaming it.")}
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
      guard !d.layers[i].isBackground else{throw CraftError.invalid("Convert Background to change its locks.")}
      d.layers[i].protection = v ? .fullyLocked : []
    case .protection(let values):
      let ids = Set(values.keys)
      for value in values.values { try value.validate() }
      guard !ids.isEmpty, ids.isSubset(of: Set(d.layers.map(\.id))) else {
        throw CraftError.invalid("Select existing layers to protect.")
      }
      guard !d.layers.contains(where:{ids.contains($0.id) && $0.isBackground}) else{throw CraftError.invalid("Convert Background to change its locks.")}
      for i in d.layers.indices where ids.contains(d.layers[i].id) {
        d.layers[i].protection = values[d.layers[i].id]!
      }
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyLayerPropertiesPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    switch self {
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
      try LayerLinks.move(.init(layerIDs:[id],dx:dx,dy:dy),in:&d)
    case .stackLayers(let request): try LayerStackOrder.apply(request, to: &d)
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
      guard properties.frame == d.layers[i].frame else { throw CraftError.invalid("Use Frame Properties to edit frame metadata.") }
      guard properties.artboard == d.layers[i].artboard else { throw CraftError.invalid("Use Artboard Properties to change artboard metadata.") }
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
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyLayerContentPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int, allowLarge: Bool = false) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      guard allowLarge || s.width <= Surface.maximumDensePixels / s.height else {
        throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")
      }
      return s
    }
    switch self {
    case .importedType(let transition):try transition.apply(to:&d)
    case .editType(let id,let content,let delta):
      let i=try index(id);guard case .text=d.layers[i].content,!d.isImageLocked(id),delta.x.isFinite,delta.y.isFinite,abs(delta.x)<=1_000_000,abs(delta.y)<=1_000_000 else{throw CraftError.invalid("Editable type and a finite origin are required.")}
      try content.validate();let old=d.layers[i];d.layers[i].content = .text(content)
      if delta.x != 0 || delta.y != 0 {
        d.layers[i].x=0;d.layers[i].y=0;d.layers[i].affine=old.coordinateTransform * .translation(delta.x,delta.y)
        if old.mask != nil{var properties=old.effectiveMaskProperties;properties.transform=try d.layers[i].coordinateTransform.inverted() * old.maskCoordinateTransform;d.layers[i].maskProperties=properties}
      }
    case .replaceContent(let id, let c):
      let i = try index(id)
      guard !d.layers[i].isGroup, !Layer(name: "", content: c).isGroup else {
        throw CraftError.invalid("Use group commands to change the layer hierarchy.")
      }
      d.layers[i].content = c
    case .rasterize(let id, let surface):
      let i = try index(id)
      var layer = d.layers[i]
      if let object = layer.smartObject, object.pdfSource != nil,
        surface.width != object.width || surface.height != object.height {
        // The shared PDF renderer can supply a denser source-space surface.
        // Preserve its document geometry and mask mapping when dropping source.
        let sx = Double(surface.width)/Double(object.width)
        let sy = Double(surface.height)/Double(object.height)
        layer.affine = (layer.affine ?? .identity) * .scale(1/sx,1/sy)
        if layer.mask != nil {
          var properties = layer.effectiveMaskProperties
          properties.transform = .scale(sx,sy) * properties.transform
          layer.maskProperties = properties
        }
        layer.content = .raster(surface)
      }
      if layer.smartFilters != nil || layer.warp != nil || layer.sourceProjection != nil || layer.importedSmartAppearance != nil {
        layer = try SmartFilterEngine.renderedLayer(layer, in: d)
        for key in ["SoLd", "SoLE", "PlLd"] { layer.sourceTags?.removeValue(forKey: key) }
        d.layers[i] = layer
        break
      }
      layer.video = nil
      layer.smartObject = nil
      for key in ["SoLd", "SoLE", "PlLd"] { layer.sourceTags?.removeValue(forKey: key) }
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
    case .embedSmartObject(let ids, let layer):
      try d.embedSmartObject(replacing: ids, with: layer)
    case .smartObjectStack(let id, let mode, let pixels):
      let i = try index(id)
      guard d.layers[i].smartObject != nil, !d.isImageLocked(id) else { throw CraftError.invalid("Select an unlocked Smart Object.") }
      d.layers[i].smartObject?.stackMode = mode; try d.layers[i].smartObject?.validate()
      d.layers[i].content = .raster(pixels)
      for key in ["SoLd", "SoLE", "PlLd"] { d.layers[i].sourceTags?.removeValue(forKey: key) }
    case .replaceSmartObject(let id, let source, let pixels, let preserveSize, let allInstances, let instancePixels):
      try d.replaceSmartObject(id, source: source, pixels: pixels, preserveSize: preserveSize, allInstances: allInstances, instancePixels: instancePixels)
    case .resetSmartObjectTransform(let id):
      let i = try index(id)
      guard d.layers[i].smartObject != nil, !d.isPositionLocked(id) else {
        throw CraftError.invalid("Select a position-unlocked Smart Object.")
      }
      let delta = Transform2D.translation(Double(d.layers[i].x), Double(d.layers[i].y)) * (try d.layers[i].smartObjectSourceTransform().inverted())
      d.layers[i] = try DocumentGeometry.transformLayer(d.layers[i], by: delta, in: d)
      d.layers[i].warp = nil
      d.layers[i].sourceProjection = nil
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyMaskPathPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    switch self {
    case .mask(let id, let s):
      let i = try index(id)
      if s == nil { try LensBlurEngine.validateMaskRemoval(d.layers[i]) }
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
      try LensBlurEngine.validateMaskRemoval(d.layers[i])
      d.layers[i] = try d.layers[i].applyingPixelMask(in: d)
    case .deleteMask(let id):
      let i = try index(id)
      try LensBlurEngine.validateMaskRemoval(d.layers[i])
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
    case .modifiedSelection(let mask,_),.reselectedSelection(let mask),.transformedSelection(let mask):
      guard mask.width == d.width,mask.height == d.height else {throw CraftError.invalid("Selection canvas sizes differ.")}
      d.setCoverageSelection(mask)
    case .colorRange(let mask):
      guard mask.width == d.width, mask.height == d.height else { throw CraftError.invalid("Color Range canvas sizes differ.") }
      d.setCoverageSelection(mask)
    case .magneticSelection(let mask,let mode):
      guard mask.width == d.width,mask.height == d.height else {throw CraftError.invalid("Magnetic Lasso canvas sizes differ.")}
      d.setCoverageSelection(try mask.combined(with:d.coverageSelection(),mode:mode))
    case .selectionCoverage(let mask, let mode):
      guard mask == nil || (mask?.width == d.width && mask?.height == d.height) else {
        throw CraftError.invalid("Selection canvas sizes differ.")
      }
      d.setCoverageSelection(try mask?.combined(with: d.coverageSelection(), mode: mode))
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyPreparedRasterPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int, allowLarge: Bool = false) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      guard allowLarge || s.width <= Surface.maximumDensePixels / s.height else {
        throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")
      }
      return s
    }
    switch self {
    case .vanishingPoint(let edit): d = try edit.applied(to:d)
    case .maskAllObjects(let edit): d = try edit.applied(to:d)
    case .skyReplacement(let edit): d = try edit.applied(to:d)
    case .warp(let edit):
      d = try edit.applied(to:d)
    case .contentAwareScale(let edit):
      d = try edit.applied(to:d)
    case .photoAlign(let edit):
      d = try edit.applied(to:d)
    case .photoBlend(let edit):
      d = try edit.applied(to:d)
    case .adjustmentBrush(let request): try request.apply(to:&d)
    case .painting(let edit):
      d = try edit.applied(to:d)
    case .regionRetouch(let edit):
      d = try edit.applied(to:d)
    case .contentAwareFill(let edit):
      d = try edit.applied(to:d)
    case .selectionRefinement(let edit),.focusArea(let edit):
      guard !edit.output.createsDocument else { throw CraftError.invalid("Create the refined document through the document controller.") }
      d = try edit.applied(to:d)
    case .selectSubject(let mask, let mode):
      guard mask.width == d.width, mask.height == d.height, mask.bounds != nil else {
        throw CraftError.invalid("No foreground subject was found, or the mask dimensions differ.")
      }
      d.setCoverageSelection(try mask.combined(with: d.coverageSelection(), mode: mode))
    case .removeBackground(let id, let mask):
      let i = try index(id)
      _ = try raster(i)
      guard mask.width == d.width, mask.height == d.height, mask.bounds != nil else {
        throw CraftError.invalid("No foreground subject was found, or the mask dimensions differ.")
      }
      // Reuse canvas-to-layer mask coordinates without consuming the user's selection.
      var selected = d
      selected.setCoverageSelection(mask)
      d.layers[i] = try d.layers[i].creatingPixelMask(.revealSelection, in: selected)
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyPaintingPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int, allowLarge: Bool = false) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      guard allowLarge || s.width <= Surface.maximumDensePixels / s.height else {
        throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")
      }
      return s
    }
    switch self {
    case .magicWand(let source, let seed, let options, let mode, let mask):
      let region = try ColorRegion.selection(
        source: source, width: d.width, height: d.height,
        seed: seed, options: options, mask: mask)
      let combined = try region.combined(with: d.coverageSelection(), mode: mode)
      try Task.checkCancellation()
      d.setCoverageSelection(combined)
    case .paintBucket(let id, let fill):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try BucketPainter.paint(
        fill, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .paintGradient(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try GradientPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
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
      let preserve = d.isTransparencyLocked(id)
      try FocusPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .toning(let id, let stroke):
      let i = try index(id)
      try ToningPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .spotHealing(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try SpotHealingPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .healingBrush(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try HealingPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .cloneStamp(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try ClonePainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .stroke(let id, let points, var brush):
      let i = try index(id)
      var s = try raster(i, allowLarge: true)
      brush=d.layers[i].backgroundBrush(brush)
      try Painter.stroke(
        surface: &s, points: points, brush: brush, selection: d.selection,
        selectionMask: d.selectionMask, offsetX: d.layers[i].x,
        offsetY: d.layers[i].y, transform: d.layers[i].coordinateTransform,
        preserveTransparency: d.isTransparencyLocked(id))
      d.layers[i].content = .raster(s)
    case .clear(let id):
      if d.layers.first(where:{$0.id==id})?.isBackground == true {try BackgroundLayer.apply(.clear(id,.white),to:&d);return}
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
      let preserveTransparency = d.isTransparencyLocked(id)
      let targetDepth = s.depth
      let edit: (Int, Int, Pixel) -> Pixel = { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        let coverage = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
        if preserveTransparency {
          guard p.a > 0, coverage > 0 else { return p }
          var edited = ProtectedPixels.fill(p, color: color, coverage: coverage).quantized(targetDepth)
          edited.a = p.a
          return edited
        }
        return p.mixing(color, coverage: coverage)
      }
      if preserveTransparency { try s.mapStoredPixels(edit) } else { s.mapPixels(edit) }
      d.layers[i].content = .raster(s)
    case .fillComponents(let id, let fill):
      try fill.validate()
      let i = try index(id)
      // The ordinary RGB8 large path below owns bounded component preparation.
      var s = try raster(i, allowLarge: d.colorMode == .rgb && !d.hasNativeModeStorage)
      guard d.depth == .u8, s.depth == .u8 else {
        throw CraftError.unsupported("Component Fill currently requires RGB/8 pixels.")
      }
      if d.colorMode == .rgb, !d.hasNativeModeStorage,
        s.width > NativeModeRaster.maximumPixels / s.height {
        let components=Set([RGBComponents.red,.green,.blue].enumerated().compactMap { fill.components.contains($0.element) ? $0.offset:nil })
        try ModeComponentEdit(layerID:id,components:components,operation:.fill(fill.value,fill.opacity)).apply(to:&d)
        return
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
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
  }

  @inline(never)
  func applyGeometryPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int, allowLarge: Bool = false) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      guard allowLarge || s.width <= Surface.maximumDensePixels / s.height else {
        throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")
      }
      return s
    }
    switch self {
    case .layerStyle(let ids, let style):
      try LayerStyleEdit(layerIDs: Set(ids), style: style).apply(to: &d)
    case .cropDocument(let edit):
      d = try edit.applied(to:d)
    case .crop(let r):
      let original = d
      guard r.x >= 0, r.y >= 0, r.width > 0, r.height > 0, r.x <= d.width - r.width,
        r.y <= d.height - r.height
      else { throw CraftError.invalid("Crop must lie within the canvas.") }
      guard !d.layers.contains(where: { $0.locked }) else {
        throw CraftError.invalid("Unlock all layers before cropping.")
      }
      for i in d.layers.indices {
        d.layers[i].x -= r.x
        d.layers[i].y -= r.y
        if let stack = d.layers[i].smartFilters {
          d.layers[i].smartFilters?.transformPuppetPins(.translation(-Double(r.x), -Double(r.y)))
          d.layers[i].smartFilters?.transformPerspectivePlanes(.translation(-Double(r.x), -Double(r.y)))
          d.layers[i].smartFilters?.maskProperties.transform = .translation(-Double(r.x), -Double(r.y)) * stack.maskProperties.transform
        }
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
      try d.mapGuides( .translation(-Double(r.x), -Double(r.y)))
      if let origin = d.artboardOrigin { d.artboardOrigin = .init(x: origin.x + r.x, y: origin.y + r.y) }
      d.width = r.width
      d.height = r.height
      d.selection = nil
      d.selectionMask = nil
      try d.transformChannels(from:original,by:.translation(-Double(r.x),-Double(r.y)))
    case .flip(let id, let horizontal):
      let i = try index(id)
      let s = try raster(i,allowLarge:true)
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
      let before=d,ids=LayerLinks.expanded(in:d,layerIDs:[id])
      guard ids.allSatisfy({!d.isPositionLocked($0)}) else{throw CraftError.invalid("Unlock every transformed linked layer and descendant.")}
      for j in d.layers.indices where ids.contains(d.layers[j].id){d.layers[j]=try DocumentGeometry.transformLayer(d.layers[j],by:delta,in:before,method:method)}
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
        if let stack = d.layers[i].smartFilters {
          d.layers[i].smartFilters?.transformPuppetPins(.translation(Double(dx), Double(dy)))
          d.layers[i].smartFilters?.transformPerspectivePlanes(.translation(Double(dx), Double(dy)))
          d.layers[i].smartFilters?.maskProperties.transform = .translation(Double(dx), Double(dy)) * stack.maskProperties.transform
        }
        if case .patternFill(var fill) = d.layers[i].content {
          try fill.transform(by: .translation(Double(dx), Double(dy)))
          d.layers[i].content = .patternFill(fill)
        }
        if let mask = d.layers[i].vectorMask {
          d.layers[i].vectorMask?.path = mask.path.transformed(.translation(Double(dx), Double(dy)))
        }
      }
      if let color = extensionColor, color.a > 0, !old.layers.contains(where:{$0.isBackground}), width > old.width || height > old.height {
        guard color.isFinite, d.layers.count < LayerLimits.maximumLayers else {
          throw CraftError.invalid("Invalid canvas extension or layer limit.")
        }
        let pixels=try Surface.canvasExtension(width:width,height:height,depth:d.depth,color:color,
          original:IntRect(x:dx,y:dy,width:old.width,height:old.height))
        d.layers.insert(Layer(name: "Canvas Extension", content: .raster(pixels)), at: 0)
      }
      if let origin = d.artboardOrigin { d.artboardOrigin = .init(x: origin.x - dx, y: origin.y - dy) }
      d.width = width
      d.height = height
      d.transformSavedPaths(by: .translation(Double(dx), Double(dy)))
      try d.mapGuides( .translation(Double(dx), Double(dy)))
      try d.mapSelection(from: old, by: .translation(Double(dx), Double(dy)))
      try d.transformChannels(from:old,by:.translation(Double(dx),Double(dy)))
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
      if let origin = old.artboardOrigin { d.artboardOrigin = .init(x: Int((Double(origin.x) * Double(width) / Double(old.width)).rounded()), y: Int((Double(origin.y) * Double(height) / Double(old.height)).rounded())) }
      d.transformSavedPaths(by: delta)
      try d.mapGuides( delta)
      try d.mapSelection(from: old, by: delta)
      try d.transformChannels(from:old,by:delta,method:method)
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
      try d.mapGuides( delta)
      try d.mapSelection(from: old, by: delta)
      try d.transformChannels(from:old,by:delta)
    default: throw CraftError.invalid("Unexpected primitive command family routing.")
    }
    switch self {
    case .canvasSize(_,_,_,let fill):try d.reframeBackground(over:fill?.a==1 ? fill!:.white)
    case .crop,.cropDocument,.imageSize,.rotateCanvas:try d.reframeBackground()
    default:break
    }
  }

}
