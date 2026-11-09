import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension DocumentIO.Format {
  var typeIdentifier: String { contentType.identifier }
  init?(typeIdentifier: String) {
    guard let format = Self.allCases.first(where: { $0.typeIdentifier == typeIdentifier }) else {
      return nil
    }
    self = format
  }
  var saveNotice: String {
    switch self {
    case .native: return "Keeps all editable Photato content."
    case .psd, .psb:
      return
        "Keeps supported editable layers, masks, alpha/spot channels, Quick Mask and the working profile. Full Photoshop metadata, rendering and 32-bit output equivalence are still in development."
    case .exr:
      return "Keeps one flat 32-bit scene-linear RGB layer and optional transparency. Use Save a Copy for Half precision, profile conversion or flattened content."
    case .png:
      return
        "Saves a single pixel layer at its current 8- or 16-bit depth, using its RGB working profile. Use Save a Copy for a flattened version of a layered document."
    case .tiff:
      return
        "Keeps supported editable layers, masks and paths at 8-, 16- or 32-bit depth. Both byte orders retain supported numeric adjustments and vector masks. Fill/path descriptors and opaque records currently require big-endian TIFF."
    case .jpeg:
      return
        "Saves a single opaque 8-bit pixel layer using the selected JPEG quality, format and color-profile settings. JPEG compression changes pixels."
    }
  }
}

extension DocumentIO {
  /// Save/Save As preserve the editable content representable by the chosen format.
  /// Copy/export intentionally has a different, flattening contract.
  static func persistenceIssue(_ document: CraftDocument, format: Format,
    options: RasterEncodingOptions = .init()) -> String? {
    if format == .native { return nil }
    if document.layers.contains(where:{$0.sourceTags?[GeneratedImageStorage.recordKey] != nil || $0.sourceTags?[GeneratedImageStorage.originalKey] != nil}) {
      return "Save as Photato to retain generated-image records and original results. Use Save a Copy for other formats."
    }
    if format != .psd,format != .psb,document.layers.contains(where: { $0.nativeMode?.requiresPagedArchive == true }) {
      return "Save this large component document as Photato, PSD or PSB. Other component-format encoders retain separate limits."
    }
    if document.isChannelOnly {
      if format == .psd || format == .psb {
        return document.depth == .f32 ? "Save this standalone32-bit document as Photato to retain its channels.":nil
      }
      return "Save this channel-only document as Photato, PSD or PSB. Load the mask into an image for ordinary image export."
    }
    if (format == .psd || format == .psb),let issue=DocumentGuideInput.photoshopPersistenceIssue(document){return issue}
    if format == .exr {
      guard document.depth == .f32,document.colorMode == .rgb,document.inkMode == nil,document.restrictedMode == nil else{return "OpenEXR requires a 32-bit RGB document."}
      if options.exrSample == .half {return "Use Save a Copy for reduced-precision Half samples."}
      if (try? ColorManagement.space(for:document)) != CGColorSpace(name:CGColorSpace.linearSRGB) {return "Use Save a Copy to convert the working profile to scene-linear sRGB."}
      if document.layers.contains(where:{$0.smartObject != nil || $0.smartFilters != nil || $0.style != nil || $0.warp != nil || $0.sourceProjection != nil}) {return "Use Save a Copy to flatten editable layer content."}
    }
    if document.width * document.height > Surface.maximumDensePixels, format != .psd, format != .psb, format != .exr {
      return "Save this large canvas as Photato. Streamed full-size raster and PSD/PSB output is not yet available."
    }
    if document.variables != nil { return "Save as Photato to retain variables, data sets and replacement images. Export a data-set variation for other formats." }
    if document.videoTimeline != nil { return "Save as Photato to retain video frames and timing. Still-image copies contain only the current frame." }
    if document.animation != nil { return "Save as Photato to retain animation. Still-image copies contain only the selected frame." }
    if document.vanishingPoint != nil { return "Save as Photato to retain Vanishing Point planes, or export a rendered copy." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .adaptiveWideAngle }) == true }) { return "Save as Photato to retain editable Adaptive Wide Angle, or export a rendered copy." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .lensCorrection }) == true }) { return "Save as Photato to retain editable Lens Correction, or export a rendered copy." }
    if document.layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind.isRender}) == true}) {return "Save as Photato to retain editable Render settings."}
    if document.layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind.isStylize && $0.filter.kind != .emboss}) == true}) {return "Save as Photato to retain editable Stylize settings."}
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind.isPixelate }) == true }) { return "Save as Photato to retain editable Pixelate settings." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind.isDistortion }) == true }) { return "Save as Photato to retain editable distortion settings and displacement maps." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .lensBlur }) == true }) { return "Save as Photato to retain editable Lens Blur settings and depth references." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .smartSharpen || $0.filter.kind == .reduceNoise }) == true }) { return "Save as Photato to retain editable Smart Sharpen / Reduce Noise settings." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .filterGallery }) == true }) { return "Save as Photato to retain editable Filter Gallery effects." }
    if document.layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .blurGallery }) == true }) { return "Save as Photato to retain editable Blur Gallery, or export a rendered copy." }
    if document.hasFrames { return "Save as Photato to retain editable frames, or export a rendered copy." }
    if document.hasArtboards {
      guard format == .psd || format == .psb else { return "Save as Photato, PSD or PSB to retain artboards. Export individual artboards for other formats." }
      if let issue=PSDArtboardInterchange.photoshopPersistenceIssue(document) { return issue }
    }
    if document.inkMode != nil {
      guard document.colorMode == .multichannel, format == .psd || format == .psb else {
        return "Save as Photato to retain ink settings. Multichannel also supports PSD/PSB; use Save a Copy for rendered raster output."
      }
      let maximum = format == .psb ? PSDFileFormat.psb.maximumDimension : PSDFileFormat.psd.maximumDimension
      if document.width > maximum || document.height > maximum || document.pixelsPerInch >= 65536 {
        return "Dimensions or resolution exceed the selected Photoshop format's limits."
      }
      return nil
    }
    if document.hasAuxiliaryChannels,format != .psd,format != .psb { return "Save as Photato to retain alpha channels and Quick Mask. Save a Copy can export a flattened image." }
    if document.restrictedMode != nil {
      if format == .jpeg { return "JPEG cannot retain Indexed Color or Bitmap mode. Use Save a Copy or convert the document to RGB." }
      if format == .png, !(document.paths ?? []).isEmpty { return "Save as Photato, PSD or TIFF to retain saved paths." }
      if format == .tiff, options.tiffLayers == true || options.tiffPredictor == true { return "Indexed Color and Bitmap TIFF use flat samples without a floating-point predictor." }
      if format == .psd || format == .psb {
        let maximum = format == .psb ? PSDFileFormat.psb.maximumDimension : PSDFileFormat.psd.maximumDimension
        if document.width > maximum || document.height > maximum || document.pixelsPerInch >= 65536 { return "Dimensions or resolution exceed the selected Photoshop format's limits." }
        if document.colorMode == .bitmap, options.psdCompositeCompression == .zipPrediction { return "Bitmap Photoshop files support None, RLE or ZIP compression." }
      }
      return nil
    }
    if format == .psd || format == .psb || (format == .tiff && options.tiffLayers != false) {
      let maximum =
        format == .psb ? PSDFileFormat.psb.maximumDimension : PSDFileFormat.psd.maximumDimension
      guard document.width <= maximum, document.height <= maximum, document.pixelsPerInch < 65_536
      else {
        return "Dimensions or resolution exceed the selected Photoshop format's limits."
      }
      for layer in document.layers {
        let photoshopSmartObject=(format == .psd || format == .psb) && layer.smartObject != nil
        if photoshopSmartObject,let source=layer.smartObject {
          if source.linkedSource != nil,source.mediaType=="application/vnd.photato.document" {return "Use a Photato package for linked Photato originals, or convert the original to a Photoshop-supported format."}
          if layer.warp != nil || source.stackMode != nil || source.rawDevelopment != nil {return "Save as Photato to retain editable Warp, image-stack or RAW Smart Object settings."}
          if let pdf=source.pdfSource,pdf.image != nil || !pdf.antialias {return "Save as Photato to retain PDF image selection and nondefault antialias settings."}
        }
        switch layer.content {
        case .raster where layer.affine == nil || photoshopSmartObject, .group, .fill, .gradientFill, .patternFill: break
        case .text(let t):
          if let space = try? ColorManagement.space(for: document), let srgb = try? RasterIO.colorSpace(),
            space != srgb && !(document.depth == .f32 && space == CGColorSpace(name: CGColorSpace.linearSRGB)) { return "Editable PSD type requires an sRGB working profile." }
          let type = t.promoted(dpi: document.pixelsPerInch).typography!
          if type.defaultParagraph.direction == .rightToLeft || type.runs.contains(where: { $0.paragraph.direction == .rightToLeft }) { return "RTL type requires Photato format until its PSD mapping is qualified." }
        case .adjustment(let adjustment):
          switch adjustment {
          case .levels, .curves, .hueSaturation, .colorBalance, .classic, .tonalSteps: break
          case .gradientMap where document.depth != .f32: break
          default: return "This adjustment is not yet editable in PSD. Save as Photato."
          }
        default:
          return "This live or transformed layer is not yet editable in PSD. Save as Photato."
        }
        if let mask=layer.mask {
          let t=layer.maskCoordinateTransform,p=layer.effectiveMaskProperties
          guard p.outside==0 || p.outside==1 else{return "PSD mask outside coverage must be black or white. Save as Photato."}
          let aligned=t.a==1 && t.b==0 && t.c==0 && t.d==1 && t.tx==t.tx.rounded() && t.ty==t.ty.rounded()
          if !aligned {
            guard p.feather==0 else{return "Transformed feathered masks require Photato format until PSD feather-space interchange is qualified."}
            // Match PSDMaskExport's metadata-only admission, without rendering on
            // menu validation or silently flattening native masks.
            guard (try? (t * .translation(-1,-1)).bounds(width:mask.width+2,height:mask.height+2)) != nil else{return "The projected PSD mask exceeds supported bounds. Save as Photato."}
          }
        } else if layer.vectorMask != nil {
          let t=layer.maskCoordinateTransform,p=layer.effectiveMaskProperties
          guard t.a==1 && t.b==0 && t.c==0 && t.d==1 && t.tx==t.tx.rounded() && t.ty==t.ty.rounded() && (p.outside==0 || p.outside==1) else{return "This transformed vector-only mask still requires Photato format."}
        }
      }
      return nil
    }
    guard document.layers.count == 1, let layer = document.layers.first,
      case .raster(let pixels) = layer.content,
      layer.visible, layer.opacity == 1, layer.blendMode == .normal, !layer.isClipped,
      layer.mask == nil, layer.vectorMask == nil, layer.affine == nil,
      layer.x == 0, layer.y == 0, pixels.width == document.width, pixels.height == document.height,
      (document.paths ?? []).isEmpty
    else {
      return
        "Save as Photato or PSD to keep editable layers, masks and paths. Use Save a Copy for a flattened image."
    }
    guard document.depth != .f32 || format == .tiff || format == .exr else {
      return
        "This format's current encoder cannot retain 32-bit pixels. Save as Photato or PSD, or use Save a Copy to convert to 16-bit."
    }
    if format == .exr,options.exrTransparency == false,
      (try? pixels.allStoredSamplesSatisfy({$0.a == 1})) != true {return "Use Save a Copy to omit transparency."}
    if format == .jpeg {
      guard document.depth == .u8 else {
        return "JPEG needs an 8-bit document. Use Save a Copy to convert."
      }
      guard (try? pixels.allStoredSamplesSatisfy({ $0.a == 1 })) == true else {
        return "JPEG cannot retain transparency. Use Save a Copy to choose a matte."
      }
    }
    return nil
  }
  static func encodeForPersistence(_ document: CraftDocument, format: Format,
    options: RasterEncodingOptions = .init()) throws -> Data {
    let options = persistenceOptions(options, format: format, document: document)
    if let issue = persistenceIssue(document, format: format, options: options) {
      throw CraftError.unsupported(issue)
    }
    return try encode(document, format: format, options: options)
  }
  static func persistenceOptions(_ requested: RasterEncodingOptions, format: Format, document: CraftDocument? = nil) -> RasterEncodingOptions {
    var result = requested
    if format == .tiff, result.tiffLayers == nil { result.tiffLayers = document?.restrictedMode == nil }
    return result
  }
}
