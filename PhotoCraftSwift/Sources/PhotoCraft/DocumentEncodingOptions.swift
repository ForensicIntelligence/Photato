import Foundation
import PhotoCraftImaging

enum DocumentEncodingOptions {
  static let jpegQualities = ["very_poor", "poor", "low", "medium", "high", "maximum", "photoshop_max"]
  static let pngLevels = [
    "none", "very_low", "low", "medium_low", "medium", "medium_high",
    "default", "high", "very_high", "maximum",
  ]
  static var schema: [String: Any] {
    ["type": "object", "additionalProperties": false, "required": [String](),
     "properties": [
       "exrCompression": ["type":"string","enum":OpenEXR.Compression.allCases.map(\.rawValue)],
       "exrSample": ["type":"string","enum":OpenEXR.Sample.allCases.map(\.rawValue)],
       "exrTransparency": ["type":"boolean"],
       "jpegQuality": ["type": "integer", "minimum": 0, "maximum": 12],
       "jpegFormat": ["type": "string", "enum": RasterEncodingOptions.JPEGFormat.allCases.map(\.rawValue)],
       "jpegMatte": ["type": "array", "minItems": 3, "maxItems": 3,
         "items": ["type": "number", "minimum": 0, "maximum": 1]],
       "jpegEmbedProfile": ["type": "boolean"],
       "pngCompression": ["type": "integer", "minimum": 0, "maximum": 9],
       "pngInterlaced": ["type": "boolean"],
       "tiffCompression": ["type": "string", "enum": RasterEncodingOptions.TIFFCompression.allCases.map(\.rawValue)],
       "tiffJPEGQuality": ["type": "integer", "minimum": 0, "maximum": 12],
       "tiffByteOrder": ["type": "string", "enum": RasterEncodingOptions.TIFFByteOrder.allCases.map(\.rawValue)],
       "tiffPixelOrder": ["type": "string", "enum": RasterEncodingOptions.TIFFPixelOrder.allCases.map(\.rawValue)],
       "tiffPredictor": ["type": "boolean"],
       "tiffLayers": ["type": "boolean"],
       "tiffAlphaChannels": ["type": "boolean"],
       "tiffSpotColors": ["type": "boolean"],
       "tiffTransparency": ["type": "boolean"],
       "tiffImagePyramid": ["type": "boolean"],
       "tiffBigTIFF": ["type": "boolean"],
     "tiffEmbedProfile": ["type": "boolean"],
       "tiffLayerCompression": ["type": "string", "enum": RasterEncodingOptions.TIFFLayerCompression.allCases.map(\.rawValue)],
       "psdLayerCompression": ["type": "string", "enum": RasterEncodingOptions.PhotoshopCompression.allCases.map(\.rawValue)],
       "psdCompositeCompression": ["type": "string", "enum": RasterEncodingOptions.PhotoshopCompression.allCases.map(\.rawValue)],
       "psdMaximizeCompatibility": ["type": "boolean"],
     ]]
  }
  static var capabilities: [String: Any] {
    ["schema": schema,
     "formats": ["exr":["exrCompression","exrSample","exrTransparency"], "jpeg": ["jpegQuality", "jpegFormat", "jpegMatte", "jpegEmbedProfile"], "png": ["pngCompression", "pngInterlaced"],
       "tiff": ["tiffCompression", "tiffJPEGQuality", "tiffByteOrder", "tiffPixelOrder", "tiffPredictor", "tiffLayers", "tiffTransparency", "tiffImagePyramid", "tiffBigTIFF", "tiffEmbedProfile", "tiffLayerCompression", "tiffAlphaChannels", "tiffSpotColors"],
       "psd": ["psdLayerCompression", "psdCompositeCompression", "psdMaximizeCompatibility"],
       "psb": ["psdLayerCompression", "psdCompositeCompression", "psdMaximizeCompatibility"]],
     "jpeg": "Quality0...12 maps to ImageIO quality/12; omitted quality retains0.95. Baseline uses platform coding; optimized recodes only Huffman entropy in native Swift; progressive uses the platform scan schedule. Matte is three sRGB values0...1, default white. jpegEmbedProfile=false removes ICC APP2 records without converting samples; True explicitly embeds the working ICC; omitted preserves platform profile signaling, which may use EXIF sRGB without an ICC segment. JPEG always flattens to opaque8-bit (HDR uses SDR sRGB). Photoshop quantization,3–5 progressive scan choice, dialog/default and byte parity remain unqualified.",
     "openEXR":["routes":["GET /v1/documents/{id}/file.exr","POST /v1/documents/import","document.saveAs","document.save","Native Open/Save/Copy"],
       "jobSupport":"OpenEXR is not an advertised Adobe v2 or Photato action-job output media type. Existing published output contracts are unchanged.",
       "encoding":"32-bit RGB documents; scene-linear sRGB; flattened single-part scanline; ZIP16/Float/transparency by default. None/ZIPS/ZIP and Half/Float are explicit choices. File RGB is premultiplied; zero-alpha RGB is retained. Half can reduce precision and rejects overflow. HDR is not tone-mapped.",
       "reading":"Full-resolution RGB or luminance Y with optional alpha, HALF/FLOAT, None/ZIPS/ZIP; 32-bit native working samples and file-backed tiles; data/display windows and xDensity retained.",
       "limits":"512MiB encoded input/output, 128MiB scan-line block, up to1GiB import workspace; API transfer budgets remain separate. Other compression, tiled/deep/multipart/AOV/UINT/subsampled data, non-square pixels, non-sRGB chromaticities and non-finite or out-of-range alpha reject. Full Photoshop format/default/output parity remains unqualified."],
     "downloadHeader": "X-Photato-Export-Options",
     "downloadHeaderEncoding": "JSON object, at most 2048 UTF-8 bytes; same schema as command parameters.options.",
     "defaults": "Omitted choices retain existing encoder behavior. PNG levels 0...9 recompress IDAT; interlacing uses Adam7. TIFF compression tags 1, 5, 8, and 7 mean None, LZW, ZIP, and JPEG. PSD/PSB defaults remain ZIP prediction for layer/mask channels and raw merged image. Explicit raw/rle/zip/zipPrediction choices are lossless. A complete merged image is included by default.",
     "photoshopTaggedBlocks": ["psdSignature":"8BIM", "psdLengthBytes":4,
       "psbWideSignature":"8B64", "psbWideLengthBytes":8,
       "scope":"Supported wide PSB layer/global blocks, including saved paths, mask display, embedded Smart Objects/filter caches and retained Multichannel metadata. Ordinary PSB blocks keep8BIM/four-byte lengths. Shared native file, Photato transfer/job and published Adobe output serializers; no new format option or route.",
       "limits":"Correct block framing does not qualify every retained descriptor, compression/context, Photoshop output or maximum physical capacity."],
     "photoshopCompression": "Layer and merged-image compression may be selected independently. A zip request for 32-bit PSD/PSB layer channels writes ZIP with prediction. Supported ZIP requests for the merged image write raw data, which Photoshop can open. RLE rows use 16-bit lengths in PSD and 32-bit lengths in PSB. A PSD RLE row above 65,535 encoded bytes is rejected. Save/Copy stage the same streaming serializer used for Data responses. The File Handling disablePSDCompression preference resolves omitted choices to raw for 16/32-bit native saves/copies and shared document downloads. Explicit choices override it. Resource jobs keep independent output defaults. See photoshopFilePreferences for the available controls. For eligible editable RGB8/16/32, psdMaximizeCompatibility=false writes a fixed process placeholder and retains layers and saved channels. Only a complete merged preview uses the requested merged-image compression. This Photato option is available to commands, downloads and Photato resource jobs.",
     "nativeState": "Successful Save/Save As remembers requested options for that format in the open document, retaining omitted fields so future default saves follow File Handling. saveEncodingOptions reports requested choices; effectiveSaveEncodingOptions applies current preferences and defaults TIFF layer preservation to true. Save a Copy and downloads do not change remembered save settings. Cancel/failure does not adopt settings. Per-document options are session state, not document content; application defaults persist separately.",
     "tiffStorage": "Explicit bigEndian/littleEndian and interleaved/perChannel choices use native Swift TIFF strip layout. tiffPredictor=true requires a32-bit document and explicit lzw or zip compression. False disables prediction. Omitted storage fields preserve platform defaults; when a storage field is explicit and compression is omitted, compression is None. Supported import decodes unassociated RGB/RGBA8/16/Float32 None/LZW/ZIP strips and integer/float predictors directly when the embedded and working profiles match. Planar associated-alpha samples are assembled natively before the established CoreGraphics conversion; other supported layouts use ImageIO/ColorSync.",
     "tiffJPEGCompression": "tiffCompression=jpeg writes bounded JPEG strips for RGB8 and Gray8 at up to 30,000 pixels per side. tiffJPEGQuality accepts 0...12; omission uses ImageIO quality 0.95. Composite opacity must be full unless tiffTransparency=false explicitly chooses a white matte. Supported editable layers and image pyramids are retained. Saved alpha and spot samples require lossless compression.",
     "tiffChannels": "Set tiffAlphaChannels and tiffSpotColors independently for lossless TIFF and BigTIFF. Omitted values follow tiffLayers for Photato API requests. Native Save and Save a Copy preselect each present channel type. The Adobe output contract keeps its published fields.",
     "tiffTransparency": "False composites the merged TIFF image over white and omits its opacity sample. Supported aligned Normal RGB16 layers use the measured Photoshop working-grid matte. Layer alpha is preserved when layers are enabled. Saved alpha and spot channels have their own lossless controls. True or omission retains the existing opacity behavior. Native Save, Save a Copy, authenticated downloads and Photato jobs share the encoder. The published Adobe output schema has no transparency field.",
     "tiffBigTIFF": "True writes BigTIFF with 64-bit offsets. It works with supported TIFF compression, layer, channel, profile and pyramid options. Omission or false writes classic TIFF. HTTP upload and download limits still apply.",
     "tiffImagePyramid": "True embeds three reduced-resolution previews in RGB, Grayscale, CMYK and Lab TIFF output. The full-resolution image and editable layers retain their normal save settings. Omission or false uses the ordinary save. Photato commands, downloads and action jobs share this option.",
     "tiffEmbedProfile": "Omission follows the document’s color profile policy. True includes the current ICC profile. False writes an untagged TIFF with the same pixel samples. Bitmap TIFF is untagged. Photato’s native save panel and local encoding options share this setting.",
     "limits": "Lossless compression retains the rendering/color/depth/metadata path; it is not a claim of complete Photoshop file-byte equivalence. TIFF supports RGB/Gray8/16/32, CMYK/Lab8/16 and flat Indexed8/Bitmap1 with supported transparency and profiles, bounded to512MiB encoded data. Explicit tiffLayers=true retains supported PSD layers/masks/groups/paths using big-endian structures by default; both byte orders support numeric adjustments and vector masks. Little-endian fill/path descriptors and opaque records remain guarded. tiffLayerCompression is rle or zip (default zip), requires tiffLayers=true, and is independent of composite compression. Ordinary Save defaults to preserving layers except for inherently flat Indexed/Bitmap documents; explicit false cannot flatten editable layered content in ordinary Save. Copy/download/job defaults remain flattened. 16/24-bit floating point, Duotone/Multichannel, exact Photoshop JPEG output and full TIFF workflows remain open. Restricted storage limits are listed in documentTransfers.restrictedFormats. Photoshop JPEG quantization/scans and full format-specific workflows remain open.",
     "adobe": "PNG compression and JPEG quality use pinned v2 named fields. JPEG seven quality names map locally to0/2/4/6/8/10/12; Adobe-equivalent quantization is unqualified. Execute-actions excludes scan (400); omitted quality retains the local0.95 default, not an asserted Adobe default. Photato action jobs additionally accept encodingOptions. Adobe output fields are not extended with Photato-only interlace or TIFF compression options."]
  }
  static func json(_ options: RasterEncodingOptions) -> [String: Any] {
    var result: [String: Any] = [:]
    if let value = options.exrCompression {result["exrCompression"] = value.rawValue}
    if let value = options.exrSample {result["exrSample"] = value.rawValue}
    if let value = options.exrTransparency {result["exrTransparency"] = value}
    if let value = options.jpegQuality { result["jpegQuality"] = value }
    if let value = options.jpegFormat { result["jpegFormat"] = value.rawValue }
    if let value = options.jpegMatte { result["jpegMatte"] = value }
    if let value = options.jpegEmbedProfile { result["jpegEmbedProfile"] = value }
    if let value = options.pngCompression { result["pngCompression"] = value }
    if let value = options.pngInterlaced { result["pngInterlaced"] = value }
    if let value = options.tiffCompression { result["tiffCompression"] = value.rawValue }
    if let value = options.tiffJPEGQuality { result["tiffJPEGQuality"] = value }
    if let value = options.tiffByteOrder { result["tiffByteOrder"] = value.rawValue }
    if let value = options.tiffPixelOrder { result["tiffPixelOrder"] = value.rawValue }
    if let value = options.tiffPredictor { result["tiffPredictor"] = value }
    if let value = options.tiffLayers { result["tiffLayers"] = value }
    if let value = options.tiffAlphaChannels { result["tiffAlphaChannels"] = value }
    if let value = options.tiffSpotColors { result["tiffSpotColors"] = value }
    if let value = options.tiffTransparency { result["tiffTransparency"] = value }
    if let value = options.tiffImagePyramid { result["tiffImagePyramid"] = value }
    if let value = options.tiffBigTIFF { result["tiffBigTIFF"] = value }
    if let value = options.tiffEmbedProfile { result["tiffEmbedProfile"] = value }
    if let value = options.tiffLayerCompression { result["tiffLayerCompression"] = value.rawValue }
    if let value = options.psdLayerCompression { result["psdLayerCompression"] = value.rawValue }
    if let value = options.psdCompositeCompression { result["psdCompositeCompression"] = value.rawValue }
    if let value = options.psdMaximizeCompatibility { result["psdMaximizeCompatibility"] = value }
    return result
  }
  static func parse(_ value: AutomationValue?, format: DocumentIO.Format) throws -> RasterEncodingOptions? {
    guard let value else { return nil }
    guard case .object(let fields) = value,
      Set(fields.keys).isSubset(of: ["exrCompression","exrSample","exrTransparency","jpegQuality", "jpegFormat", "jpegMatte", "jpegEmbedProfile", "pngCompression", "pngInterlaced", "tiffCompression",
        "tiffJPEGQuality", "tiffByteOrder", "tiffPixelOrder", "tiffPredictor", "tiffLayers", "tiffTransparency", "tiffImagePyramid", "tiffBigTIFF", "tiffEmbedProfile", "tiffLayerCompression", "tiffAlphaChannels", "tiffSpotColors",
        "psdLayerCompression", "psdCompositeCompression", "psdMaximizeCompatibility"]) else {
      throw AutomationFailure(status: 400, message: "Expected supported encoding options.")
    }
    var result = RasterEncodingOptions()
    if let raw=fields["exrCompression"] {
      guard case .string(let v)=raw,let value=OpenEXR.Compression(rawValue:v) else{throw AutomationFailure(status:400,message:"exrCompression must be none, zips or zip.")}
      result.exrCompression=value
    }
    if let raw=fields["exrSample"] {
      guard case .string(let v)=raw,let value=OpenEXR.Sample(rawValue:v) else{throw AutomationFailure(status:400,message:"exrSample must be half or float.")}
      result.exrSample=value
    }
    if let raw=fields["exrTransparency"] {
      guard case .bool(let value)=raw else{throw AutomationFailure(status:400,message:"exrTransparency must be boolean.")}
      result.exrTransparency=value
    }
    if let raw = fields["jpegQuality"] {
      guard case .number(let value) = raw, value.isFinite, value.rounded() == value,
        (0...12).contains(value) else {
        throw AutomationFailure(status: 400, message: "jpegQuality must be an integer from 0 through 12.")
      }
      result.jpegQuality = Int(value)
    }
    if let raw = fields["jpegFormat"] {
      guard case .string(let value) = raw, let format = RasterEncodingOptions.JPEGFormat(rawValue: value) else {
        throw AutomationFailure(status: 400, message: "jpegFormat must be baseline, optimized or progressive.")
      }
      result.jpegFormat = format
    }
    if let raw = fields["jpegMatte"] {
      guard case .array(let values) = raw, values.count == 3 else {
        throw AutomationFailure(status: 400, message: "jpegMatte requires three sRGB numbers.")
      }
      result.jpegMatte = try values.map { value in
        guard case .number(let number) = value, number.isFinite, (0...1).contains(number) else {
          throw AutomationFailure(status: 400, message: "jpegMatte components must be numbers from 0 through 1.")
        }
        return number
      }
    }
    if let raw = fields["jpegEmbedProfile"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "jpegEmbedProfile must be boolean.")
      }
      result.jpegEmbedProfile = value
    }
    if let raw = fields["pngCompression"] {
      guard case .number(let number) = raw, number.isFinite, number.rounded() == number,
        (0...9).contains(number) else {
        throw AutomationFailure(status: 400, message: "pngCompression must be an integer from 0 through 9.")
      }
      result.pngCompression = Int(number)
    }
    if let raw = fields["pngInterlaced"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "pngInterlaced must be boolean.")
      }
      result.pngInterlaced = value
    }
    if let raw = fields["tiffCompression"] {
      guard case .string(let value) = raw, let compression = RasterEncodingOptions.TIFFCompression(rawValue: value) else {
        throw AutomationFailure(status: 400, message: "tiffCompression must be none, lzw, zip or jpeg.")
      }
      result.tiffCompression = compression
    }
    if let raw = fields["tiffJPEGQuality"] {
      guard case .number(let value) = raw, (0...12).contains(value), value == value.rounded() else {
        throw AutomationFailure(status: 400, message: "tiffJPEGQuality must be an integer from 0 through 12.")
      }
      result.tiffJPEGQuality = Int(value)
    }
    if let raw = fields["tiffByteOrder"] {
      guard case .string(let value) = raw, let order = RasterEncodingOptions.TIFFByteOrder(rawValue: value) else {
        throw AutomationFailure(status: 400, message: "tiffByteOrder must be bigEndian or littleEndian.")
      }
      result.tiffByteOrder = order
    }
    if let raw = fields["tiffPixelOrder"] {
      guard case .string(let value) = raw, let order = RasterEncodingOptions.TIFFPixelOrder(rawValue: value) else {
        throw AutomationFailure(status: 400, message: "tiffPixelOrder must be interleaved or perChannel.")
      }
      result.tiffPixelOrder = order
    }
    if let raw = fields["tiffPredictor"] {
      guard case .bool(let enabled) = raw else {
        throw AutomationFailure(status: 400, message: "tiffPredictor must be boolean.")
      }
      result.tiffPredictor = enabled
    }
    if let raw = fields["tiffLayers"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffLayers must be boolean.")
      }
      result.tiffLayers = value
    }
    if let raw = fields["tiffAlphaChannels"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffAlphaChannels must be boolean.")
      }
      result.tiffAlphaChannels = value
    }
    if let raw = fields["tiffSpotColors"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffSpotColors must be boolean.")
      }
      result.tiffSpotColors = value
    }
    if let raw = fields["tiffTransparency"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffTransparency must be boolean.")
      }
      result.tiffTransparency = value
    }
    if let raw = fields["tiffBigTIFF"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffBigTIFF must be boolean.")
      }
      result.tiffBigTIFF = value
    }
    if let raw = fields["tiffImagePyramid"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffImagePyramid must be boolean.")
      }
      result.tiffImagePyramid = value
    }
    if let raw = fields["tiffEmbedProfile"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "tiffEmbedProfile must be boolean.")
      }
      result.tiffEmbedProfile = value
    }
    if let raw = fields["tiffLayerCompression"] {
      guard case .string(let value) = raw,
        let compression = RasterEncodingOptions.TIFFLayerCompression(rawValue: value) else {
        throw AutomationFailure(status: 400, message: "tiffLayerCompression must be rle or zip.")
      }
      result.tiffLayerCompression = compression
    }
    for key in ["psdLayerCompression", "psdCompositeCompression"] {
      if let raw = fields[key] {
        guard case .string(let value) = raw,
          let compression = RasterEncodingOptions.PhotoshopCompression(rawValue: value) else {
          throw AutomationFailure(status: 400, message: "\(key) must be raw, rle, zip or zipPrediction.")
        }
        if key == "psdLayerCompression" { result.psdLayerCompression = compression }
        else { result.psdCompositeCompression = compression }
      }
    }
    if let raw = fields["psdMaximizeCompatibility"] {
      guard case .bool(let enabled) = raw else {
        throw AutomationFailure(status: 400, message: "psdMaximizeCompatibility must be boolean.")
      }
      result.psdMaximizeCompatibility = enabled
    }
    do { try result.validate(for: format.contentType) } catch {
      throw AutomationFailure(status: 400, message: error.localizedDescription)
    }
    return result
  }
  static func header(_ value: String?, format: DocumentIO.Format) throws -> RasterEncodingOptions {
    guard let value else { return .init() }
    guard value.utf8.count <= 2048,
      let raw = try? JSONDecoder().decode(AutomationValue.self, from: Data(value.utf8)) else {
      throw AutomationFailure(status: 400, message: "Invalid X-Photato-Export-Options JSON.")
    }
    return try parse(raw, format: format) ?? .init()
  }
}
