import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

public enum SmartObjectIO {
  public static let maximumCanvasPixels = 8_388_608
  public static let maximumPagedRGBPixels = Surface.maxPixels
  @TaskLocal static var nesting = 0
  public static func withNesting<T>(_ operation: () throws -> T) throws -> T {
    guard nesting < 8 else { throw CraftError.unsupported("Embedded Smart Object nesting exceeds eight levels.") }
    return try $nesting.withValue(nesting + 1, operation: operation)
  }
  public static func decode(_ data: Data, fileName: String) throws -> CraftDocument {
    try withNesting {
      guard data.count <= SmartObject.maximumSourceBytes else {
        throw CraftError.invalid("Embedded source exceeds 64 MiB.")
      }
      if data.starts(with: Data("PHOTATO\0".utf8)) || data.starts(with: Data("bplist".utf8)) {
        let document = try NativeArchive.decodePaged(data, heapByteLimit: 256 * 1_024 * 1_024)
        try check(document); return document
      }
      if RawSourceIO.recognizes(data) { return try RawSourceIO.open(data,fileName:fileName) }
      let width: Int, height: Int
      if data.starts(with: Data("8BPS".utf8)), data.count >= 26 {
        width = data[18..<22].reduce(0) { ($0 << 8) | Int($1) }
        height = data[14..<18].reduce(0) { ($0 << 8) | Int($1) }
      } else if let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int {
        width = w; height = h
      } else { throw CraftError.unsupported("Unsupported embedded image format.") }
      guard width > 0, height > 0,width<=Surface.maxDimension,height<=Surface.maxDimension,
        width <= maximumPagedRGBPixels / height else {
        throw CraftError.unsupported("Embedded source exceeds the native canvas extent.")
      }
      let name=(fileName as NSString).deletingPathExtension
      let document = try data.starts(with:Data("8BPS".utf8)) ? PSDCodec.readPaged(data,name:name,heapByteLimit:256*1_024*1_024):RasterIO.read(data,name:name)
      try check(document); return document
    }
  }
  public static func sourceDocument(_ object: SmartObject) throws -> CraftDocument {
    if let settings = object.rawDevelopment { return try RawSourceIO.open(object.data,fileName:object.fileName,settings:settings) }
    let document = try decode(object.data, fileName: object.fileName)
    guard document.width == object.width, document.height == object.height else {
      throw CraftError.invalid("Embedded source dimensions disagree with its metadata.")
    }
    return document
  }
  public static func check(_ document: CraftDocument) throws {
    try document.validate()
    let pagedRGB=document.colorMode == .rgb && document.inkMode==nil && document.restrictedMode==nil
    guard (pagedRGB || document.width <= maximumCanvasPixels / document.height),
      document.estimatedBytes <= 256 * 1_024 * 1_024 else {
      throw CraftError.unsupported("Smart Objects require at most256 MiB owned content; non-RGB sources retain8,388,608-pixel admission. Encoded sources retain the64 MiB limit.")
    }
  }
  public static func embedded(document: CraftDocument, in parent: CraftDocument,
    originalData: Data? = nil, fileName: String? = nil) throws -> (SmartObject, Surface) {
    if let originalData, RawSourceIO.recognizes(originalData), let object = document.layers.first?.smartObject, object.rawDevelopment != nil {
      return (object,try ColorManagement.converted(sourceComposite(document),from:document,to:parent))
    }
    try check(document)
    let data = try originalData ?? NativeArchive.encodeChunked(document)
    let type: String
    if originalData == nil || data.starts(with: Data("PHOTATO\0".utf8)) || data.starts(with: Data("bplist".utf8)) {
      type = "application/vnd.photato.document"
    } else if data.starts(with: Data("8BPS".utf8)) {
      type = data.count > 5 && data[5] == 2 ? "application/x-photoshop" : "image/vnd.adobe.photoshop"
    } else if let source = CGImageSourceCreateWithData(data as CFData, nil),
      let identifier = CGImageSourceGetType(source) as String?, let mime = UTType(identifier)?.preferredMIMEType {
      type = mime
    } else { throw CraftError.unsupported("Unsupported embedded source format.") }
    let name = fileName ?? "Contents.photato"
    let object = try SmartObject(fileName: name, mediaType: type, data: data,
      width: document.width, height: document.height, resolution: document.pixelsPerInch)
    let pixels = try ColorManagement.converted(sourceComposite(document), from: document, to: parent)
    return (object, pixels)
  }
  private static func sourceComposite(_ document:CraftDocument)throws->Surface {
    if document.colorMode == .rgb,document.width>maximumCanvasPixels/document.height {return try Renderer.compositePaged(document)}
    return try Renderer.composite(document)
  }
  public static func placed(data: Data, fileName: String, in parent: CraftDocument,
    fit: Bool = true) throws -> Layer {
    if PDFImport.recognizes(data) {
      var settings = PDFImportSettings();settings.resolution = 72
      return try PDFSmartObjectIO.placed(data,fileName:fileName,in:parent,settings:settings,fit:fit)
    }
    return try placed(document:decode(data,fileName:fileName),data:data,fileName:fileName,in:parent,fit:fit)
  }
  public static func placed(document: CraftDocument, data: Data, fileName: String,
    in parent: CraftDocument, fit: Bool = true) throws -> Layer {
    let (object, pixels) = try embedded(document: document, in: parent, originalData: data, fileName: fileName)
    var layer = Layer(name: (fileName as NSString).deletingPathExtension, content: .raster(pixels))
    layer.smartObject = object
    let scale = fit ? min(1, min(Double(parent.width) / Double(document.width), Double(parent.height) / Double(document.height))) : 1
    layer.x = Int((Double(parent.width) - Double(document.width) * scale) / 2)
    layer.y = Int((Double(parent.height) - Double(document.height) * scale) / 2)
    layer.affine = .scale(scale, scale)
    return layer
  }
  public static func rasterizationCommand(_ layer: Layer, in document: CraftDocument) throws -> Command {
    let input = try PDFSmartObjectIO.renderedLayer(layer,in:document)
    return .rasterize(layer.id,try Renderer.layerSurface(input,in:document))
  }
  public static func convert(in document: CraftDocument, selected: Set<UUID>) throws -> Command {
    try document.validate()
    let roots = document.layers.filter { selected.contains($0.id) && Set(document.ancestors(of: $0.id).map(\.id)).isDisjoint(with: selected) }
    guard let first = roots.first, selected.isSubset(of: Set(document.layers.map(\.id))),
      roots.allSatisfy({ $0.parentID == first.parentID }) else {
      throw CraftError.invalid("Select one or more layers in the same group.")
    }
    let ids = roots.reduce(into: Set<UUID>()) { $0.formUnion(document.subtreeIDs($1.id)) }
    // A selected clipping layer must retain its selected base inside the source.
    guard document.layers.filter({ ids.contains($0.id) && $0.isClipped }).allSatisfy({
      document.clippingBase(for: $0.id).map { ids.contains($0.id) } == true
    }) else { throw CraftError.invalid("Include the clipping base when converting clipped layers.") }
    var source = document
    source.id = UUID(); source.name = roots.count == 1 ? first.name : "Smart Object Contents"
    source.layers = document.layers.filter { ids.contains($0.id) }
    source.activeLayerID = source.layers.last?.id
    source.selection = nil; source.selectionMask = nil; source.paths = nil; source.sourceMetadata = nil
    for i in source.layers.indices where roots.contains(where: { $0.id == source.layers[i].id }) { source.layers[i].parentID = nil }
    if roots.count == 1, let i = source.layers.firstIndex(where: { $0.id == first.id }), !first.isGroup {
      source.layers[i].blendMode = .normal
      source.layers[i].opacity = 1; source.layers[i].visible = true
    }
    let needsCanvas = source.layers.contains { $0.isCanvasFill || $0.style != nil || $0.isGroup && $0.mask != nil }
    let bounds = needsCanvas ? nil : try LayerLayout.union(roots.compactMap { try Renderer.layoutBounds($0, in: document, stored: true) })
    let rect = bounds ?? IntRect(x: 0, y: 0, width: document.width, height: document.height)
    let shift = Transform2D.translation(-Double(rect.x), -Double(rect.y))
    for i in source.layers.indices {
      source.layers[i].x -= rect.x; source.layers[i].y -= rect.y
      if let mask = source.layers[i].vectorMask { source.layers[i].vectorMask?.path = mask.path.transformed(shift) }
      if case .text(var text) = source.layers[i].content {
        text.layoutWidth = text.layoutWidth ?? document.width; text.layoutHeight = text.layoutHeight ?? document.height
        source.layers[i].content = .text(text)
      }
    }
    source.width = rect.width; source.height = rect.height
    let (object, pixels) = try embedded(document: source, in: document)
    var layer = Layer(name: roots.count == 1 ? first.name : "Smart Object", content: .raster(pixels))
    layer.smartObject = object; layer.x = rect.x; layer.y = rect.y
    if roots.count == 1, !first.isGroup {
      layer.blendMode = first.blendMode; layer.opacity = first.opacity; layer.visible = first.visible
    }
    return .embedSmartObject(selected, layer)
  }
  public static func replacement(in parent: CraftDocument, layerID: UUID, source: CraftDocument,
    data: Data? = nil, fileName: String? = nil, preserveSize: Bool = true, allInstances: Bool = true) throws -> Command {
    let (object, pixels) = try embedded(document: source, in: parent, originalData: data, fileName: fileName)
    guard let old = parent.layers.first(where: { $0.id == layerID })?.smartObject else { throw CraftError.invalid("Select a Smart Object.") }
    var caches: [UUID: Surface] = [:], modes: [ImageStackMode: Surface] = [:]
    for layer in parent.layers where layer.id == layerID || allInstances && layer.smartObject?.sourceID == old.sourceID {
      if let mode = layer.smartObject?.stackMode {
        guard object.rawDevelopment == nil else { throw CraftError.invalid("Remove stack modes before replacing a stack with a camera RAW source.") }
        let cache = try modes[mode] ?? ImageStack.render(source, mode: mode, in: parent)
        modes[mode] = cache; caches[layer.id] = cache
      }
    }
    return .replaceSmartObject(layerID, object, pixels, preserveSize: preserveSize, allInstances: allInstances, instancePixels: caches)
  }
}
