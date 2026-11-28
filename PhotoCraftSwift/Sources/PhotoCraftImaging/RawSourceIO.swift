import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PhotoCraftCore

/// Storage policy for adjustments attached to original Digital Negative files.
public enum RawDNGSettingsStorage: String, CaseIterable, Codable, Sendable {
  case embedXMP
  case sidecarXMP
  case ignoreSidecarXMP
}

/// Native Apple sensor decoder. Never substitutes CGImageSource previews for RAW output.
/// Settings for the developed document. Camera Raw's source XMP contains the
/// development settings only. Output dimensions and PPI describe the new file.
package struct RawWorkflowOutput: Codable, Equatable, Sendable {
  package enum Profile: String, CaseIterable, Codable, Sendable {
    case sRGB, displayP3, adobeRGB, proPhotoRGB, rec2020

    package var title: String {
      switch self {
      case .sRGB: "sRGB IEC61966-2.1"
      case .displayP3: "Display P3"
      case .adobeRGB: "Adobe RGB (1998)"
      case .proPhotoRGB: "ProPhoto RGB"
      case .rec2020: "Rec. 2020"
      }
    }

    package func icc() throws -> Data {
      let name: CFString
      switch self {
      case .sRGB: name = CGColorSpace.sRGB
      case .displayP3: name = CGColorSpace.displayP3
      case .adobeRGB: name = CGColorSpace.adobeRGB1998
      case .proPhotoRGB: name = CGColorSpace.rommrgb
      case .rec2020: name = CGColorSpace.itur_2020
      }
      guard let profile = CGColorSpace(name: name)?.copyICCData() as Data? else {
        throw CraftError.unsupported("The selected Camera Raw output profile is unavailable.")
      }
      return profile
    }
  }

  package struct Resize: Codable, Equatable, Sendable {
    package enum Mode: String, CaseIterable, Codable, Sendable {
      case widthHeight, dimensions, longSide, shortSide, megapixels, percentage

      package var title: String {
        switch self {
        case .widthHeight: "Width & Height"
        case .dimensions: "Dimensions"
        case .longSide: "Long Side"
        case .shortSide: "Short Side"
        case .megapixels: "Megapixels"
        case .percentage: "Percentage"
        }
      }

      package var usesSecondValue: Bool { self == .widthHeight || self == .dimensions }
    }

    package var mode: Mode
    package var value: Double
    package var secondValue: Double?
    package var dontEnlarge: Bool

    package init(mode: Mode, value: Double, secondValue: Double? = nil, dontEnlarge: Bool = false) {
      self.mode = mode
      self.value = value
      self.secondValue = secondValue
      self.dontEnlarge = dontEnlarge
    }

    package func validate() throws {
      guard value.isFinite, value > 0, mode.usesSecondValue == (secondValue != nil) else {
        throw CraftError.invalid("Choose valid Camera Raw output dimensions.")
      }
      switch mode {
      case .widthHeight, .dimensions, .longSide, .shortSide:
        for side in [value, secondValue].compactMap({ $0 }) {
          guard side.isFinite, side == side.rounded(), (1...Double(Surface.maxDimension)).contains(side) else {
            throw CraftError.invalid("Enter whole pixel dimensions from 1 to 300,000.")
          }
        }
      case .megapixels, .percentage:
        break
      }
    }

    package func dimensions(width: Int, height: Int) throws -> (width: Int, height: Int) {
      try validate()
      guard (1...Surface.maxDimension).contains(width), (1...Surface.maxDimension).contains(height) else {
        throw CraftError.invalid("Invalid Camera Raw input dimensions.")
      }
      if let secondValue {
        let first = Int(value), second = Int(secondValue)
        let horizontal: Int, vertical: Int
        if mode == .widthHeight {
          (horizontal, vertical) = (first, second)
        } else {
          let long = max(first, second), short = min(first, second)
          (horizontal, vertical) = width >= height ? (long, short) : (short, long)
        }
        return try FitImageOptions(width: horizontal, height: vertical, dontEnlarge: dontEnlarge)
          .dimensions(sourceWidth: width, sourceHeight: height)
      }
      let factor: Double
      switch mode {
      case .longSide: factor = value / Double(max(width, height))
      case .shortSide: factor = value / Double(min(width, height))
      case .megapixels: factor = (value / (Double(width * height) / 1_000_000)).squareRoot()
      case .percentage: factor = value / 100
      case .widthHeight, .dimensions:
        throw CraftError.invalid("Enter both Camera Raw bounds.")
      }
      let scale = dontEnlarge ? min(1, factor) : factor
      let w = max(1, (Double(width) * scale).rounded())
      let h = max(1, (Double(height) * scale).rounded())
      guard w.isFinite, h.isFinite, w <= Double(Surface.maxDimension), h <= Double(Surface.maxDimension) else {
        throw CraftError.invalid("The Camera Raw result exceeds 300,000 pixels per side.")
      }
      return (Int(w), Int(h))
    }
  }

  package var profile: Profile?
  package var depth: PixelDepth?
  package var pixelsPerInch: Double?
  package var resize: Resize?

  package init(profile: Profile? = nil, depth: PixelDepth? = nil, pixelsPerInch: Double? = nil, resize: Resize? = nil) {
    self.profile = profile
    self.depth = depth
    self.pixelsPerInch = pixelsPerInch
    self.resize = resize
  }

  package func validate() throws {
    if let depth, depth != .u8 && depth != .u16 {
      throw CraftError.invalid("Choose 8 or 16 bits per channel for Camera Raw output.")
    }
    if let pixelsPerInch, !pixelsPerInch.isFinite || !(1...100_000).contains(pixelsPerInch) {
      throw CraftError.invalid("Enter a resolution from 1 to 100,000 pixels per inch.")
    }
    try resize?.validate()
  }

  /// Convert the one developed RAW cache before deciding how it will be opened.
  /// The source bytes, XMP settings and source-space dimensions stay attached.
  package func prepare(in source: CraftDocument) throws -> CraftDocument {
    try validate()
    guard profile != nil || depth != nil || pixelsPerInch != nil else { return source }
    guard source.colorMode == .rgb, source.modeDescriptor == nil, source.layers.count == 1,
      source.layers[0].smartObject?.rawDevelopment != nil,
      case .raster(let rgb) = source.layers[0].content else {
      throw CraftError.invalid("Camera Raw output settings require one developed RGB source.")
    }
    var result = source
    result.depth = depth ?? source.depth
    result.resolution = pixelsPerInch ?? source.resolution
    if let profile {
      result.workingICC = try ColorManagement.importedProfile(profile.icc(), depth: result.depth)
      result.profileIsUntagged = nil
    } else if result.depth != source.depth {
      result.workingICC = try ColorManagement.importedProfile(source.workingICC, depth: result.depth)
    }
    if let pixelsPerInch { result.layers[0].smartObject?.resolution = pixelsPerInch }
    if result.depth != source.depth || result.workingICC != source.workingICC {
      result.layers[0].content = .raster(try ColorManagement.converted(rgb, from: source, to: result))
    }
    try result.validate()
    return result
  }
}

package enum RawOpenMode: String, CaseIterable, Sendable {
  case image, object, copy

  package var savesSourceSettings: Bool { self != .copy }

  /// The initial RAW import is a single, full-canvas rendered source. Retain
  /// the document's color coordinates and metadata when making a pixel layer.
  package func output(from preview: CraftDocument, workflow: RawWorkflowOutput = .init()) throws -> CraftDocument {
    let developed = try workflow.prepare(in: preview)
    let size = try workflow.resize?.dimensions(width: developed.width, height: developed.height)
    var output = try layerOutput(from: developed)
    if let size, size.width != output.width || size.height != output.height {
      let resolution = output.resolution
      try Command.imageSize(size.width, size.height, output.pixelsPerInch, .bicubic).apply(to: &output)
      output.resolution = resolution
    }
    return output
  }

  private func layerOutput(from developed: CraftDocument) throws -> CraftDocument {
    guard developed.colorMode == .rgb, developed.layers.count == 1, let layer = developed.layers.first,
      layer.smartObject?.rawDevelopment != nil, case .raster(let raster) = layer.content,
      layer.visible, layer.opacity == 1, layer.blendMode == .normal,
      layer.mask == nil, layer.vectorMask == nil, layer.smartFilters == nil,
      layer.style == nil, layer.warp == nil, layer.sourceProjection == nil else {
      throw CraftError.invalid("Choose a single full-canvas Camera Raw source to open.")
    }
    guard self != .object else { return developed }
    let bounds = IntRect(x: 0, y: 0, width: developed.width, height: developed.height)
    let aligned = (layer.coordinateTransform == .identity && raster.width == bounds.width && raster.height == bounds.height)
      ? raster
      : try RasterGeometry.render(raster, transform: layer.coordinateTransform, bounds: bounds, method: .bilinear)
    var output = developed
    var background = Layer(name: "Background", content: .raster(try BackgroundLayer.opaque(aligned, over: .white)))
    background.id = layer.id
    background.background = true
    background.sourceTags = ["lyid": Data(repeating: 0, count: 4)]
    output.layers = [background]
    try output.validate()
    return output
  }
}

public enum RawSourceIO {
  public static let maximumPixels = 512_000_000
  public static let maximumDimension = 65_000
  public static let mediaTypes = ["image/x-camera-raw","image/x-adobe-dng"]
  public static let contentType = UTType("public.camera-raw-image")!
  public struct Info: Codable, Equatable, Sendable {
    public let type: String, model: String
    public let nativeWidth: Int, nativeHeight: Int
    public let decoderVersion: String
    public let supportedDecoders: [String]
    public let temperature: Float, tint: Float
    public let iso: Double?
    public let lensCorrectionSupported: Bool, highlightRecoverySupported: Bool
    public let lensCorrectionEnabled: Bool, highlightRecoveryEnabled: Bool
  }
  fileprivate struct SensorKey: Equatable, Sendable {
    let data: Data
    let depth: PixelDepth
    let decoderVersion: String?
    let values: [UInt32?]
    let lensCorrection: Bool?
    let highlightRecovery: Bool?

    init(data: Data, depth: PixelDepth, settings: RawDevelopment) {
      self.data = data
      self.depth = depth
      decoderVersion = settings.decoderVersion
      values = [settings.temperature?.bitPattern, settings.tint?.bitPattern,
        settings.exposure.bitPattern, settings.boost.bitPattern, settings.shadowBoost.bitPattern,
        settings.extendedRange.bitPattern]
      lensCorrection = settings.lensCorrection
      highlightRecovery = settings.highlightRecovery
    }
  }

  /// Immutable samples before the RGB adjustments and document profile conversion.
  package final class SensorRaster: Sendable {
    fileprivate let key: SensorKey
    fileprivate let pixels: Surface
    package let info: Info

    fileprivate init(key: SensorKey, pixels: Surface, info: Info) {
      self.key = key
      self.pixels = pixels
      self.info = info
    }
  }

  public static func type(_ data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let type = CGImageSourceGetType(source) as String? else { return nil }
    if UTType(type)?.conforms(to: contentType) == true { return type }
    // A TIFF classification can identify a RAW's thumbnail instead of the
    // sensor image. Require a DNG marker or a Nikon CFA directory before hinting.
    guard type == UTType.tiff.identifier, data.count <= SmartObject.maximumCameraRawSourceBytes,
      TIFFContainer.isClassic(data),
      let root = try? TIFFContainer(data, metadata: false, additionalTags: [271, 50706], maximumBytes: SmartObject.maximumCameraRawSourceBytes) else { return nil }
    if isDNG(root) { return "com.adobe.raw-image" }
    guard isNikonCamera(root),
      let sensor = try? TIFFContainer(data, metadata: false, additionalTags: [33421, 33422], inspectSubIFDs: true,
        maximumBytes: SmartObject.maximumCameraRawSourceBytes),
      hasNikonMosaic(sensor) else { return nil }
    return "com.nikon.raw-image"
  }
  public static func recognizes(_ data: Data) -> Bool { type(data) != nil }
  public static func recognizes(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
      let type = CGImageSourceGetType(source) as String? else { return false }
    if UTType(type)?.conforms(to: contentType) == true { return true }
    guard type == UTType.tiff.identifier,
      let source = try? PSDFileSource(url, maximumBytes: SmartObject.maximumCameraRawSourceBytes),
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
    guard !data.isEmpty,data.count <= SmartObject.maximumCameraRawSourceBytes,let type = type(data),
      let raw = CIRAWFilter(imageData:data,identifierHint:type) else { throw CraftError.unsupported("This file is not a supported camera RAW image, or exceeds the 2 GiB local source limit.") }
    if let version {
      guard raw.supportedDecoderVersions.map(\.rawValue).contains(version) else { throw CraftError.unsupported("The saved RAW decoder version is unavailable on this Mac.") }
      raw.decoderVersion = CIRAWDecoderVersion(rawValue:version)
      guard raw.decoderVersion.rawValue == version else { throw CraftError.unsupported("The requested RAW decoder could not be selected.") }
    }
    let size = raw.nativeSize
    guard size.width.isFinite,size.height.isFinite,size.width >= 1,size.height >= 1,
      size.width <= CGFloat(maximumDimension),size.height <= CGFloat(maximumDimension),size.width*size.height <= CGFloat(maximumPixels),
      size.width.rounded() == size.width,size.height.rounded() == size.height else { throw CraftError.unsupported("The RAW decoder returned invalid dimensions or exceeded 65,000 pixels per side or 512 megapixels.") }
    let versions = raw.supportedDecoderVersions.map(\.rawValue)
    guard !raw.decoderVersion.rawValue.isEmpty,versions.contains(raw.decoderVersion.rawValue),raw.neutralTemperature.isFinite,raw.neutralTint.isFinite else { throw CraftError.unsupported("This camera has no available native RAW decoder.") }
    let properties = raw.properties
    if type == "com.adobe.raw-image" { try validateDNGCanvas(properties, decoded: size) }
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String:Any]
    let model = (tiff?[kCGImagePropertyTIFFModel as String] as? String) ?? "Camera RAW"
    var highlightSupported = false, highlightEnabled = false
    if #available(macOS 26,*) { highlightSupported = raw.isHighlightRecoverySupported; highlightEnabled = raw.isHighlightRecoveryEnabled }
    let info = Info(type:type,model:String(model.prefix(256)),nativeWidth:Int(size.width),nativeHeight:Int(size.height),decoderVersion:raw.decoderVersion.rawValue,supportedDecoders:versions,temperature:raw.neutralTemperature,tint:raw.neutralTint,iso:cameraISO(properties as? [CFString: Any]),lensCorrectionSupported:raw.isLensCorrectionSupported,highlightRecoverySupported:highlightSupported,lensCorrectionEnabled:raw.isLensCorrectionEnabled,highlightRecoveryEnabled:highlightEnabled)
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

  public static func prepareLocalSettings(_ url: URL, depth: PixelDepth = .u16,
    dngStorage: RawDNGSettingsStorage = .embedXMP) throws
    -> (document: CraftDocument, source: RawSettingsSource?) {
    try prepareLocalSettings(url, depth: depth, dngStorage: dngStorage, rawDefaults: .init())
  }

  package static func prepareLocalSettings(_ url: URL, depth: PixelDepth = .u16,
    dngStorage: RawDNGSettingsStorage = .embedXMP, rawDefaults: RawDefaults) throws
    -> (document: CraftDocument, source: RawSettingsSource?) {
    let input = try PSDFileSource(url, maximumBytes: SmartObject.maximumCameraRawSourceBytes)
    let original = try prepareLocalOriginal(url, input: input, dngStorage: dngStorage, rawDefaults: rawDefaults, mapped: false)
    let document = try original.document(depth: depth)
    try input.validateUnchanged()
    return (document, original.settingsSource)
  }

  package struct LocalOriginal: Sendable {
    fileprivate let bytes: EmbeddedSourceBytes
    fileprivate let description: SourceDescription
    package let url: URL
    package let settingsSource: RawSettingsSource?
    package let sensorInfo: Info?
    package var settings: RawDevelopment { description.initial }

    package func document(settings: RawDevelopment? = nil, depth: PixelDepth = .u16) throws -> CraftDocument {
      try RawSourceIO.makeDocument(bytes, fileName: url.lastPathComponent, description: description,
        settings: settings ?? description.initial, depth: depth)
    }

    package func thumbnail() -> CGImage? {
      guard let source = CGImageSourceCreateWithData(bytes.data as CFData, nil) else { return nil }
      return CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 144,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary)
    }
  }

  package static func prepareLocalOriginal(_ url: URL, dngStorage: RawDNGSettingsStorage,
    rawDefaults: RawDefaults) throws -> LocalOriginal {
    let input = try PSDFileSource(url, maximumBytes: SmartObject.maximumCameraRawSourceBytes)
    return try prepareLocalOriginal(url, input: input, dngStorage: dngStorage, rawDefaults: rawDefaults, mapped: true)
  }

  private static func prepareLocalOriginal(_ url: URL, input: PSDFileSource, dngStorage: RawDNGSettingsStorage,
    rawDefaults: RawDefaults, mapped: Bool) throws -> LocalOriginal {
    let bytes: EmbeddedSourceBytes
    if mapped || input.count > SmartObject.maximumSourceBytes {
      bytes = .file(try FileBackedSource.retain(byteCount: input.count, fingerprinting: true) { offset, count in
        try input.bytes(at: offset, count: count)
      })
    } else {
      bytes = .memory(try input.bytes(at: 0, count: input.count))
    }
    let data = bytes.data
    let ignoresSidecar = dngStorage == .ignoreSidecarXMP && type(data) == "com.adobe.raw-image"
    let related = try ignoresSidecar ? nil : relatedXMP(for: url)
    let settings = try related?.settings.map { try compatibleStoredSettings($0, in: data) }
    let description = try describeSource(data, requested: settings, rawDefaults: rawDefaults)
    let info = mapped ? try inspect(data, decoderVersion: description.initial.decoderVersion) : nil
    let safeSource = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
    let mediaType = description.sourceType == "com.adobe.raw-image" ? "image/x-adobe-dng" : "image/x-camera-raw"
    let source: RawSettingsSource?
    if safeSource, mediaType == "image/x-adobe-dng", dngStorage != .sidecarXMP, TIFFContainer.isClassic(data) {
      source = .embeddedDNG(RawDNGSource(url: url, original: data, sidecar: related, ignoresSidecar: ignoresSidecar))
    } else if safeSource, mediaType == "image/x-camera-raw"
      || (mediaType == "image/x-adobe-dng" && dngStorage == .sidecarXMP) {
      let existing = try related ?? relatedXMP(for: url, requireAdjustments: false)
      source = .sidecar(RawSidecarSource(url: url, original: data, existing: existing))
    } else {
      source = nil
    }
    try input.validateUnchanged()
    return LocalOriginal(bytes: bytes, description: description, url: url, settingsSource: source, sensorInfo: info)
  }
  public static func open(_ data: Data, fileName: String, settings requested: RawDevelopment? = nil,
    depth: PixelDepth = .u16) throws -> CraftDocument {
    try open(data, fileName: fileName, settings: requested, depth: depth, rawDefaults: .init())
  }

  package static func open(_ data: Data, fileName: String, settings requested: RawDevelopment? = nil,
    depth: PixelDepth = .u16, rawDefaults: RawDefaults) throws -> CraftDocument {
    guard (1...SmartObject.maximumCameraRawSourceBytes).contains(data.count) else {
      throw CraftError.invalid("Camera RAW source must contain 1 byte to 2 GiB.")
    }
    let source: EmbeddedSourceBytes = if data.count > SmartObject.maximumSourceBytes {
      .file(try FileBackedSource.retain(byteCount: data.count, fingerprinting: true) { offset, count in
        data.subdata(in: offset..<offset + count)
      })
    } else {
      .memory(data)
    }
    return try open(source, fileName: fileName, settings: requested, depth: depth, rawDefaults: rawDefaults)
  }

  package static func open(_ bytes: EmbeddedSourceBytes, fileName: String, settings requested: RawDevelopment? = nil,
    depth: PixelDepth = .u16, rawDefaults: RawDefaults = .init()) throws -> CraftDocument {
    try Task.checkCancellation()
    let data = bytes.data
    guard (1...SmartObject.maximumCameraRawSourceBytes).contains(data.count) else {
      throw CraftError.invalid("Camera RAW source must contain 1 byte to 2 GiB.")
    }
    let description = try describeSource(data, requested: requested, rawDefaults: rawDefaults)
    return try makeDocument(bytes, fileName: fileName, description: description, settings: description.initial, depth: depth)
  }

  fileprivate struct SourceDescription: Sendable {
    let sourceType: String?
    let metadata: [String: Data]?
    let resolution: Double?
    let initial: RawDevelopment
  }

  private static func describeSource(_ data: Data, requested: RawDevelopment?, rawDefaults: RawDefaults) throws -> SourceDescription {
    let sourceType = type(data)
    let options = sourceType.map { [kCGImageSourceTypeIdentifierHint: $0] as CFDictionary }
    let source = CGImageSourceCreateWithData(data as CFData, options)
    let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    var metadata: [String: Data]?
    if let source, let properties { metadata = try RasterMetadata.capture(source, properties: properties) }
    if sourceType == "com.adobe.raw-image", metadata?[RasterMetadata.xmpKey] == nil,
      let packet = try? embeddedDNGXMP(data) {
      var captured = metadata ?? [:]
      captured[RasterMetadata.xmpKey] = packet
      metadata = captured
    }
    let embedded = (metadata?[RasterMetadata.xmpKey]).flatMap { try? CameraRawXMP.readStored($0) }
    let initial: RawDevelopment
    if let requested { initial = requested }
    else if let embedded { initial = try compatibleStoredSettings(embedded, in: data) }
    else {
      initial = try defaultDevelopment(rawDefaults.choice(for: cameraIdentity(properties)),
        from: data, iso: cameraISO(properties))
    }
    return SourceDescription(sourceType: sourceType, metadata: metadata,
      resolution: properties?[kCGImagePropertyDPIWidth] as? Double, initial: initial)
  }

  private static func makeDocument(_ bytes: EmbeddedSourceBytes, fileName: String,
    description: SourceDescription, settings initial: RawDevelopment, depth: PixelDepth) throws -> CraftDocument {
    let data = bytes.data
    let (workingPixels, settings, info) = try render(data, settings: initial, depth: depth == .u8 ? .u16 : depth)
    let pixels = try workingPixels.converted(to: depth)
    var name = URL(fileURLWithPath:fileName).lastPathComponent
    if (name as NSString).pathExtension.isEmpty { name += "." + (UTType(info.type)?.preferredFilenameExtension ?? "raw") }
    var document = try CraftDocument(width:pixels.width,height:pixels.height,depth:depth,name:(name as NSString).deletingPathExtension)
    document.sourceMetadata = description.metadata
    if let dpi = description.resolution, dpi.isFinite, (1...100_000).contains(dpi) {
      document.resolution = dpi
    }
    var object = try SmartObject(fileName:name.isEmpty ? "Source.raw" : name,mediaType:info.type == "com.adobe.raw-image" ? "image/x-adobe-dng" : "image/x-camera-raw",source:bytes,width:pixels.width,height:pixels.height,rawDevelopment:settings)
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
    let (pixels, settings, sensor) = try develop(data, settings: requested, depth: depth, reusing: nil)
    return (pixels, settings, sensor.info)
  }

  private static func develop(_ data: Data, settings requested: RawDevelopment, depth: PixelDepth,
    reusing previous: SensorRaster?) throws -> (Surface, RawDevelopment, SensorRaster) {
    try requested.validate()
    try Task.checkCancellation()
    let key = SensorKey(data: data, depth: depth, settings: requested)
    let sensor = try (previous?.key == key ? previous : nil) ?? readSensor(key, settings: requested)
    var settings = requested
    settings.decoderVersion = sensor.info.decoderVersion
    let pixels = try CameraRawEngine.develop(sensor.pixels, settings: settings.adjustments,
      maximumPixels: maximumPixels)
    return (pixels, settings, sensor)
  }

  private static func readSensor(_ key: SensorKey, settings: RawDevelopment) throws -> SensorRaster {
    let (raw, info) = try decoder(key.data, version: key.decoderVersion)
    let depth = key.depth
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
      bounds.width >= 1,bounds.height >= 1,bounds.width <= CGFloat(maximumDimension),bounds.height <= CGFloat(maximumDimension),bounds.width*bounds.height <= CGFloat(maximumPixels),bounds.width.rounded() == bounds.width,bounds.height.rounded() == bounds.height else { throw CraftError.unsupported("RAW sensor output has invalid or oversized dimensions.") }
    let w = Int(bounds.width), h = Int(bounds.height)
    let space = CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!
    let context = CIContext(options:[.workingColorSpace:space,.outputColorSpace:space,.cacheIntermediates:false])
    let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
    let rows = min(Surface.tileSide, h)
    var buffer = [Float](repeating: 0, count: w * rows * 4)
    func renderBand(at y: Int, rows: Int) throws {
      try Task.checkCancellation()
      // Core Image uses bottom-up bounds and writes top-down rows after orientation.
      let rect = CGRect(x: bounds.minX, y: bounds.minY + CGFloat(h - y - rows), width: CGFloat(w), height: CGFloat(rows))
      context.render(image, toBitmap: &buffer, rowBytes: w * 16, bounds: rect, format: .RGBAf, colorSpace: space)
    }
    func copyBand(rows: Int, into pixels: inout Surface, top: Int) throws {
      for row in 0..<rows { for x in 0..<w {
        let offset = (row * w + x) * 4
        let pixel = Pixel(buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
        guard pixel.isFinite else { throw CraftError.invalid("The RAW decoder produced nonfinite sensor pixels.") }
        if depth == .f32 { pixels.setLinearPixel(x: x, y: top + row, pixel) }
        else { pixels.setPixel(x: x, y: top + row, SRGBTransfer.encoded(pixel)) }
      } }
    }
    let pixels: Surface
    if w * h > Surface.maximumDensePixels {
      let paged = try Surface.PagedBuilder(width: w, height: h, depth: depth, colorEncoding: encoding)
      for y in stride(from: 0, to: h, by: rows) {
        let count = min(rows, h - y)
        try renderBand(at: y, rows: count)
        var band = try Surface(width: w, height: count, depth: depth, colorEncoding: encoding)
        try copyBand(rows: count, into: &band, top: 0)
        try paged.append(band, atX: 0, atY: y)
      }
      pixels = try paged.finish()
    } else {
      var dense = try Surface(width: w, height: h, depth: depth, colorEncoding: encoding)
      for y in stride(from: 0, to: h, by: rows) {
        let count = min(rows, h - y)
        try renderBand(at: y, rows: count)
        try copyBand(rows: count, into: &dense, top: y)
      }
      pixels = dense
    }
    try Task.checkCancellation()
    return SensorRaster(key: key, pixels: pixels, info: info)
  }

  public static func command(in document: CraftDocument,layerID: UUID,settings: RawDevelopment,allInstances: Bool = true) throws -> Command {
    try developmentCommand(in: document, layerID: layerID, settings: settings,
      allInstances: allInstances, reusing: nil).command
  }

  package static func developmentCommand(in document: CraftDocument, layerID: UUID, settings: RawDevelopment,
    allInstances: Bool = true, reusing previous: SensorRaster?) throws -> (command: Command, sensor: SensorRaster) {
    guard let layer = document.layers.first(where: { $0.id == layerID }),var object = layer.smartObject,object.rawDevelopment != nil,
      !document.isImageLocked(layerID) else { throw CraftError.invalid("Select an unlocked RAW Smart Object.") }
    let (decoded, resolved, sensor) = try develop(object.data, settings: settings,
      depth: document.depth == .u8 ? .u16 : document.depth, reusing: previous)
    var source = try CraftDocument(width:decoded.width,height:decoded.height,depth:decoded.depth)
    source.layers[0].content = .raster(decoded)
    let pixels = try ColorManagement.converted(decoded,from:source,to:document)
    if !allInstances { object.sourceID = UUID() }
    object.rawDevelopment = resolved; object.width = decoded.width; object.height = decoded.height
    return (.replaceSmartObject(layerID, object, pixels, preserveSize: true, allInstances: allInstances), sensor)
  }
}
