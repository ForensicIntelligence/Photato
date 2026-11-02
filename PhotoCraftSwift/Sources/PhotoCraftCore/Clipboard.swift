import Foundation

public enum PastePlacement: String, Codable, Sendable {
  case centered, inPlace, into, outside
}

/// Native clipboard data retains editable layers, sample precision and document coordinates.
public struct ClipboardContent: Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case pixels, layers }
  public var kind: Kind
  public var document: CraftDocument
  public var bounds: IntRect
  /// Stored palette/bit identity; the pixel layer separately retains selection alpha.
  public var restrictedSamples: RestrictedModeRaster?
  public init(kind: Kind, document: CraftDocument, bounds: IntRect, restrictedSamples: RestrictedModeRaster? = nil) throws {
    self.kind = kind
    self.document = document
    self.bounds = bounds
    self.restrictedSamples = restrictedSamples
    try validate()
  }
  public func validate() throws {
    try document.validate()
    _ = try Surface(width: bounds.width, height: bounds.height)
    guard !document.layers.isEmpty, abs(Double(bounds.x)) <= 1_000_000,
      abs(Double(bounds.y)) <= 1_000_000, document.selection == nil,
      document.selectionMask == nil
    else { throw CraftError.invalid("Invalid clipboard contents.") }
    if kind == .pixels {
      guard document.layers.count == 1, case .raster(let pixels) = document.layers[0].content,
        pixels.width == bounds.width, pixels.height == bounds.height,
        document.layers[0].x == bounds.x, document.layers[0].y == bounds.y,
        document.layers[0].affine == nil, document.layers[0].mask == nil,
        document.layers[0].vectorMask == nil, document.layers[0].maskProperties == nil,
        document.layers[0].style == nil, document.layers[0].smartObject == nil,
        document.layers[0].smartFilters == nil, document.layers[0].warp == nil,
        document.layers[0].visible,
        document.layers[0].opacity == 1, document.layers[0].blendMode == .normal,
        !document.layers[0].isClipped
      else {
        throw CraftError.invalid("Invalid pixel clipboard contents.")
      }
    }
    if let samples = restrictedSamples {
      try samples.validate()
      guard kind == .pixels, samples.width == bounds.width, samples.height == bounds.height,
        document.restrictedMode == nil, document.modeDescriptor == nil,
        document.workingICC == samples.profile, document.depth == .u8,
        case .raster(let pixels) = document.layers[0].content else {
        throw CraftError.invalid("Clipboard samples do not match their pixel layout or profile.")
      }
      let expanded = try samples.surface()
      for y in 0..<bounds.height { try Task.checkCancellation(); for x in 0..<bounds.width {
        let actual = pixels.pixel(x: x, y: y), stored = expanded.pixel(x: x, y: y)
        guard actual.a <= stored.a, actual.a == 0 || actual.rgb == stored.rgb else {
          throw CraftError.invalid("Clipboard pixels differ from their retained samples.")
        }
      } }
    }
  }
  public static func pixels(
    _ surface: Surface, x: Int = 0, y: Int = 0, resolution: Double = 72, workingICC: Data? = nil,
    restrictedSamples: RestrictedModeRaster? = nil, untagged: Bool = false
  )
    throws -> Self
  {
    var doc = try CraftDocument(width: surface.width, height: surface.height, depth: surface.depth)
    var layer = Layer(name: "Layer", content: .raster(surface))
    layer.x = x
    layer.y = y
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    doc.resolution = resolution
    doc.workingICC = workingICC
    doc.profileIsUntagged = untagged ? true : nil
    return try Self(
      kind: .pixels, document: doc,
      bounds: IntRect(x: x, y: y, width: surface.width, height: surface.height), restrictedSamples: restrictedSamples)
  }
  private struct Envelope: Codable {
    var magic = "PhotatoClipboard"
    var version = 1
    var kind: Kind
    var bounds: IntRect
    var archive: Data
    var restrictedSamples: RestrictedModeRaster?
  }
  public func encoded() throws -> Data {
    try validate()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(
      Envelope(
        version: restrictedSamples == nil ? 1 : 2, kind: kind, bounds: bounds,
        archive: NativeArchive.encode(document), restrictedSamples: restrictedSamples))
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Clipboard exceeds the 512 MiB transfer limit.")
    }
    return data
  }
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Clipboard exceeds the 512 MiB transfer limit.")
    }
    let envelope = try PropertyListDecoder().decode(Envelope.self, from: data)
    guard envelope.magic == "PhotatoClipboard", (1...2).contains(envelope.version),
      envelope.version >= 2 || envelope.restrictedSamples == nil else {
      throw CraftError.unsupported("Unsupported Photato clipboard version.")
    }
    return try Self(
      kind: envelope.kind, document: NativeArchive.decode(envelope.archive),
      bounds: envelope.bounds, restrictedSamples: envelope.restrictedSamples)
  }
  public func newDocument(name: String) throws -> CraftDocument {
    try validate()
    if let samples = restrictedSamples ?? document.restrictedMode,
      case .raster(let pixels) = document.layers[0].content, pixels == (try samples.surface()) {
      var target = try CraftDocument(width: bounds.width, height: bounds.height, name: name)
      target.resolution = document.pixelsPerInch
      return try target.replacingRestrictedMode(samples)
    }
    var target = try CraftDocument(
      width: bounds.width, height: bounds.height, depth: document.depth,
      name: name)
    target.layers = []
    target.activeLayerID = nil
    target.resolution = document.pixelsPerInch
    target.workingICC = document.workingICC
    target.profileIsUntagged = document.profileIsUntagged
    target.modeDescriptor = document.modeDescriptor
    try paste(into: &target, placement: .centered, center: nil)
    try target.validate()
    return target
  }
  func paste(into target: inout CraftDocument, placement: PastePlacement, center: PathPoint?) throws
  {
    try validate()
    guard document.workingICC == target.workingICC else {
      throw CraftError.unsupported(
        "Convert clipboard colours to the destination working profile before pasting.")
    }
    let masked = placement == .into || placement == .outside
    guard !masked || (target.selection != nil && kind == .pixels) else {
      throw CraftError.invalid("Paste Into and Paste Outside need a pixel image and a selection.")
    }
    let destination: PathPoint
    if let selection = target.selection, placement != .inPlace {
      destination = PathPoint(
        Double(selection.x) + Double(selection.width) / 2,
        Double(selection.y) + Double(selection.height) / 2)
    } else {
      destination = center ?? PathPoint(Double(target.width) / 2, Double(target.height) / 2)
    }
    guard destination.x.isFinite, destination.y.isFinite,
      abs(destination.x) <= 1_000_000, abs(destination.y) <= 1_000_000
    else {
      throw CraftError.invalid("Invalid paste destination.")
    }
    let dx =
      placement == .inPlace
      ? 0 : Int((destination.x - Double(bounds.width) / 2).rounded()) - bounds.x
    let dy =
      placement == .inPlace
      ? 0 : Int((destination.y - Double(bounds.height) / 2).rounded()) - bounds.y
    if target.restrictedMode != nil {
      try RestrictedClipboard.paste(self, into: &target, placement: placement, dx: dx, dy: dy)
      return
    }
    let parent: UUID?
    let insertion: Int
    if let index = target.activeIndex {
      let active = target.layers[index]
      parent = active.isGroup ? active.id : active.parentID
      insertion = active.isGroup ? index : index + 1
    } else {
      parent = nil
      insertion = target.layers.count
    }
    if let parent, target.isLocked(parent) {
      throw CraftError.invalid("Unlock the destination group before pasting.")
    }
    guard target.layers.count + document.layers.count <= LayerLimits.maximumLayers else {
      throw CraftError.invalid("Layer limit reached.")
    }
    let mapping = Dictionary(uniqueKeysWithValues: document.layers.map { ($0.id, UUID()) })
    var patternIDs: [String: String] = [:]
    for layer in document.layers {
      if case .patternFill(let fill) = layer.content, patternIDs[fill.patternID] == nil,
        let pattern = document.pattern(fill.patternID)
      {
        patternIDs[fill.patternID] = try target.installPattern(pattern)
      }
    }
    var copies: [Layer] = []
    for original in document.layers {
      try Task.checkCancellation()
      var layer = original
      layer.id = mapping[original.id]!
      layer.parentID = original.parentID.flatMap { mapping[$0] } ?? parent
      layer.x += dx
      layer.y += dy
      if let stack = layer.smartFilters {
        layer.smartFilters?.maskProperties.transform = .translation(Double(dx), Double(dy)) * stack.maskProperties.transform
      }
      if case .patternFill(var fill) = layer.content {
        fill.patternID = patternIDs[fill.patternID] ?? fill.patternID
        try fill.transform(by: .translation(Double(dx), Double(dy)))
        layer.content = .patternFill(fill)
      }
      if let vector = layer.vectorMask {
        layer.vectorMask?.path = vector.path.transformed(.translation(Double(dx), Double(dy)))
      }
      if case .raster(let pixels) = layer.content {
        layer.content = .raster(try pixels.converted(to: target.depth))
        if let descriptor = target.modeDescriptor {
          let native: NativeModeRaster
          if let retained = original.nativeMode {
            native = try retained.converted(to: descriptor.mode, depth: target.depth,
              profile: descriptor.profile, intent: descriptor.intent)
          } else {
            native = try NativeModeRaster.converting(pixels, to: descriptor.mode, depth: target.depth,
              profile: descriptor.profile, intent: descriptor.intent, sourceProfile: document.workingICC)
          }
          layer.nativeMode = native; layer.content = .raster(try native.surface())
        } else { layer.nativeMode = nil }
      }
      if let mask = layer.mask { layer.mask = try mask.converted(to: target.depth) }
      if masked {
        layer = try layer.creatingPixelMask(
          placement == .outside ? .hideSelection : .revealSelection,
          in: target)
        layer.maskProperties?.linked = false
      }
      copies.append(layer)
    }
    target.layers.insert(contentsOf: copies, at: insertion)
    target.activeLayerID = document.activeLayerID.flatMap { mapping[$0] } ?? copies.last?.id
    target.selection = nil
    target.selectionMask = nil
  }
}

extension Surface {
  public func converted(to depth: PixelDepth) throws -> Surface {
    if depth == self.depth { return self }
    if width>Surface.maximumDensePixels/height || mappedBytes>0 {
      let output=try Surface(width:width,height:height,depth:depth,fill:defaultPixel)
      let builder=try Surface.PagedBuilder(template:output),columns=(width+63)/64
      var keys=storedTileKeys.makeIterator(),next=keys.next()
      while let first=next {
        try Task.checkCancellation()
        let row=first/columns;var end=first+1;next=keys.next()
        while let key=next,key==end,key/columns==row,end-first<32 {end+=1;next=keys.next()}
        let left=first%columns*64,top=row*64
        var patch=try Surface(width:min(width-left,(end-first)*64),height:min(64,height-top),depth:depth,fill:defaultPixel)
        for y in 0..<patch.height {try Task.checkCancellation();for x in 0..<patch.width {
          let value=pixel(x:left+x,y:top+y).quantized(depth)
          // Match the legacy value comparison, including signed-zero folding.
          if value != output.defaultPixel {patch.setPixel(x:x,y:y,value)}
        }}
        try builder.append(patch,atX:left,atY:top)
      }
      return try builder.finish()
    }
    var output = try Surface(width: width, height: height, depth: depth, fill: defaultPixel)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let value = pixel(x: x, y: y).quantized(depth)
        if value != output.defaultPixel { output.setPixel(x: x, y: y, value) }
      }
    }
    return output
  }
}
