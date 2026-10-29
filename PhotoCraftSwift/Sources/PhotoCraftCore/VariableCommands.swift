import Foundation

public enum VariableCommand: Sendable {
  case configure(DataDrivenGraphics, apply: UUID?)
  case define([VariableDefinition])
  case rename(String, String)
  case dataSets([VariableDataSet], append: Bool)
  case image(VariableImage)
  case removeImage(UUID)
  case apply(UUID)
  case clear
  public var label: String {
    switch self {
    case .configure: "Variables and Data Sets"
    case .define: "Define Variables"
    case .rename: "Rename Variable"
    case .dataSets: "Edit Data Sets"
    case .image: "Add Replacement Image"
    case .removeImage: "Remove Replacement Image"
    case .apply: "Apply Data Set"
    case .clear: "Remove Variables and Data Sets"
    }
  }
  public func apply(to document: inout CraftDocument) throws {
    // Validation, cancellation and a late failing layer cannot leave a partial row applied.
    var result = document, variables = document.variables ?? DataDrivenGraphics()
    switch self {
    case .configure(let settings, let selected):
      variables = settings
      for i in variables.definitions.indices where variables.definitions[i].kind == .pixelReplacement && variables.definitions[i].pixelFrame == nil {
        let definition = variables.definitions[i]
        if let old = document.variables?.definitions.first(where: { $0.id == definition.id && $0.layerID == definition.layerID && $0.kind == definition.kind }), let frame = old.pixelFrame {
          variables.definitions[i].pixelFrame = frame
        } else {
          guard let layer = result.layers.first(where: { $0.id == definition.layerID }) else { throw CraftError.invalid("The variable's layer no longer exists.") }
          variables.definitions[i].pixelFrame = try VariablePixelFrame(layer: layer)
        }
      }
      variables.activeDataSetID = nil
      result.variables = variables.isEmpty ? nil : variables
      try result.validate()
      if let selected { try VariableCommand.apply(selected).apply(to: &result) }
      document = result; return
    case .clear: result.variables = nil; document = result; return
    case .define(var definitions):
      for i in definitions.indices where definitions[i].kind == .pixelReplacement && definitions[i].pixelFrame == nil {
        guard let layer = result.layers.first(where: { $0.id == definitions[i].layerID }) else {
          throw CraftError.invalid("The variable's layer no longer exists.")
        }
        let retained = document.variables?.definitions.first(where: {
          $0.id == definitions[i].id && $0.layerID == definitions[i].layerID && $0.kind == .pixelReplacement
        })?.pixelFrame
        if let retained { definitions[i].pixelFrame = retained }
        else { definitions[i].pixelFrame = try VariablePixelFrame(layer: layer) }
      }
      variables.definitions = definitions
      let kinds = Dictionary(definitions.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
      for i in variables.dataSets.indices {
        variables.dataSets[i].values = variables.dataSets[i].values.filter { kinds[$0.key] == $0.value.kind }
      }
      variables.activeDataSetID = nil
    case .rename(let old, let new):
      guard variables.definitions.contains(where: { $0.name == old }), VariableDefinition.validName(new),
            old == new || !variables.definitions.contains(where: { $0.name == new }) else {
        throw CraftError.invalid("Choose an existing variable and an unused valid name.")
      }
      for i in variables.definitions.indices where variables.definitions[i].name == old { variables.definitions[i].name = new }
      for i in variables.dataSets.indices {
        if let value = variables.dataSets[i].values.removeValue(forKey: old) { variables.dataSets[i].values[new] = value }
      }
    case .dataSets(let rows, let append):
      variables.dataSets = append ? variables.dataSets + rows : rows
      variables.activeDataSetID = nil
    case .image(let image):
      if let i = variables.images.firstIndex(where: { $0.id == image.id }) { variables.images[i] = image }
      else { variables.images.append(image) }
      variables.activeDataSetID = nil
    case .removeImage(let id):
      guard !variables.dataSets.contains(where: { $0.values.values.contains(.pixels(id)) }) else {
        throw CraftError.invalid("This image is used by a data set. Choose Do Not Replace or another image first.")
      }
      variables.images.removeAll { $0.id == id }
    case .apply(let id):
      try variables.validate(in: result)
      guard let row = variables.dataSets.first(where: { $0.id == id }) else { throw CraftError.invalid("Data set not found.") }
      for definition in variables.definitions {
        try Task.checkCancellation()
        guard let value = row.values[definition.name] else { continue }
        if case .pixels(nil) = value { continue }
        guard let i = result.layers.firstIndex(where: { $0.id == definition.layerID }), !result.isLocked(definition.layerID) else {
          throw CraftError.invalid("Unlock the variable's layer and its parent groups before applying this data set.")
        }
        switch value {
        case .visibility(let visible): result.layers[i].visible = visible
        case .text(let replacement):
          guard !result.isImageLocked(definition.layerID), case .text(var text) = result.layers[i].content else {
            throw CraftError.invalid("Text Replacement needs editable type.")
          }
          text.text = replacement
          if var type = text.typography {
            // Keep the first character/paragraph formatting when replacing the complete string.
            if let first = type.runs.first { type.defaultStyle = first.style; type.defaultParagraph = first.paragraph }
            type.runs = []; type.defaultStyle.glyphOverride = nil; text.typography = type
          }
          try text.validate(); result.layers[i].content = .text(text)
          for key in ["TySh", "tySh", "Txt2"] { result.layers[i].sourceTags?.removeValue(forKey: key) }
        case .pixels(let assetID):
          guard let assetID, let asset = variables.images.first(where: { $0.id == assetID }) else {
            throw CraftError.invalid("Replacement image not found.")
          }
          guard !result.hasAuthoritativeModeStorage, !result.isImageLocked(definition.layerID), !result.isTransparencyLocked(definition.layerID),
                !result.isPositionLocked(definition.layerID), asset.workingICC == result.workingICC else {
            throw CraftError.unsupported("Pixel Replacement needs an unlocked RGB layer and an image converted to the template's working profile.")
          }
          result.layers[i] = try Self.replacingPixels(result.layers[i], definition: definition, image: asset.pixels, depth: result.depth)
        }
      }
      variables.activeDataSetID = id
    }
    result.variables = variables.isEmpty ? nil : variables
    try result.validate(); document = result
  }
  private static func replacingPixels(_ layer: Layer, definition: VariableDefinition,
                                      image: Surface, depth: PixelDepth) throws -> Layer {
    guard let frame = definition.pixelFrame, let options = definition.pixelOptions else {
      throw CraftError.invalid("Pixel placement is missing.")
    }
    let tw = Double(frame.width), th = Double(frame.height), iw = Double(image.width), ih = Double(image.height)
    let sx: Double, sy: Double
    switch options.method {
    case .fit: sx = min(tw / iw, th / ih); sy = sx
    case .fill: sx = max(tw / iw, th / ih); sy = sx
    case .asIs: sx = 1; sy = 1
    case .conform: sx = tw / iw; sy = th / ih
    }
    let (ax, ay) = options.method == .conform ? (0.0, 0.0) : options.alignment.fractions
    let placement = Transform2D.translation(((tw - iw * sx) * ax).rounded(), ((th - ih * sy) * ay).rounded()) * .scale(sx, sy)
    var bounds = try placement.bounds(width: image.width, height: image.height)
    if options.clipToBounds && (options.method == .fill || options.method == .asIs) {
      bounds = bounds.clipped(toWidth: frame.width, height: frame.height)
    }
    guard bounds.width > 0, bounds.height > 0 else { throw CraftError.invalid("Replacement has no pixels inside the bounding box.") }
    let inverse = try placement.inverted()
    var output = try Surface(width: bounds.width, height: bounds.height, depth: depth)
    for y in 0..<bounds.height {
      try Task.checkCancellation()
      for x in 0..<bounds.width {
        let p = inverse.point(Double(x + bounds.x) + 0.5, Double(y + bounds.y) + 0.5)
        if p.x >= 0 && p.y >= 0 && p.x < iw && p.y < ih {
          output.setPixel(x: x, y: y, RasterGeometry.sample(image, x: p.x, y: p.y, method: .bicubic, clampEdges: true))
        }
      }
    }
    var result = layer
    result.content = .raster(output); result.x = 0; result.y = 0
    result.affine = frame.transform * .translation(Double(bounds.x), Double(bounds.y))
    let transform = result.coordinateTransform
    if transform.a == 1, transform.b == 0, transform.c == 0, transform.d == 1,
       transform.tx == transform.tx.rounded(), transform.ty == transform.ty.rounded() {
      result.x = Int(transform.tx); result.y = Int(transform.ty); result.affine = nil
    }
    if layer.mask != nil {
      var properties = layer.effectiveMaskProperties
      properties.transform = try result.coordinateTransform.inverted() * layer.maskCoordinateTransform
      result.maskProperties = properties
    }
    return result
  }
}

extension CraftDocument {
  mutating func reconcileVariables(after command: Command, before: CraftDocument) throws {
    reconcileVariables()
    guard var variables else { return }
    if layers != before.layers { variables.activeDataSetID = nil }
    for i in variables.definitions.indices {
      let definition = variables.definitions[i]
      guard var frame = definition.pixelFrame,
            let old = before.layers.first(where: { $0.id == definition.layerID }),
            let current = layers.first(where: { $0.id == definition.layerID }) else { continue }
      let delta: Transform2D
      switch command {
      case .imageSize(let w, let h, _, _):
        delta = .scale(Double(w) / Double(before.width), Double(h) / Double(before.height))
      case .rotateCanvas(let turn): delta = turn.transform(width: before.width, height: before.height)
      case .transform(let id, let transform, _) where before.subtreeIDs(id).contains(old.id): delta = transform
      case .flip(let id, let horizontal) where id == old.id:
        guard case .raster(let surface) = old.content else { continue }
        delta = .translation(Double(old.x), Double(old.y))
          * (horizontal ? Transform2D(a: -1, tx: Double(surface.width)) : Transform2D(d: -1, ty: Double(surface.height)))
          * .translation(-Double(old.x), -Double(old.y))
      default: delta = try current.coordinateTransform * old.coordinateTransform.inverted()
      }
      frame.transform = delta * frame.transform
      variables.definitions[i].pixelFrame = frame
    }
    self.variables = variables
  }
  /// Drop bindings only when their owning layer/type is removed. Other layers' values survive.
  mutating func reconcileVariables() {
    guard var variables else { return }
    variables.definitions.removeAll { definition in
      !layers.contains(where: { $0.id == definition.layerID && definition.supports($0) })
    }
    let names = Set(variables.variableNames)
    for i in variables.dataSets.indices { variables.dataSets[i].values = variables.dataSets[i].values.filter { names.contains($0.key) } }
    if variables.definitions.isEmpty { variables.dataSets = []; variables.activeDataSetID = nil }
    self.variables = variables.isEmpty ? nil : variables
  }
}
