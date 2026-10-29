import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PhotoCraftCore

/// Native Apple sensor decoder. Never substitutes CGImageSource previews for RAW output.
public enum RawSourceIO {
  public static let maximumPixels = Surface.maxPixels
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
    guard let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
      let type = CGImageSourceGetType(source) as String?,UTType(type)?.conforms(to:contentType) == true else { return nil }
    return type
  }
  public static func recognizes(_ data: Data) -> Bool { type(data) != nil }
  public static func recognizes(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),let type = CGImageSourceGetType(source) as String? else { return false }
    return UTType(type)?.conforms(to:contentType) == true
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
    let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
    let data = try file.read(upToCount:SmartObject.maximumSourceBytes+1) ?? Data()
    return try open(data,fileName:url.lastPathComponent,depth:depth)
  }
  public static func open(_ data: Data,fileName: String,settings requested: RawDevelopment = .init(),depth: PixelDepth = .u16) throws -> CraftDocument {
    let (pixels,settings,info) = try render(data,settings:requested,depth:depth)
    var name = URL(fileURLWithPath:fileName).lastPathComponent
    if (name as NSString).pathExtension.isEmpty { name += "." + (UTType(info.type)?.preferredFilenameExtension ?? "raw") }
    var document = try CraftDocument(width:pixels.width,height:pixels.height,depth:depth,name:(name as NSString).deletingPathExtension)
    if let source = CGImageSourceCreateWithData(data as CFData,nil),let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] {
      document.sourceMetadata = try RasterMetadata.capture(source,properties:properties)
      if let dpi = properties[kCGImagePropertyDPIWidth] as? Double,dpi.isFinite,(1...100_000).contains(dpi) { document.resolution = dpi }
    }
    var object = try SmartObject(fileName:name.isEmpty ? "Source.raw" : name,mediaType:info.type == "com.adobe.raw-image" ? "image/x-adobe-dng" : "image/x-camera-raw",data:data,width:pixels.width,height:pixels.height,rawDevelopment:settings)
    object.resolution = document.pixelsPerInch
    var layer = Layer(name:document.name,content:.raster(pixels)); layer.smartObject = object
    document.layers = [layer]; document.activeLayerID = layer.id
    try document.validate(); return document
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
