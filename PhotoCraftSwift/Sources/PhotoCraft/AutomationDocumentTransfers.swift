import AppKit
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

extension DocumentIO {
  static func decodeUpload(_ data: Data, native: Bool, name: String) throws -> CraftDocument {
    guard !data.isEmpty, data.count <= maximumUploadBytes else {
      throw AutomationFailure(status: 413, message: "Upload must contain 1 byte to 64 MiB.")
    }
    if !native, MovieIO.recognizes(data) { return try MovieIO.decode(data,name:name,maximumBytes:128*1024*1024,maximumPixels:4_194_304) }
    let width: Int
    let height: Int
    if native {
      (width, height) = try NativeArchive.dimensions(data)
    } else if OpenEXR.recognizes(data) {
      (width,height) = try OpenEXR.dimensions(data)
    } else if PcraftImport.recognizes(data) {
      (width, height) = try PcraftImport.dimensions(data)
    } else if data.starts(with: Data("8BPS".utf8)) {
      guard data.count >= 26 else {
        throw AutomationFailure(status: 422, message: "Truncated PSD header.")
      }
      func number(_ offset: Int) -> Int {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
      }
      (width, height) = (number(18), number(14))
    } else {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int,
        let h = properties[kCGImagePropertyPixelHeight] as? Int
      else { throw AutomationFailure(status: 422, message: "Unsupported image data.") }
      (width, height) = (w, h)
    }
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension else {
      throw AutomationFailure(status: 413, message: "Upload exceeds300,000 pixels per side. Codec, heap and transfer budgets apply separately.")
    }
    return try decode(data, native: native, name: name, rasterByteLimit: 128 * 1_024 * 1_024)
  }
}

extension AutomationService {
  static var documentTransferCapabilities: [String: Any] {
    [
      "encodingOptions": DocumentEncodingOptions.capabilities,
      "pagedRasterInput": RasterStorageAPI.capabilities,
      "movieFramesImport": MovieFramesAPI.capabilities,
      "pdfImport": PDFImportAPI.capabilities,
      "illustratorPaths": IllustratorPathExportAPI.capabilities,
      "import": [
        "method": "POST", "path": "/v1/documents/import", "successStatus": 201,
        "contentTypes": DocumentIO.uploadTypes,
        "formatHeader": ["name": "X-Photato-Open-Format", "required": false,
          "schema": ["type": "string", "enum": DocumentOpenFormat.allCases.filter{$0 != .pdf}.map(\.rawValue)],
          "untypedBody": "application/octet-stream is accepted only when the format header is present"],
        "bodySchema": [
          "type": "string", "format": "binary", "minLength": 1,
          "maxLength": DocumentIO.maximumUploadBytes,
        ],
        "nameHeader": [
          "name": "X-Photato-Name", "required": false,
          "schema": ["type": "string", "minLength": 1, "maxLength": 256, "pattern": "^[ -~]+$"],
        ],
        "result":
          "New shared document state, including id, revision and isModified. Native archives retain their stored name.",
      ],
      "download": [
        "method": "GET", "path": "/v1/documents/{id}/file.{format}",
        "formats": DocumentIO.Format.allCases.map(\.rawValue),
        "formatAliases": ["pcswift": DocumentIO.Format.native.rawValue],
        "responseTypes": DocumentIO.Format.allCases.map(\.mediaType),
        "maxBytes": DocumentIO.maximumDownloadBytes,
        "revisionHeader": "Optional X-Photato-Revision must equal the current document revision.",
        "result":
          "Binary snapshot; native archives retain editable structure, PSD/PSB retain supported structures, raster outputs flatten.",
      ],
      "auxiliaryPhotoshop":ChannelAPI.photoshopCapabilities,
      "multichannelPhotoshop": [
        "formats": ["psd", "psb"], "bitsPerChannel": [8, 16], "maximumChannels": 56,
        "maximumPixels": 8_388_608, "compression": ["raw", "rle", "zip", "zipPrediction"],
        "preserves": ["numeric ink samples", "alpha masks", "channel order within ink/mask groups", "Unicode names", "spot display colors", "solidity", "saved paths", "resolution"],
        "limits": "Flat Multichannel mode7. Display colors quantize to16-bit RGB and opacity/solidity to whole percentages when changed; imported supported color records are reused unchanged. Active Quick Mask, private color-book records and Duotone PSD remain unsupported. Exact Photoshop composite rendering is unqualified.",
        "routes": ["GET /v1/documents/{id}/file.psd", "GET /v1/documents/{id}/file.psb", "POST /v1/documents/import", "document.saveAs", "POST /v1/action-jobs", "POST /v2/execute-actions"],
      ],
      "nativeArchives": [
        "writeVersion": 11, "largeFileFallbackVersion":63,"pagedSelectionVersion":64, "readVersions": Array(1...89),"customShapeBlurVersion":87,"galleryTextureVersion":88,"channelOnlyVersion":85,"componentPageVersion":86,"layerLinksVersion":84,"backgroundLayerVersion":83,"linkedSmartObjectVersion":66,"extendedShapeVersion":68,"extendedTypeVersion":69,"extendedSmartObjectVersion":70,"relightVersion":71,"lightingEffectsVersion":72,"sourceDisplacementVersion":73,"sourceAdjustmentVersion":74,"advancedLayerStyleVersion":75,"auxiliarySpotVersion":76,"parentSmartObjectCompVersion":81,"emptyLayerCompOptionsVersion":82,"sourceLayerCompClearVersion":82,"smartObjectLayerCompVersion":80,"layerCompsVersion":79,"documentGuidesVersion":78,"psdChannelRetentionVersion":77,"exposureAdjustmentVersion":67,"modernAdjustmentVersion":65, "partialProtectionVersion": 12, "layerStyleVersion": 13, "smartObjectVersion": 14, "smartFilterVersion": 15, "richTextVersion": 16, "classicAdjustmentVersion": 17, "colorLookupVersion": 18, "liquifyVersion": 19, "alphaChannelVersion": 20, "cameraRawVersion": 21, "rawSourceVersion": 22, "imageStackVersion": 23, "warpVersion": 24, "puppetVersion": 25, "perspectiveVersion": 26, "artboardVersion": 27, "frameVersion": 28, "blurGalleryVersion": 29, "lensCorrectionVersion": 30, "wideAngleVersion": 31, "vanishingPointVersion": 32, "liveShapeVersion":33,"advancedTypographyVersion":34,"shapedTextVersion":35,"filterGalleryVersion":36,"photoDetailVersion":37,"lensBlurVersion":38,"distortionVersion":39,"pixelateVersion":40,"stylizeVersion":41,"renderVersion":42,"otherVideoVersion":43,"classicDetailVersion":44,"shadowsHighlightsVersion":45,"documentModeVersion":46,"restrictedModeVersion":47,"inkModeVersion":48,"untaggedProfileVersion":49,"animationVersion":50,"videoVersion":51,"movieVersion":52,"keyframeVersion":53,"arrangementVersion":54,"transitionVersion":55,"timelineAudioVersion":56,"timelineWorkspaceVersion":57,"timelineTrimVersion":58,"frameTimelineConversionVersion":59,"sampledFrameVersion":60,"variablesVersion":61,"pdfSmartObjectVersion":62,"hierarchicalIndexVersion":63,
        "downloadDefaultVersion": 10,
        "downloadVersionHeader": [
          "name": "X-Photato-Archive-Version", "required": false,
          "schema": ["type": "string", "enum": ["10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88"], "default": "10"],
          "scope":
            "Native downloads only; both file.photato and file.pcswift remain equivalent aliases",
        ],
        "extension": "photato", "legacyExtension": "pcswift",
        "layout":
          "Version11/12/13 indexed tile/selection blobs with binary-plist metadata and SHA256 integrity checks",
        "fileIO":
          "Native Open/Save/Copy/autosave use bounded64KiB physical reads/writes; Data API output uses the identical serializer",
        "samplePreservation":
          "Exact stored Float32 bits, profiles, editable structure and metadata",
        "maxFileBytes": NativeArchive.maximumBytes,
        "desktopFileMaximumBytes": NativeArchive.maximumFileBytes,
        "dataAndMetadataMaximumBytes": NativeArchive.maximumBytes,
        "legacyEncode":
          "Core encode emits10, desktop saves11; partial protection requires12, layer styles13, Smart Objects14 and Smart Filters15. Native downloads require explicit opt-in to the required version.",
        "limits":
          "Metadata, selection and active document remain resident; full paging, crash-relaunch recovery, large-file and live platform qualification remain open",
      ],
      "layeredTIFF": [
        "input": true, "output": true,
        "colorModes": ["rgb": [8, 16, 32], "grayscale": [8, 16, 32], "cmyk": [8, 16], "lab": [8, 16]],
        "depths": [8, 16, 32], "byteOrders": ["bigEndian", "littleEndian"],
        "layerCompression": ["raw", "rle", "zip", "zipPrediction"],
        "outputLayerCompression": ["rle", "zip"],
        "scope": "Classic TIFF Photoshop ImageSourceData: RGB/Gray/CMYK/Lab raster layers, groups, masks and Unicode names in both byte orders. RGB additionally supports numeric adjustments and vector masks. Retained global mask-display metadata survives TIFF/PSD/PSB output. Big-endian records share supported PSD rich-layer decoding.",
        "limits": "Little-endian fill/path descriptors and opaque blocks, PSB-style ImageSourceData, non-default layered orientation, non-RGB rich content, spot inks, indexed/bitmap modes and native-mode tiled/JPEG-compressed input remain unsupported. Unsupported records reject instead of flattening. Classic output is bounded to512MiB and1024 layer records including group markers. Flattened Gray/CMYK components remain numerical; Lab16 composite chroma is quantized to the TIFF signed 1/256 scale (up to one native code step). Layer planes remain exact. Multi-layer mode previews still use RGB composition/reseparation. Full Photoshop byte parity remains unqualified.",
        "api": "Native Open, Photato import, and both action-job inputs share the decoder. Native Save and Photato save commands default to preserving layers. Copy/download and Photato jobs preserve layers with encodingOptions.tiffLayers=true; default exports remain flattened. TIFF layer compression is rle or zip and requires tiffLayers=true. Omitted layered byte order is bigEndian. The Adobe TiffOutput contract has no preservation field; its flattened output stays unchanged.",
      ],
      "restrictedFormats": [
        "modes": ["indexed": 8, "bitmap": 1], "nativeArchive": 47,
        "inputOutput": ["psd", "psb", "png", "tiff"],
        "storage": "One flat palette-index or packed bilevel raster; duplicate palette indices and a single transparent index are retained. Native47 preserves the complete restricted store. TIFF supports both byte orders and interleaved/per-channel unassociated alpha; palette count/transparency use Photoshop resources.",
        "psdCompression": ["indexed": ["raw", "rle", "zip", "zipPrediction"], "bitmap": ["raw", "rle", "zip"]],
        "png": "Indexed1/2/4/8-bit and grayscale1-bit input; indexed8-bit or grayscale1-bit output; all scanline filters/Adam7 decode and optional Adam7 output.",
        "tiff": "Palette1/2/4/8-bit and bilevel strip/tile input, raw/LZW/ZIP/PackBits;8-bit palette or1-bit bilevel output with raw/LZW/ZIP. Single transparent index can use unassociated alpha samples. Rotated raster samples retain index/bit identity.",
        "api": "Native Open/Save and Photato import/download use shared codecs. Existing Photato/Adobe action-job resource paths share the same native decoder/encoder; conversion commands are not yet advertised.",
        "limits": "8,388,608 pixels before the lower existing API/job budgets. Flat storage only. No auxiliary channels, PSD layers, restricted TIFF ImageSourceData, CCITT, non-square pixels or high-precision TIFF ColorMap. PNG multiple/partial alpha, animated PNG, TIFF transfer tables and rotated saved paths reject explicitly. Full Photoshop numerical/file equivalence and broader contexts remain unqualified."
      ],
      "photoshopContainers": [
        "readVersions": [1, 2], "writeFormats": ["psd", "psb"],
        "colorModes": ["rgb": [8, 16, 32], "grayscale": [8, 16, 32], "cmyk": [8, 16], "lab": [8, 16], "indexed": [8], "bitmap": [1], "multichannel": [8, 16]],
        "psbMediaType": "application/x-photoshop",
        "maximumFileBytes": PSDCodec.maximumFileBytes,"maximumPSDFileBytes":PSDCodec.maximumPSDFileBytes,"maximumDataBytes":PSDCodec.maximumInputBytes,"maximumRetainedMetadataBytes":PSDCodec.maximumMetadataBytes,
        "maximumDimension": Surface.maxDimension, "maximumPixels": Surface.maxPixels,
        "streamingLargeFiles": true,
        "smartFilterCaches":["rowBasedWrite":true,"boundedReaderViews":true,"pagedMasks":true,
          "maximumRetainedDerivedCacheBytes":8*1_024*1_024,"maskPatchPixels":2048*64,
          "scope":"Supported editable RGB Smart Filter descriptors/source caches and geometric masks use shared native PSD/PSB file, import/export and job codecs. Large embedded RGB source composition retains pages.",
          "limits":"Embedded sources remain64MiB each; source/retained metadata, API64MiB transfers/128MiB decoded heap, local job64MiB resources/128MiB aggregates, separate4MP analysis/artboard limits, output formats, unsupported descriptors/modes/mask options and physical capacity/performance remain independent. Full Photoshop/cache/descriptor/platform equality is unqualified."],
        "pagedRGB":["depths":[8,16,32],"rasterLayers":true,"rasterMasks":true,"flattenedMerged":true,"patchPixels":2048*64,"nativeTileScratchMaximumBytes":RasterTileStore.defaultMaximumBytes,"rawPlaneStagingMaximumBytes":RasterTileStore.defaultMaximumBytes,"apiHeapMaximumBytes":128*1_024*1_024,"decoderHeapMaximumBytes":1_073_741_824,"rowPatchHeapReserveBytes":PSDCodec.pagedWorkingHeapReserveBytes,"nativeFileAdmissionNotice":"PSB4TiB/PSD2GiB implementation limits; not the format maximum. Raw staging, mapped samples and metadata have distinct budgets; residency is managed by macOS."],
        "pagedNativeComponents": ["modes":["grayscale":[8,16,32],"cmyk":[8,16],"lab":[8,16]],"maximumDimension":Surface.maxDimension,"maximumPixels":NativeModeRaster.maximumDocumentPixels,"rasterLayers":true,"flattenedMerged":true,"rawWords":true,"componentWriteCacheBlocks":2,"sharedRGBAndComponentScratchBudget":true,"mergedOutput":"Bounded RGB composition and the same native conversion/matting math as smaller documents; original layer separations remain independent.","interfaces":"Native file Open/Save/Save As/Save a Copy, paged uploads, Data decoding and both isolated resource job interfaces share the codec. Existing per-interface container, heap, output, resource and permission limits remain.","limits":"Native sample geometry admits300000per side; this is not full maximum dense capacity qualification. TIFF/printing and other dense operations keep separate admissions. Full Photoshop mode composition, hidden-color/default, corruption corpus, multiGB, live/platform and60fps fidelity remain open."],
        "fileInput": [
          "boundedReads": true, "readWindowBytes": PSDCodec.fileReadWindowBytes,
          "maximumCacheBytes": PSDCodec.maximumFileCacheBytes,
          "consistency":
            "Owned regular-file descriptor; detects observed changes, truncation and replacement before accepting decoded content.",
          "scope":
            "Native PSD/PSB file opens/reverts and paged Photato binary uploads share parsing and paged RGB/native-component assembly. Native files use disk-backed samples; API uploads retain heap/container limits; paged samples have a separate scratch bound.",
        ],
        "fileOutput": [
          "boundedWrites": true, "maximumWriteBytes": AtomicFileWriter.chunkBytes,
          "rowBasedCompression": true, "checkedLengthBackpatching": true,
          "atomicReplacement": true,
          "scope":
            "Native PSD/PSB Save, Save As, Save a Copy and API local saves stage private files. API downloads and both job interfaces share the serializer with Data output. Large RGB and native-component merged previews render bounded regions; staged copies admit exactly their known file size. Data downloads and jobs retain their separate budgets.",
        ],
        "channelDecoding": [
          "rowBased": true, "nestedSectionViews": true, "zipInputChunkBytes": 65536,
          "unusedMergedCache": "Validated row-by-row without retaining decoded cache bytes.",
          "limits":
            "Data input and retained metadata remain512MiB. Native RGB and Gray/CMYK/Lab samples use private paged storage; other modes retain separate admissions. Channels stream validated rows; whole-plane array helpers retain512MiB limits.",
        ],
        "scope":
          "RGB8/16/32 plus native Grayscale8/16/32 and CMYK/Lab8/16 raster layers, groups, masks and ICC profiles in PSD/PSB. Non-RGB editable type/fill/adjustment/Smart Object records remain unsupported. Native components use bounded raw pages and merged preview bands; existing API transfer/job budgets also apply. PSB uses64bit lengths and32bit RLE row tables. Mode blend/composite fidelity remains unqualified.",
        "adobeJobs":
          "Both job interfaces can decode PSB resource inputs. The published image/vnd.adobe.photoshop output remains PSD; PSB output is available through Photato file.psb and document.saveAs format psb.",
        "limits":
          "Full90GP/dense stress, all Photoshop content/modes and physical/platform/independent live PSB qualification remain open. Native files admit4TiB PSB/2GiB PSD; API uploads/downloads/jobs keep separately advertised bounds.",
      ],
      "metadata": [
        "raster":
          "Retains imported ImageIO camera, copyright, descriptive and XMP metadata where the output format supports it; updates orientation, dimensions, resolution and sRGB color-space fields.",
        "psd":
          "Retains opaque image-resource blocks except regenerated profile/resolution/paths and stale thumbnail, layer-index, selection, version and recovery records. Retention does not implement unsupported Photoshop workflows.",
        "profiles":
          "PSD and native archives retain actual RGB working profiles separately from source provenance. RGB32 uses linear matrix profiles. Integer raster exports retain working profiles; HDR raster exports convert to SDR sRGB. Display previews convert to sRGB. Full Photoshop conversion-policy and rendering equivalence remain unqualified.",
        "metadataLimitBytes": 16 * 1024 * 1024,
        "workingProfileLimitBytes": ICCProfile.maximumBytes,
        "workingProfileMaximumTags": ICCProfile.maximumTags,
      ],
      "float32Storage": [
        "nativeArchiveVersion": 10, "latestNativeArchiveVersion":92, "nativeArchiveWriteVersions":Array(10...92),
        "encoding": "linearRGB",
        "preservation":
          "Supported RGB32 PSD raster samples retain their IEEE754 bits through native archives, metadata-only edits and straight PSD layer output. PSD merged color samples use separately rounded white-distance matting, including opaque samples.",
        "normalRasterComposition": [
          "scope":
            "Root untransformed Normal raster stacks; linear Float32 mask-before-opacity, fused alpha and color interpolation. Original Photoshop references cover opaque/translucent HDR samples, Cartesian alpha pairs, offset masks, layer opacity and three-layer stacks.",
          "mergedEncoding":
            "Big-endian planar Float32 RGB with white matte and straight alpha; opaque Photoshop references may omit the alpha plane.",
          "exactWholePSDFile": false,
        ],
        "normalHierarchyComposition": [
          "scope":
            "Untransformed Normal RGB32 raster layers in Pass Through and isolated groups, group opacity/masks, and raster clipping chains with Blend Clipped Layers as Group enabled. Shared linear evaluation preserves measured Photoshop rounding.",
          "limitations":
            "Independent clipping blending, clipping groups, non-Normal blends, affine/rich layers and arbitrary profiles remain unqualified.",
          "exactWholePSDFile": false,
        ],
        "limits":
          "Complete group/clipping combinations, transforms, non-Normal blends, adjustments, arbitrary profiles and all HDR edits are not fully qualified for exact Photoshop output. Finite-range composition overflow reports an error. Source RGB32 replacement still requires Save As review.",
        "interfaces": [
          "document downloads", "document.save", "document.saveAs", "/v1/action-jobs",
          "/v2/execute-actions",
        ],
      ],
      "saveCopy": [
        "desktopCommand": "File > Save a Copy…", "shortcut": "Option-Command-S",
        "apiOperation": "GET /v1/documents/{id}/file.{format}",
        "formats": DocumentIO.Format.allCases.map {
          ["format": $0.rawValue, "effect": $0.copyDescription]
        },
        "stateEffect":
          "Does not change the open document, its filename, modified flag or undo/redo history.",
      ],
      "revert": [
        "command": "document.revert", "method": "POST", "path": "/v1/documents/{id}/commands",
        "parameters": "Empty object; current revision is required. No filesystem paths accepted.",
        "stateEffect":
          "Reads only the associated local file; restores it as one undoable edit and clears the modified flag. Upload-only documents have no source until saved in the desktop.",
        "limits": "Same 64 MiB input, pixel, layer and decoded-memory limits as uploads.",
      ],
      "availability":
        "Requires native document-transfer enablement and session authentication. Downloads additionally require an existing document share. One transfer at a time; eight shared documents maximum.",
      "connectionLifecycle":
        "Request receipt and response delivery each have a15-second transport deadline. Accepted native decoding/encoding is not limited by that deadline; server stop still cancels work. Client timeouts and independent resource limits apply.",
      "errors": [
        "400": "Invalid name", "401": "Authentication", "403": "Disabled",
        "404": "Missing share/route", "409": "Busy, stale, changed or revoked",
        "413": "Resource limit", "415": "Content type",
        "422": "Decode/encode or unsupported format semantics", "429": "Transfer or share capacity",
      ],
      "persistence":
        "No filesystem paths accepted. Uploads create unsaved native documents. Downloads never save or clear desktop dirty/history state. Explicit document.revert reloads only the already-associated file and is undoable.",
      "adobe":
        "Desktop open/download has no dedicated Adobe v2 endpoint. Existing execute-actions resource input/output remains a separately qualified subset using the shared native codecs.",
    ]
  }

  func handleDocumentTransfer(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let importing = request.method == "POST" && request.path == "/v1/documents/import"
    let parts = request.path.split(separator: "/")
    let format =
      parts.count == 4 && parts[0] == "v1" && parts[1] == "documents"
        && parts[3].hasPrefix("file.")
      ? DocumentIO.Format(fileExtension: String(parts[3].dropFirst(5))) : nil
    let downloading = request.method == "GET" && format != nil
    guard importing || downloading, request.path == "/" + parts.joined(separator: "/") else {
      return nil
    }
    if importing, controller.recoveryIndex.isBusy || controller.documentClosing.isActive || controller.documentOpening.isActive || controller.documentOpening.hasPendingRequests {
      throw AutomationFailure(status: 409, message: "Wait for document opening or closing before importing.")
    }
    guard documentTransfersEnabled else {
      throw AutomationFailure(
        status: 403, message: "Enable document uploads and downloads in the native API window.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status: 429, message: "A document transfer is already in progress.")
    }
    let expectedGeneration = documentTransferGeneration
    let expectedToken = token
    let closingOperation = controller.documentClosing.state?.id
    let openingOperation = controller.documentOpening.generation
    let maintenanceGeneration = controller.recoveryMaintenance.generation
    let discoveryGeneration = controller.recoveryDiscovery.generation
    documentTransferBusy = true
    defer { documentTransferBusy = false }
    func validateSession() throws {
      guard !Task.isCancelled, isRunning, token == expectedToken, documentTransfersEnabled,
        documentTransferGeneration == expectedGeneration
      else {
        throw AutomationFailure(status: 409, message: "Document transfer was cancelled or revoked.")
      }
    }

    if importing {
      guard
        let contentType = request.headers["content-type"]?.lowercased().split(separator: ";").first
          .map(String.init),
        (DocumentIO.uploadTypes.contains(contentType) || (contentType == "application/octet-stream" && request.headers["x-photato-open-format"] != nil))
      else {
        throw AutomationFailure(
          status: 415, message: "Choose a supported image or Photato document Content-Type.")
      }
      if MovieIO.mediaTypes.contains(contentType), !MovieIO.recognizes(request.body) {throw AutomationFailure(status:422,message:"Expected a supported movie container.")}
      if RawSourceIO.mediaTypes.contains(contentType), !RawSourceIO.recognizes(request.body) { throw AutomationFailure(status:422,message:"Expected supported camera RAW sensor data.") }
      let name = request.headers["x-photato-name"] ?? "Imported Image"
      guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 256,
        name.utf8.allSatisfy({ (32...126).contains($0) })
      else {
        throw AutomationFailure(
          status: 400, message: "X-Photato-Name must contain 1–256 printable ASCII characters.")
      }
      guard shares.count < 8 else {
        throw AutomationFailure(status: 429, message: "Share up to eight documents at once.")
      }
      guard NSApp?.modalWindow == nil else {
        throw AutomationFailure(
          status: 409, message: "Finish the modal dialog before opening a document.")
      }
      let selection: DocumentOpenFormat?
      if let raw = request.headers["x-photato-open-format"] {
        guard let format = DocumentOpenFormat(rawValue: raw) else {
          throw AutomationFailure(status: 400, message: "Unknown X-Photato-Open-Format.")
        }
        selection = format
      } else { selection = nil }
      if selection == .pdf {
        throw AutomationFailure(status:422,message:"Use POST /v1/documents/import/pdf with X-Photato-PDF-Options to select PDF pages; ordinary import returns a single document.")
      }
      let frameOptions = try MovieFramesAPI.options(request.headers[MovieFramesAPI.header])
      if frameOptions != nil {
        guard MovieIO.mediaTypes.contains(contentType) || (contentType == "application/octet-stream" && selection == .movie),MovieIO.recognizes(request.body) else {throw AutomationFailure(status:415,message:"Movie-frame import requires a supported movie Content-Type and container.")}
        guard controller.canFinishMovieFrames else {throw AutomationFailure(status:409,message:"Finish the current document workflow before importing movie frames.")}
      }
      let native = contentType == DocumentIO.Format.native.mediaType
      let decoder = documentDecoder
      let colorSettings = controller.colorSettings.value
      let colorChoice = try ColorPolicyAPI.choice(request.headers["x-photato-color-decision"], opening: true)
      let worker = Task.detached(priority: .utility) {
        let usesNative: Bool
        if let selection {
          let actual = DocumentOpenFormat.detect(request.body)
          try selection.validate(actual)
          guard actual != .pdf else {throw AutomationFailure(status:422,message:"Use POST /v1/documents/import/pdf to choose PDF pages and render settings.")}
          usesNative = actual == .native
        } else { usesNative = native }
        if let frameOptions {
          guard colorChoice == nil else {throw AutomationFailure(status:400,message:"Movie-frame import creates sRGB layers; omit X-Photato-Color-Decision.")}
          return try MovieFrames.decode(request.body,name:name,options:frameOptions,maximumBytes:128*1024*1024,maximumPixels:4_194_304,maximumLayers:64)
        }
        var decoded = try decoder(request.body, usesNative, name)
        if usesNative {
          guard colorChoice == nil else { throw AutomationFailure(status: 400, message: "Native Photato imports retain their saved interpretation; omit X-Photato-Color-Decision.") }
          return decoded
        }
        if [.psd, .psb].contains(DocumentOpenFormat.detect(request.body)), decoded.sourceICC == nil { decoded.profileIsUntagged = true }
        return try ColorPolicyInput.opening(decoded, settings: colorSettings, choice: colorChoice)
      }
      let frameOperation = frameOptions == nil ? nil:UUID()
      if let frameOperation {movieFramesImportOperationID = frameOperation;movieFramesImportTask = worker}
      defer {if let frameOperation,movieFramesImportOperationID == frameOperation {movieFramesImportOperationID = nil;movieFramesImportTask = nil}}
      let model = try await withTaskCancellationHandler(
        operation: { try await worker.value }, onCancel: { worker.cancel() })
      if frameOptions != nil {guard !worker.isCancelled,controller.canFinishMovieFrames else {throw CancellationError()}}
      try validateSession()
      try Self.checkLimits(model)
      guard NSApp?.modalWindow == nil, !controller.documentClosing.isActive,
        !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests,
        controller.documentClosing.state?.id == closingOperation,
        controller.documentOpening.generation == openingOperation,
        !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenanceGeneration,
        controller.recoveryDiscovery.generation == discoveryGeneration else {
        throw AutomationFailure(status: 409, message: "A document lifecycle operation started during the transfer.")
      }
      guard shares.count < 8 else {
        throw AutomationFailure(
          status: 429, message: "Document sharing capacity changed during upload.")
      }
      let document = CraftNSDocument(model: model)
      if frameOptions != nil {document.store.timelineVisible = model.animation != nil}
      controller.addDocument(document)
      do { try share(document) } catch {
        controller.removeDocument(document)
        throw error
      }
      document.updateChangeCount(.changeDone)
      document.makeWindowControllers()
      document.showWindows()
      guard let share = shares.first(where: { $0.document === document }) else {
        throw AutomationFailure(status: 409, message: "Document sharing ended.")
      }
      return .json(state(share, document: document), status: 201)
    }

    guard let format, let id = UUID(uuidString: String(parts[2])),
      let share = shares.first(where: { $0.id == id }), let document = share.document
    else {
      throw AutomationFailure(status: 404, message: "Shared document not found.")
    }
    try preflight(document)
    try Self.checkLimits(document.store.document)
    let expectedRevision = revision(document.store)
    guard
      request.headers["x-photato-revision"] == nil
        || request.headers["x-photato-revision"] == expectedRevision
    else {
      throw AutomationFailure(status: 409, message: "Stale document revision.")
    }
    let requestedArchiveVersion = request.headers["x-photato-archive-version"]
    if format == .native,document.store.document.requiresHueRangeColorArchive,requestedArchiveVersion != "92" {throw AutomationFailure(status:422,message:"Sampled Hue/Saturation display colors require X-Photato-Archive-Version:92.")}
    if format == .native,document.store.document.requiresSelectedGrayArchive,!["91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Retained selected-area Float32 gray requires X-Photato-Archive-Version:91.")}
    if format == .native,document.store.document.minimumArchiveVersion>=90,!["90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Sparse video frames require X-Photato-Archive-Version:90.")}
    if format == .native,document.store.document.requiresChannelBlendingArchive,!["89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Channel blending requires X-Photato-Archive-Version:89.")}
    if format == .native, document.store.document.requiresGalleryTextureArchive, !["88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"Custom Gallery textures require X-Photato-Archive-Version:88.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 87, !["87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"Custom Shape Blur kernels require X-Photato-Archive-Version:87.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 86, !["86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"Large component documents require X-Photato-Archive-Version:86.")
    }
    if format == .native,document.store.document.minimumArchiveVersion>=84,!["84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Layer links require X-Photato-Archive-Version: 84.")}
    if format == .native,document.store.document.layers.contains(where:{$0.isBackground}),!["83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Background identity requires X-Photato-Archive-Version: 83.")}
    if format == .native,document.store.document.isChannelOnly,!["85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"A channel-only document requires native archive version85.")}
    if format == .native, document.store.document.requiresLayerComp82Archive, !["82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"This document requires Layer Comp metadata archive version82.") }
    if format == .native,document.store.document.layerComps?.requiresSmartObjectSelectionArchive == true,!["81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Parent Layer Comp Smart Object choices require X-Photato-Archive-Version: 81.")}
    if format == .native,document.store.document.requiresSmartObjectLayerCompArchive,!["80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Smart Object Layer Comp selection requires X-Photato-Archive-Version: 80.")}
    if format == .native,document.store.document.layerComps != nil,!["79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Layer Comps require X-Photato-Archive-Version: 79.")}
    if format == .native,document.store.document.guides != nil,!["78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Document guides require X-Photato-Archive-Version: 78.")}
    if format == .native,document.store.document.hasPSDChannelRetention,!["77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Retained PSD channel metadata and Float32 gray require X-Photato-Archive-Version: 77.")}
    if format == .native,document.store.document.hasSpotChannels,!["76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Auxiliary spot channels require X-Photato-Archive-Version: 76.")}
    if format == .native,document.store.document.minimumArchiveVersion>=75,!["75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Advanced styles and shared light require X-Photato-Archive-Version: 75.")}
    if format == .native,document.store.document.minimumArchiveVersion>=74,!["74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Original adjustment controls require X-Photato-Archive-Version: 74.")}
    if format == .native,document.store.document.minimumArchiveVersion>=73,!["73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Source Displace/transparent edge settings require X-Photato-Archive-Version: 73.")}
    if format == .native,document.store.document.minimumArchiveVersion>=72,!["72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Lighting Effects settings require X-Photato-Archive-Version: 72.")}
    if format == .native,document.store.document.minimumArchiveVersion>=71,!["71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Relight settings require X-Photato-Archive-Version: 71.")}
    if format == .native,document.store.document.minimumArchiveVersion>=70,!["70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Source Smart Objects require X-Photato-Archive-Version: 70.")}
    if format == .native,document.store.document.minimumArchiveVersion>=69,!["69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Rich type formatting and original appearance require X-Photato-Archive-Version: 69.")}
    if format == .native,document.store.document.minimumArchiveVersion>=68,!["68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Extended shape paths, stroke controls and imported appearance require X-Photato-Archive-Version: 68.")}
    if format == .native,document.store.document.minimumArchiveVersion>=67,!["67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Complete Exposure adjustments require X-Photato-Archive-Version: 67.")}
    if format == .native,document.store.document.minimumArchiveVersion>=66,!["66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Linked Smart Objects require X-Photato-Archive-Version: 66.")}
    if format == .native,document.store.document.minimumArchiveVersion>=65,!["65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Modern adjustment layers require X-Photato-Archive-Version: 65.")}
    if let requestedArchiveVersion {
      guard format == .native, ["10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion) else {
        throw AutomationFailure(
          status: 400, message: "X-Photato-Archive-Version must be 10 through92 on native downloads.")
      }
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 62, !["62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"Retained PDF Smart Objects require X-Photato-Archive-Version: 62.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 61, !["61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Variables and data sets require X-Photato-Archive-Version: 61.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 60, !["60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Sampled frame animation requires X-Photato-Archive-Version: 60.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 59, !["59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Converted frame Timelines require X-Photato-Archive-Version: 59.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 58, !["58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Trimmed Timelines require X-Photato-Archive-Version: 58.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 57, !["57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Timeline work areas/onion settings require X-Photato-Archive-Version: 57.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 56, !["56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Timeline audio requires X-Photato-Archive-Version: 56.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 55, !["55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Video transitions require X-Photato-Archive-Version: 55.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 54, !["54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Video arrangement requires X-Photato-Archive-Version: 54.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 53, !["53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Video keyframes require X-Photato-Archive-Version: 53.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 52, !["52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Movie sources require X-Photato-Archive-Version: 52.")}
    if format == .native, document.store.document.videoTimeline != nil, !["51","52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Video requires X-Photato-Archive-Version: 51.") }
    if format == .native, document.store.document.animation != nil, !["50","51","52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status: 422, message: "Frame animation requires X-Photato-Archive-Version: 50.") }
    if format == .native, document.store.document.requiresPartialProtectionArchive,
      !["12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422,
        message: "Partial layer protection requires X-Photato-Archive-Version: 12.")
    }
    if format == .native, document.store.document.requiresLayerStylesArchive, !["13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Layer styles require X-Photato-Archive-Version: 13.")
    }
    if format == .native, document.store.document.profileIsUntagged == true, !["49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status: 422, message: "Untagged documents require X-Photato-Archive-Version: 49.") }
    if format == .native, document.store.document.inkMode != nil, !["48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Duotone and Multichannel require X-Photato-Archive-Version: 48.")
    }
    if format == .native, document.store.document.restrictedMode != nil, !["47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Indexed Color and Bitmap require X-Photato-Archive-Version: 47.")
    }
    if format == .native, document.store.document.hasNativeModeStorage, !["46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Native color components require X-Photato-Archive-Version: 46.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 45, !["45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Shadows/Highlights Smart Filters require X-Photato-Archive-Version: 45.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 44, !["44","45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Blur/Noise/Sharpen Smart Filters require X-Photato-Archive-Version: 44.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 43, !["43","44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Other/Video Smart Filters require X-Photato-Archive-Version: 43.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 42, !["42","43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Render Smart Filters require X-Photato-Archive-Version: 42.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 41, !["41","42","43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Stylize Smart Filters require X-Photato-Archive-Version: 41.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 40, !["40","41", "42","43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Pixelate Smart Filters require X-Photato-Archive-Version: 40.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 39, !["39","40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Distortion Smart Filters require X-Photato-Archive-Version: 39.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 38, !["38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Lens Blur requires X-Photato-Archive-Version: 38.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 37, !["37","38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {throw AutomationFailure(status:422,message:"Photo detail requires X-Photato-Archive-Version: 37.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 36, !["36","37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Editable Filter Gallery requires X-Photato-Archive-Version: 36.") }
    if format == .native, document.store.document.hasShapedText,!["35","36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? ""){throw AutomationFailure(status:422,message:"Shaped text requires X-Photato-Archive-Version: 35.")}
    if format == .native, document.store.document.hasAdvancedTypography,!["34","35","36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? ""){throw AutomationFailure(status:422,message:"Advanced typography requires X-Photato-Archive-Version: 34.")}
    if format == .native, document.store.document.minimumArchiveVersion >= 33, !["33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Live shapes require X-Photato-Archive-Version: 33.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 32, !["32","33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Vanishing Point planes require X-Photato-Archive-Version: 32.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 31, !["31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Adaptive Wide Angle requires X-Photato-Archive-Version: 31.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 30, !["30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Lens Correction requires X-Photato-Archive-Version: 30.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 29, !["29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Blur Gallery requires X-Photato-Archive-Version: 29.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 28, !["28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Frames require X-Photato-Archive-Version: 28.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 27, !["27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Artboards require X-Photato-Archive-Version: 27.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 26, !["26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Editable Perspective Warp requires X-Photato-Archive-Version: 26.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 25, !["25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Editable Puppet Warp requires X-Photato-Archive-Version: 25.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 24, !["24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Editable Warp requires X-Photato-Archive-Version: 24.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 23, !["23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") { throw AutomationFailure(status:422,message:"Image stacks require X-Photato-Archive-Version: 23.") }
    if format == .native, document.store.document.minimumArchiveVersion >= 22, !["22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"RAW sources require X-Photato-Archive-Version: 22.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 21, !["21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"Camera Raw Smart Filters require X-Photato-Archive-Version: 21.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 20, !["20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status:422,message:"Alpha channels and Quick Mask require X-Photato-Archive-Version: 20.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 19, !["19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Liquify Smart Filters require X-Photato-Archive-Version: 19.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 18, !["18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Color Lookup requires X-Photato-Archive-Version: 18.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 17, !["17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Classic adjustments require X-Photato-Archive-Version: 17.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 16, !["16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Rich text requires X-Photato-Archive-Version: 16.")
    }
    if format == .native, document.store.document.minimumArchiveVersion >= 15, !["15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Smart Filters require X-Photato-Archive-Version: 15.")
    }
    if format == .native, document.store.document.requiresSmartObjectArchive, !["14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52","53","54","55","56","57","58","59","60","61","62","63","64","65","66","67","68","69","70","71","72","73","74","75","76","77","78","79","80","81","82","83","84","85","86","87","88","89","90","91","92"].contains(requestedArchiveVersion ?? "") {
      throw AutomationFailure(status: 422, message: "Embedded Smart Objects require X-Photato-Archive-Version: 14 or15.")
    }
    let legacyNative = format == .native && (requestedArchiveVersion == nil || requestedArchiveVersion == "10")
    let options = document.effectiveEncodingOptions(
      try DocumentEncodingOptions.header(request.headers["x-photato-export-options"], format: format),
      format: format)
    let snapshot = document.store.document
    let worker = Task.detached(priority: .utility) {
      if format == .native, let version = requestedArchiveVersion.flatMap(Int.init), version >= 12 {
        return try NativeArchive.encodeChunked(snapshot, minimumVersion: version)
      }
      return legacyNative
        ? try NativeArchive.encode(snapshot) : try DocumentIO.encode(snapshot, format: format, options: options)
    }
    let data = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try validateSession()
    prune()
    guard shares.contains(where: { $0.id == id }), revision(document.store) == expectedRevision
    else {
      throw AutomationFailure(
        status: 409, message: "Document changed or sharing ended during encoding.")
    }
    guard data.count <= DocumentIO.maximumDownloadBytes else {
      throw AutomationFailure(
        status: 413, message: "Encoded document exceeds the 128 MiB download limit.")
    }
    return .init(status: 200, contentType: format.mediaType, body: data)
  }
}
