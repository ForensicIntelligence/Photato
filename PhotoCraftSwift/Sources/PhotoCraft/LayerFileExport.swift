import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

struct LayerFileExportSettings: Codable, Equatable, Sendable {
  enum Format: String, Codable, CaseIterable, Sendable {
    case bmp, jpeg, pdf, psd, tga, tiff, png8, png24, psb, photato
    var title: String { switch self { case .png8: "PNG-8"; case .png24: "PNG-24"; case .photato: "Photato (editable)"; case .jpeg: "JPEG"; default: rawValue.uppercased() } }
    var ext: String { switch self { case .png8, .png24: "png"; case .jpeg: "jpg"; default: rawValue } }
    var supportsICC: Bool { ![.bmp,.tga].contains(self) }
    var editable: Bool { [.psd,.psb,.photato].contains(self) }
  }
  var format: Format = .psd
  var prefix = ""
  var visibleOnly = false
  var trim = false
  var includeICC = true
  var transparency = true
  var jpegQuality = 8
  var tiffCompression: RasterEncodingOptions.TIFFCompression = .lzw
  var pngInterlaced = false
  var paletteColors = 256
  var paletteDither: IndexedDither = .diffusion
  var paletteAmount: Float = 0.75
  var ids: [UUID] = []
  func validate() throws {
    guard prefix.utf8.count <= 64, prefix.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !"/\\:".unicodeScalars.contains($0) }),
      prefix != ".", prefix != "..", (0...12).contains(jpegQuality), (2...256).contains(paletteColors), paletteAmount.isFinite, (0...1).contains(paletteAmount),
      ids.count <= LayerLimits.maximumLayers, Set(ids).count == ids.count else { throw CraftError.invalid("Invalid layer export prefix, options or layer IDs.") }
    guard format != .photato || includeICC else { throw CraftError.invalid("Editable Photato exports always retain their interpreting color profile.") }
    guard format.supportsICC || !includeICC else { throw CraftError.unsupported("BMP and Targa layer exports do not embed an ICC profile; disable Include ICC Profile.") }
  }
  func layers(in document: CraftDocument) throws -> [Layer] {
    try validate(); try document.validate()
    guard document.animation == nil, document.videoTimeline == nil else { throw CraftError.unsupported("Use frame/video exports for a temporal document.") }
    let leaves = document.layers.reversed().filter { !$0.isGroup }
    guard Set(ids).isSubset(of: Set(leaves.map(\.id))) else { throw CraftError.invalid("Choose existing individual layers for Layers to Files.") }
    let result = leaves.filter { layer in
      (ids.isEmpty || ids.contains(layer.id)) && (!visibleOnly || (layer.visible && document.ancestors(of: layer.id).allSatisfy(\.visible)))
    }
    guard !result.isEmpty else { throw CraftError.invalid("No layers match the export settings.") }; return result
  }
}
struct LayerFileRecord: Codable, Sendable {
  let id: UUID
  let layerName: String
  let file: String
  let width: Int
  let height: Int
  let bytes: Int
}
struct LayerFileProgress: Equatable, Sendable {
  var completed = 0
  var total = 0
  var current = ""
}
struct LayerFileIdentity: Sendable {
  let path: URL
  let device: UInt64
  let inode: UInt64
  let bytes: UInt64
  let modified: Date
  static func capture(_ path: URL) throws -> Self {
    let a = try FileManager.default.attributesOfItem(atPath: path.path)
    guard let device = a[.systemNumber] as? NSNumber, let inode = a[.systemFileNumber] as? NSNumber, let bytes = a[.size] as? NSNumber, let date = a[.modificationDate] as? Date else { throw CraftError.invalid("Could not identify a staged layer file.") }
    return .init(path: path, device: device.uint64Value, inode: inode.uint64Value, bytes: bytes.uint64Value, modified: date)
  }
  func matches(_ url: URL) -> Bool {
    guard let other = try? Self.capture(url) else { return false }
    return device == other.device && inode == other.inode && bytes == other.bytes && modified == other.modified
  }
}
struct PreparedLayerFiles: Sendable {
  let staging: URL
  let files: [LayerFileRecord]
  let manifest: Data
  func discard() { try? FileManager.default.removeItem(at: staging) }
  func archive(maximumBytes: Int = ImageAssetExport.maximumBytes) throws -> Data {
    guard (1...ImageAssetExport.maximumBytes).contains(maximumBytes) else { throw CraftError.invalid("Invalid layer archive budget.") }
    var output: [StoredZIP.File] = []; var used = manifest.count
    for file in files {
      try Task.checkCancellation()
      guard file.bytes <= maximumBytes - used else { throw CraftError.invalid("Layer files exceed the API ZIP limit; export fewer layers or use native file export.") }
      let data = try Data(contentsOf: staging.appendingPathComponent(file.file), options: .mappedIfSafe)
      guard data.count == file.bytes else { throw CraftError.invalid("A staged export changed before download.") }
      used += data.count; output.append(.init(name:file.file,data:data))
    }
    output.append(.init(name:"photato-layer-files.json",data:manifest))
    return try StoredZIP.encode(output,maximumBytes:maximumBytes)
  }
  func publish(to directory: URL) throws -> [LayerFileIdentity] {
    let destinations = files.map { directory.appendingPathComponent($0.file) }
    guard destinations.allSatisfy({ !FileManager.default.fileExists(atPath:$0.path) }) else { throw CraftError.invalid("A layer export already exists; choose another prefix or folder.") }
    var published: [LayerFileIdentity] = []
    do {
      for (file,destination) in zip(files,destinations) {
        try Task.checkCancellation()
        let source = staging.appendingPathComponent(file.file), identity = try LayerFileIdentity.capture(source)
        try FileManager.default.linkItem(at:source,to:destination)
        published.append(.init(path:destination,device:identity.device,inode:identity.inode,bytes:identity.bytes,modified:identity.modified))
      }
      try Task.checkCancellation(); return published
    } catch { Self.rollback(published); throw error }
  }
  static func rollback(_ files: [LayerFileIdentity]) {
    for file in files where file.matches(file.path) { try? FileManager.default.removeItem(at:file.path) }
  }
}
enum LayerFileExport {
  static func variation(_ document: CraftDocument, layer: Layer, options: LayerFileExportSettings) throws -> CraftDocument {
    var source = try ImageAssetSelection.document(document,ids:[layer.id],crop:options.trim ? .trim:.documentBounds,includingAncestors:true)
    source.profileIsUntagged = !options.includeICC
    return source
  }
  static func name(_ layer: Layer, index: Int, options: LayerFileExportSettings) -> String {
    let prefix = options.prefix.isEmpty ? "" : options.prefix + "_"
    return prefix + String(format:"%04d_",index) + ImageAssetExport.safeName(layer.name) + "." + options.format.ext
  }
  static func prepare(_ document: CraftDocument, options: LayerFileExportSettings, directory: URL,
    progress: @Sendable (LayerFileProgress) -> Void = { _ in }) throws -> PreparedLayerFiles {
    let layers = try options.layers(in:document)
    guard directory.isFileURL else { throw CraftError.invalid("Choose a local export folder.") }
    let staging = directory.appendingPathComponent(".photato-layer-files-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false)
    var records: [LayerFileRecord] = []
    do {
      for (index,layer) in layers.enumerated() {
        try Task.checkCancellation(); progress(.init(completed:index,total:layers.count,current:layer.name))
        let variation = try variation(document,layer:layer,options:options), name = name(layer,index:index,options:options), destination = staging.appendingPathComponent(name)
        try write(variation,options:options,to:destination)
        let bytes = (try FileManager.default.attributesOfItem(atPath:destination.path)[.size] as! NSNumber).intValue
        records.append(.init(id:layer.id,layerName:layer.name,file:name,width:variation.width,height:variation.height,bytes:bytes))
        progress(.init(completed:index+1,total:layers.count,current:layer.name))
      }
      let manifest = try JSONSerialization.data(withJSONObject:["version":1,"source":document.name,"format":options.format.rawValue,"visibleOnly":options.visibleOnly,"trim":options.trim,"includeICC":options.includeICC,"files":BrushAPI.json(records)],options:[.sortedKeys])
      try Task.checkCancellation(); return .init(staging:staging,files:records,manifest:manifest)
    } catch { try? FileManager.default.removeItem(at:staging); throw error }
  }
  static func flattened(_ source: CraftDocument, options: LayerFileExportSettings) throws -> CraftDocument {
    var target = try CraftDocument(width:source.width,height:source.height,depth:.u8,name:source.name)
    target.workingICC = source.depth == .f32 ? nil : source.workingICC; target.sourceICC = target.workingICC
    target.sourceMetadata = source.sourceMetadata; target.resolution = source.resolution; target.profileIsUntagged = !options.includeICC
    var surface = try ColorManagement.converted(Renderer.composite(source),from:source,to:target)
    if !options.transparency || [.jpeg,.bmp].contains(options.format) { surface.mapPixels { _,_,p in Pixel(p.r*p.a+1-p.a,p.g*p.a+1-p.a,p.b*p.a+1-p.a,1) } }
    target.layers[0].content = .raster(surface); target.layers[0].name = source.layers.first(where: { !$0.isGroup })?.name ?? "Export"
    return target
  }
  static func write(_ source: CraftDocument, options: LayerFileExportSettings, to url: URL) throws {
    try Task.checkCancellation()
    if options.format == .png8, source.width > PaletteQuantization.maximumPixels / source.height { throw CraftError.unsupported("PNG-8 palette processing exceeds8,388,608 pixels. Use PNG-24 or a smaller trimmed layer.") }
    switch options.format {
    case .psd,.psb: try PSDCodec.writeRasterLayers(source,to:url,format:options.format == .psd ? .psd : .psb)
    case .photato: try NativeArchive.write(source,to:url)
    case .tiff:
      let bytes = try DocumentIO.encode(source,format:.tiff,options:.init(tiffCompression:options.tiffCompression,tiffLayers:false)); try write(bytes,to:url)
    case .pdf: try write(pdf(source,includeICC:options.includeICC),to:url)
    case .png24,.png8,.jpeg,.bmp,.tga:
      var raster = try flattened(source,options:options)
      if options.format == .png8 {
        var settings = IndexedColorSettings(); settings.colors = options.paletteColors; settings.dither = options.paletteDither; settings.amount = options.paletteAmount; settings.transparency = options.transparency; settings.forced = .none
        try RestrictedModeInput.indexed(settings,in:raster).apply(to:&raster)
      }
      let type: UTType = [.png24,.png8].contains(options.format) ? .png : options.format == .jpeg ? .jpeg : options.format == .bmp ? .bmp : UTType(importedAs:"com.truevision.tga-image",conformingTo:.image)
      var encoding = RasterEncodingOptions()
      if options.format == .jpeg { encoding.jpegQuality=options.jpegQuality; encoding.jpegEmbedProfile=options.includeICC }
      if [.png24,.png8].contains(options.format) { encoding.pngInterlaced=options.pngInterlaced }
      let bytes = [.bmp,.tga].contains(options.format) ? try bitmap(raster,type:type) : try RasterIO.encoded(raster,type:type,options:encoding)
      try write(bytes,to:url)
    }
  }
  private static func bitmap(_ source:CraftDocument,type:UTType) throws -> Data {
    let surface = try Renderer.composite(source), pixels = try surface.rgbaData(depth:.u8)
    guard let provider = CGDataProvider(data:pixels as CFData),
      let image = CGImage(width:source.width,height:source.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:source.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { throw CraftError.invalid("Could not prepare the bitmap layer.") }
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes,type.identifier as CFString,1,nil) else { throw CraftError.unavailable("This native bitmap encoder is unavailable.") }
    CGImageDestinationAddImage(destination,image,[kCGImagePropertyDPIWidth:source.pixelsPerInch,kCGImagePropertyDPIHeight:source.pixelsPerInch] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CraftError.invalid("Could not encode the bitmap layer.") }
    try Task.checkCancellation(); return bytes as Data
  }
  private static func write(_ bytes: Data,to url: URL) throws {
    let writer = try AtomicFileWriter(to:url,maximumBytes:max(1,bytes.count)); try writer.append(bytes); try Task.checkCancellation(); try writer.commit()
  }
  static func pdf(_ source: CraftDocument,includeICC: Bool) throws -> Data {
    let bytes = NSMutableData(); guard let consumer = CGDataConsumer(data:bytes), let context = CGContext(consumer:consumer,mediaBox:nil,nil) else { throw CraftError.invalid("Could not create layer PDF.") }
    var size = CGRect(x:0,y:0,width:Double(source.width)*72/source.pixelsPerInch,height:Double(source.height)*72/source.pixelsPerInch)
    let original = try ColorManagement.image(Renderer.composite(source),in:source)
    let space = includeICC ? try ColorManagement.space(for:source) : CGColorSpaceCreateDeviceRGB()
    guard let image = original.copy(colorSpace:space) else { throw CraftError.invalid("Could not prepare PDF color space.") }
    let page = NSData(bytes:&size,length:MemoryLayout<CGRect>.size)
    context.beginPDFPage([kCGPDFContextMediaBox as String:page] as CFDictionary); context.draw(image,in:size); context.endPDFPage(); context.closePDF()
    try Task.checkCancellation(); return bytes as Data
  }
}
