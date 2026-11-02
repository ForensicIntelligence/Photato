import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

/// Native resource processing shared with desktop import/export. These limits
/// describe the local preview, not Adobe's hosted service limits.
enum AdobeActionAssets {
  static let maximumResourceBytes = 64 * 1_024 * 1_024
  static let maximumOutputBytes = 128 * 1_024 * 1_024
  static let maximumCanvasPixels = Surface.maxPixels
  static let maximumDocumentBytes = 128 * 1_024 * 1_024
  // These codecs/analysis workflows do not yet use the paged Photoshop input path.
  static let maximumUnpagedInputPixels = 4_194_304
  static let maximumAnalysisPixels = 4_194_304
  static let maximumArtboardPixels = 4_194_304

  static func checkDimensions(width: Int, height: Int) throws {
    guard width > 0, height > 0, width <= Surface.maxDimension,
      height <= Surface.maxDimension, width <= maximumCanvasPixels / height else {
      throw AdobeAPIError.invalid("Input exceeds the local 300,000-pixel side limit.")
    }
  }

  struct Encoded: Sendable {
    let output: AdobeActionsRequest.Output
    let data: Data
  }
  private struct EncodingKey: Hashable {
    let type: AdobeActionsRequest.MediaType
    let options: RasterEncodingOptions
    let profile: AdobeOutputProfile?
    let selection: AdobeLayerOutput?
  }

  static func decode(_ data: Data, allowPhotatoInput: Bool = false) throws -> CraftDocument {
    try Task.checkCancellation()
    guard data.count <= maximumResourceBytes else {
      throw AdobeAPIError.invalid("Input exceeds the local 64 MiB resource limit.")
    }
    if allowPhotatoInput && (data.starts(with:Data("PHOTATO\0".utf8)) || data.starts(with:Data("bplist00".utf8))) {
      let (w,h)=try NativeArchive.dimensions(data);try checkDimensions(width:w,height:h)
      let document=try DocumentIO.decode(data,native:true,name:"Action Input",rasterByteLimit:maximumDocumentBytes)
      try check(document);return document
    }
    if allowPhotatoInput && PcraftImport.recognizes(data) {
      let (w, h) = try PcraftImport.dimensions(data)
      try checkDimensions(width: w, height: h)
      guard w <= maximumUnpagedInputPixels / h else {
        throw AdobeAPIError.invalid("PhotoCraft input exceeds the local 4,194,304 pixel decoder limit.")
      }
      let document = try DocumentIO.decode(data, native: false, name: "Action Input",
        rasterByteLimit: maximumDocumentBytes)
      try check(document)
      return document
    }
    let width: Int
    let height: Int
    let isTIFF = data.starts(with: [73, 73, 42, 0]) || data.starts(with: [77, 77, 0, 42])
    let isPhotoshop = data.starts(with: Data("8BPS".utf8))
    if isPhotoshop {
      guard data.count >= 26 else { throw AdobeAPIError.invalid("Truncated PSD header.") }
      func number(_ start: Int, _ count: Int) -> Int {
        data[start..<(start + count)].reduce(0) { ($0 << 8) | Int($1) }
      }
      let mode = number(24, 2), depth = number(22, 2)
      let component = [1, 3, 4, 9].contains(mode) && [8, 16, 32].contains(depth)
        && (depth != 32 || [1, 3].contains(mode))
      let restricted = (mode == 0 && depth == 1) || (mode == 2 && depth == 8)
      guard [1, 2].contains(number(4, 2)), component || restricted || (mode == 7 && [8,16].contains(depth))
      else {
        throw AdobeAPIError.unsupported(
          "Actions require a supported component, Indexed Color, Bitmap or Multichannel PSD/PSB/TIFF/PNG image.")
      }
      width = number(18, 4)
      height = number(14, 4)
    } else {
      guard isTIFF || data.starts(with: Data([137, 80, 78, 71, 13, 10, 26, 10])),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int,
        let h = properties[kCGImagePropertyPixelHeight] as? Int
      else {
        throw AdobeAPIError.unsupported("The input must contain a supported PSD/PSB, TIFF or PNG image.")
      }
      width = w
      height = h
    }
    try checkDimensions(width: width, height: height)
    if !isPhotoshop, width > maximumUnpagedInputPixels / height {
      throw AdobeAPIError.invalid("Raster input exceeds the local 4,194,304 pixel decoder limit; use a supported paged PSD/PSB resource for larger RGB documents.")
    }
    let document = isPhotoshop
      ? try PSDCodec.readPaged(data, name: "Action Input", heapByteLimit: maximumDocumentBytes)
      : try RasterIO.read(data, name: "Action Input")
    if !isTIFF && !data.starts(with: Data("8BPS".utf8)), document.depth != .u8 {
      throw AdobeAPIError.unsupported("PNG action input currently requires RGB8.")
    }
    try check(document)
    return document
  }

  static func check(_ document: CraftDocument) throws {
    try document.validate()
    try checkDimensions(width: document.width, height: document.height)
    guard document.layers.count <= LayerLimits.maximumLayers, document.estimatedBytes <= maximumDocumentBytes
    else {
      throw AdobeAPIError.invalid(
        "Input exceeds the local 8,000-layer or 128 MiB resident document limit.")
    }
  }

  /// Encode every output before publishing any of them. This prevents an invalid
  /// later output from exposing a misleading partial successful result.
  static func execute(_ request: AdobeActionsRequest, input: Data, resources: [URL: Data] = [:]) throws -> [Encoded] {
    let document = try request.creation?.document(resources: resources)
      ?? decode(input, allowPhotatoInput: request.allowsPhotatoInput)
    return try execute(request, document: document, resources: resources)
  }
  static func execute(_ request: AdobeActionsRequest, document: CraftDocument, resources: [URL: Data] = [:]) throws -> [Encoded] {
    let edited = try request.applying(to: document, resources: resources).session.document
    return try encode(request, document: edited, resources: resources)
  }
  static func encode(_ request: AdobeActionsRequest, document edited: CraftDocument, resources: [URL: Data] = [:]) throws -> [Encoded] {
    try check(edited)
    var cache: [EncodingKey: Data] = [:]
    var total = 0
    return try request.outputs.map { output in
      try Task.checkCancellation()
      let data: Data
      let key = EncodingKey(type: output.mediaType, options: output.encodingOptions, profile: output.colorProfile, selection: output.layerExport)
      if let existing = cache[key] {
        data = existing
      } else {
        let isolated = try output.layerExport?.document(edited) ?? edited
        let converted = try output.colorProfile?.convert(isolated, resources: resources, rasterOutput: output.mediaType != .psd) ?? isolated
        if output.colorProfile != nil, [.png, .jpeg].contains(output.mediaType), converted.colorMode != .rgb {
          throw AdobeAPIError.unsupported("Non-RGB output ICC profiles currently require PSD or TIFF.")
        }
        switch output.mediaType {
        case .json:
          data = try AdobeArtboardRequest.manifest(edited)
        case .psd:
          data = try PSDCodec.writeRasterLayers(converted,
            compression: output.encodingOptions.psdLayerCompression?.codec ?? .zipPrediction,
            compositeCompression: output.encodingOptions.psdCompositeCompression?.codec ?? .raw,
            maximumBytes: maximumResourceBytes)
        case .jpeg:
          data = try DocumentIO.encode(converted, format: output.mediaType.format!, options: output.encodingOptions)
        case .png, .tiff:
          guard edited.depth != .f32 || output.mediaType == .tiff else {
            throw AdobeAPIError.unsupported("This PNG encoder cannot retain RGB32 action output; request PSD or TIFF.")
          }
          data = try DocumentIO.encode(converted, format: output.mediaType.format!, options: output.encodingOptions)
        }
        guard data.count <= maximumResourceBytes else {
          throw AdobeAPIError.invalid("Encoded output exceeds the local 64 MiB resource limit.")
        }
        cache[key] = data
      }
      total += data.count
      guard total <= maximumOutputBytes else {
        throw AdobeAPIError.invalid("Outputs exceed the local 128 MiB aggregate limit.")
      }
      return Encoded(output: output, data: data)
    }
  }
}
