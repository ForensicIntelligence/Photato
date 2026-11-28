import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PhotoCraftCore

/// Native Apple sensor decoder. Never substitutes CGImageSource previews for RAW output.
public enum RawSourceIO {
  public static let maximumPixels = Surface.maximumDensePixels
  public static let mediaTypes = ["image/x-camera-raw","image/x-adobe-dng"]
  public static let contentType = UTType("public.camera-raw-image")!
  public struct Info: Codable, Equatable, Sendable {
    public let type: String, model: String
    public let nativeWidth: Int, nativeHeight: Int
    public let decoderVersion: String
    public let supportedDecoders: [String]
    public let temperature: Float, tint: Float
    public let lensCorrectionSupported: Bool, highlightRecoverySupported: Bool
    public let lensCorrectionEnabled: Bool, highlightRecoveryEnabled: Bool
  }
  public static func type(_ data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let type = CGImageSourceGetType(source) as String? else { return nil }
    if UTType(type)?.conforms(to: contentType) == true { return type }
    // A TIFF classification can identify a RAW's thumbnail instead of the
    // sensor image. Require a DNG marker or a Nikon CFA directory before hinting.
    guard type == UTType.tiff.identifier, data.count <= SmartObject.maximumSourceBytes,
      TIFFContainer.isClassic(data),
      let root = try? TIFFContainer(data, metadata: false, additionalTags: [271, 50706]) else { return nil }
    if isDNG(root) { return "com.adobe.raw-image" }
    guard isNikonCamera(root),
      let sensor = try? TIFFContainer(data, metadata: false, additionalTags: [33421, 33422], inspectSubIFDs: true),
      hasNikonMosaic(sensor) else { return nil }
    return "com.nikon.raw-image"
  }
  public static func recognizes(_ data: Data) -> Bool { type(data) != nil }
  public static func recognizes(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
      let type = CGImageSourceGetType(source) as String? else { return false }
    if UTType(type)?.conforms(to: contentType) == true { return true }
    guard type == UTType.tiff.identifier,
      let source = try? PSDFileSource(url, maximumBytes: SmartObject.maximumSourceBytes),
      let tiff = try? TIFFContainer(file: source, metadata: false, additionalTags: [271, 50706]),
      !tiff.isBigTIFF else { return false }
    if isDNG(tiff) { return true }
    guard isNikonCamera(tiff),
      let sensor = try? TIFFContainer(file: source, metadata: false, additionalTags: [33421, 33422], inspectSubIFDs: true)
    else { return false }
    return hasNikonMosaic(sensor)
  }

  private static func isDNG(_ tiff: TIFFContainer) -> Bool {
    guard let version = tiff.root.fields[50706] else { return false }
    return version.type == 1 && version.count == 4 && version.data.first == 1
  }

  private static func isNikonCamera(_ tiff: TIFFContainer) -> Bool {
    guard let make = tiff.root.fields[271], make.type == 2, (5...128).contains(make.count),
      let brand = String(bytes: make.data.prefix { $0 != 0 }, encoding: .ascii) else { return false }
    return brand == "NIKON" || brand == "NIKON CORPORATION"
  }

  private static func hasNikonMosaic(_ tiff: TIFFContainer) -> Bool {
    func containsMosaic(_ directory: TIFFContainer.Directory) -> Bool {
      if let interpretation = directory.fields[262], interpretation.type == 3, interpretation.count == 1,
        tiff.order.number(interpretation.data, 0, 2) == 32_803,
        let repeatSize = directory.fields[33421], repeatSize.type == 3, repeatSize.count == 2,
        let pattern = directory.fields[33422], pattern.type == 1,
        (directory.fields[273] != nil && directory.fields[279] != nil)
          || (directory.fields[324] != nil && directory.fields[325] != nil) {
        let rows = tiff.order.number(repeatSize.data, 0, 2)
        let columns = tiff.order.number(repeatSize.data, 2, 2)
        if (1...16).contains(rows), (1...16).contains(columns), pattern.count == rows * columns { return true }
      }
      return directory.fields[330]?.children.contains(where: containsMosaic) == true
    }
    return containsMosaic(tiff.root)
  }
  static func decoder(_ data: Data,version: String? = nil) throws -> (CIRAWFilter,Info) {
    try Task.checkCancellation()
    guard !data.isEmpty,data.count <= SmartObject.maximumSourceBytes,let type = type(data),
      let raw = CIRAWFilter(imageData:data,identifierHint:type) else { throw CraftError.unsupported("This file is not a supported camera RAW image, or exceeds 64 MiB.") }
    if let version {
      guard raw.supportedDecoderVersions.map(\.rawValue).contains(version) else { throw CraftError.unsupported("The saved RAW decoder version is unavailable on this Mac.") }
      raw.decoderVersion = CIRAWDecoderVersion(rawValue:version)
      guard raw.decoderVersion.rawValue == version else { throw CraftError.unsupported("The requested RAW decoder could not be selected.") }
    }
    let size = raw.nativeSize
    guard size.width.isFinite,size.height.isFinite,size.width >= 1,size.height >= 1,
      size.width <= CGFloat(Surface.maxDimension),size.height <= CGFloat(Surface.maxDimension),size.width*size.height <= CGFloat(maximumPixels),
      size.width.rounded() == size.width,size.height.rounded() == size.height else { throw CraftError.unsupported("The RAW decoder returned invalid sensor dimensions or exceeded 36 megapixels.") }
    let versions = raw.supportedDecoderVersions.map(\.rawValue)
    guard !raw.decoderVersion.rawValue.isEmpty,versions.contains(raw.decoderVersion.rawValue),raw.neutralTemperature.isFinite,raw.neutralTint.isFinite else { throw CraftError.unsupported("This camera has no available native RAW decoder.") }
    let properties = raw.properties
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String:Any]
    let model = (tiff?[kCGImagePropertyTIFFModel as String] as? String) ?? "Camera RAW"
    var highlightSupported = false, highlightEnabled = false
    if #available(macOS 26,*) { highlightSupported = raw.isHighlightRecoverySupported; highlightEnabled = raw.isHighlightRecoveryEnabled }
    let info = Info(type:type,model:String(model.prefix(256)),nativeWidth:Int(size.width),nativeHeight:Int(size.height),decoderVersion:raw.decoderVersion.rawValue,supportedDecoders:versions,temperature:raw.neutralTemperature,tint:raw.neutralTint,lensCorrectionSupported:raw.isLensCorrectionSupported,highlightRecoverySupported:highlightSupported,lensCorrectionEnabled:raw.isLensCorrectionEnabled,highlightRecoveryEnabled:highlightEnabled)
    return (raw,info)
  }
  public static func inspect(_ data: Data,decoderVersion: String? = nil) throws -> Info { try decoder(data,version:decoderVersion).1 }
  public static func read(_ url: URL,depth: PixelDepth = .u16) throws -> CraftDocument {
    try prepareLocal(url, depth: depth).document
  }

  public static func prepareLocal(_ url: URL, depth: PixelDepth = .u16) throws
    -> (document: CraftDocument, dngSource: RawDNGSource?) {
    let prepared = try prepareLocalSettings(url, depth: depth)
    if case .embeddedDNG(let dng) = prepared.source { return (prepared.document, dng) }
    return (prepared.document, nil)
  }

  public static func prepareLocalSettings(_ url: URL, depth: PixelDepth = .u16) throws
    -> (document: CraftDocument, source: RawSettingsSource?) {
    let input = try PSDFileSource(url, maximumBytes: SmartObject.maximumSourceBytes)
    let data = try input.bytes(at: 0, count: input.count)
    let related = try relatedXMP(for: url)
    let settings = try related?.settings.map { try compatibleStoredSettings($0, in: data) }
    let document = try open(data, fileName: url.lastPathComponent, settings: settings, depth: depth)
    let safeSource = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
    let source: RawSettingsSource?
    if safeSource, document.layers.first?.smartObject?.mediaType == "image/x-adobe-dng", TIFFContainer.isClassic(data) {
      source = .embeddedDNG(RawDNGSource(url: url, original: data, sidecar: related))
    } else if safeSource, document.layers.first?.smartObject?.mediaType == "image/x-camera-raw" {
      let existing = try related ?? relatedXMP(for: url, requireAdjustments: false)
      source = .sidecar(RawSidecarSource(url: url, original: data, existing: existing))
    } else {
      source = nil
    }
    try input.validateUnchanged()
    return (document, source)
  }
  public static func open(_ data: Data, fileName: String, settings requested: RawDevelopment? = nil,
    depth: PixelDepth = .u16) throws -> CraftDocument {
    try Task.checkCancellation()
    guard !data.isEmpty, data.count <= SmartObject.maximumSourceBytes else {
      throw CraftError.invalid("Camera RAW source must contain 1 byte to 64 MiB.")
    }
    let options = type(data).map { [kCGImageSourceTypeIdentifierHint: $0] as CFDictionary }
    let source = CGImageSourceCreateWithData(data as CFData, options)
    let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    let metadata: [String: Data]?
    if let source, let properties { metadata = try RasterMetadata.capture(source, properties: properties) }
    else { metadata = nil }
    let embedded = (metadata?[RasterMetadata.xmpKey]).flatMap { try? CameraRawXMP.readStored($0) }
    let initial = try requested ?? compatibleStoredSettings(embedded ?? .init(), in: data)
    let (pixels, settings, info) = try render(data, settings: initial, depth: depth)
    var name = URL(fileURLWithPath:fileName).lastPathComponent
    if (name as NSString).pathExtension.isEmpty { name += "." + (UTType(info.type)?.preferredFilenameExtension ?? "raw") }
    var document = try CraftDocument(width:pixels.width,height:pixels.height,depth:depth,name:(name as NSString).deletingPathExtension)
    document.sourceMetadata = metadata
    if let dpi = properties?[kCGImagePropertyDPIWidth] as? Double, dpi.isFinite, (1...100_000).contains(dpi) {
      document.resolution = dpi
    }
    var object = try SmartObject(fileName:name.isEmpty ? "Source.raw" : name,mediaType:info.type == "com.adobe.raw-image" ? "image/x-adobe-dng" : "image/x-camera-raw",data:data,width:pixels.width,height:pixels.height,rawDevelopment:settings)
    object.resolution = document.pixelsPerInch
    var layer = Layer(name:document.name,content:.raster(pixels)); layer.smartObject = object
    document.layers = [layer]; document.activeLayerID = layer.id
    try document.validate(); return document
  }
  static func compatibleStoredSettings(_ settings: RawDevelopment, in data: Data) throws -> RawDevelopment {
    guard settings.decoderVersion != nil || settings.highlightRecovery == true || settings.lensCorrection == true else {
      return settings
    }
    var availableSettings = settings
    let available = try inspect(data)
    if let version = settings.decoderVersion, !available.supportedDecoders.contains(version) {
      availableSettings.decoderVersion = nil
    }
    if !available.highlightRecoverySupported { availableSettings.highlightRecovery = nil }
    if !available.lensCorrectionSupported { availableSettings.lensCorrection = nil }
    return availableSettings
  }

  public static func render(_ data: Data,settings requested: RawDevelopment,depth: PixelDepth) throws -> (Surface,RawDevelopment,Info) {
    try requested.validate()
    let (raw,info) = try decoder(data,version:requested.decoderVersion)
    var settings = requested; settings.decoderVersion = info.decoderVersion
    if let temperature = settings.temperature { raw.neutralTemperature = temperature }
    if let tint = settings.tint { raw.neutralTint = tint }
    raw.exposure = settings.exposure; raw.boostAmount = settings.boost; raw.boostShadowAmount = settings.shadowBoost
    raw.extendedDynamicRangeAmount = settings.extendedRange
    if let value = settings.lensCorrection {
      guard info.lensCorrectionSupported || !value else { throw CraftError.unsupported("Lens correction is not supported for this RAW source.") }; raw.isLensCorrectionEnabled = value
    }
    if let value = settings.highlightRecovery {
      guard info.highlightRecoverySupported || !value else { throw CraftError.unsupported("Highlight recovery requires a supported source and macOS26 or newer.") }
      if #available(macOS 26,*) { raw.isHighlightRecoveryEnabled = value }
    }
    raw.scaleFactor = 1; raw.isDraftModeEnabled = false
    guard let image = raw.outputImage else { throw CraftError.unsupported("RAW sensor decoding failed. No embedded preview was substituted.") }
    let bounds = image.extent
    guard !bounds.isNull,!bounds.isInfinite,bounds.width.isFinite,bounds.height.isFinite,bounds.origin.x.isFinite,bounds.origin.y.isFinite,
      bounds.width >= 1,bounds.height >= 1,bounds.width <= CGFloat(Surface.maxDimension),bounds.height <= CGFloat(Surface.maxDimension),bounds.width*bounds.height <= CGFloat(maximumPixels),bounds.width.rounded() == bounds.width,bounds.height.rounded() == bounds.height else { throw CraftError.unsupported("RAW sensor output has invalid or oversized dimensions.") }
    let w = Int(bounds.width), h = Int(bounds.height)
    let space = CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!
    let context = CIContext(options:[.workingColorSpace:space,.outputColorSpace:space,.cacheIntermediates:false])
    var pixels = try Surface(width:w,height:h,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    // Bounded rows avoid a second full-sized Float32 image allocation. Core Image
    // uses bottom-up bounds but writes top-down bitmap rows, after EXIF orientation.
    let rows = min(64,h); var buffer = [Float](repeating:0,count:w*rows*4)
    for y in stride(from:0,to:h,by:rows) {
      try Task.checkCancellation(); let count = min(rows,h-y)
      let rect = CGRect(x:bounds.minX,y:bounds.minY+CGFloat(h-y-count),width:CGFloat(w),height:CGFloat(count))
      context.render(image,toBitmap:&buffer,rowBytes:w*16,bounds:rect,format:.RGBAf,colorSpace:space)
      for row in 0..<count { for x in 0..<w {
        let offset = (row*w+x)*4
        let p = Pixel(buffer[offset],buffer[offset+1],buffer[offset+2],buffer[offset+3])
        guard p.isFinite else { throw CraftError.invalid("The RAW decoder produced nonfinite sensor pixels.") }
        if depth == .f32 { pixels.setLinearPixel(x:x,y:y+row,p) } else { pixels.setPixel(x:x,y:y+row,SRGBTransfer.encoded(p)) }
      } }
    }
    try Task.checkCancellation()
    pixels = try CameraRawEngine.develop(pixels,settings:settings.adjustments,maximumPixels:maximumPixels)
    return (pixels,settings,info)
  }
  public static func command(in document: CraftDocument,layerID: UUID,settings: RawDevelopment,allInstances: Bool = true) throws -> Command {
    guard let layer = document.layers.first(where: { $0.id == layerID }),var object = layer.smartObject,object.rawDevelopment != nil,
      !document.isImageLocked(layerID) else { throw CraftError.invalid("Select an unlocked RAW Smart Object.") }
    let (decoded,resolved,_) = try render(object.data,settings:settings,depth:document.depth)
    var source = try CraftDocument(width:decoded.width,height:decoded.height,depth:document.depth)
    source.layers[0].content = .raster(decoded)
    let pixels = try ColorManagement.converted(decoded,from:source,to:document)
    if !allInstances { object.sourceID = UUID() }
    object.rawDevelopment = resolved; object.width = decoded.width; object.height = decoded.height
    return .replaceSmartObject(layerID,object,pixels,preserveSize:true,allInstances:allInstances)
  }
}
