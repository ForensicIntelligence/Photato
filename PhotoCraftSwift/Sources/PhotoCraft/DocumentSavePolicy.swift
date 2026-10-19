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
    case .psd:
      return
        "Keeps supported editable layers and masks. Uses sRGB (linear sRGB for 32-bit). Full source-profile, metadata and 32-bit precision preservation are still in development."
    case .png, .tiff:
      return
        "Saves a single pixel layer at its current 8- or 16-bit depth, using sRGB. Use Save a Copy for a flattened version of a layered document."
    case .jpeg:
      return
        "Saves a single opaque 8-bit pixel layer using sRGB and 95% JPEG quality. JPEG compression changes pixels."
    }
  }
}

extension DocumentIO {
  /// Save/Save As preserve the editable content representable by the chosen format.
  /// Copy/export intentionally has a different, flattening contract.
  static func persistenceIssue(_ document: CraftDocument, format: Format) -> String? {
    if format == .native { return nil }
    if format == .psd {
      guard document.width <= 30_000, document.height <= 30_000, document.pixelsPerInch < 65_536
      else {
        return "PSD dimensions or resolution exceed the supported format limits."
      }
      for layer in document.layers {
        switch layer.content {
        case .raster where layer.affine == nil, .group, .fill, .gradientFill, .patternFill: break
        case .adjustment(let adjustment):
          switch adjustment {
          case .levels, .curves, .hueSaturation, .colorBalance, .tonalSteps: break
          case .gradientMap where document.depth != .f32: break
          default: return "This adjustment is not yet editable in PSD. Save as Photato."
          }
        default:
          return "This live or transformed layer is not yet editable in PSD. Save as Photato."
        }
        if layer.mask != nil || layer.vectorMask != nil {
          let t = layer.maskCoordinateTransform
          let p = layer.effectiveMaskProperties
          guard t.a == 1, t.b == 0, t.c == 0, t.d == 1,
            t.tx == t.tx.rounded(), t.ty == t.ty.rounded(), p.outside == 0 || p.outside == 1
          else { return "This transformed mask is not yet editable in PSD. Save as Photato." }
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
    guard document.depth != .f32 else {
      return
        "This format's current encoder cannot retain 32-bit pixels. Save as Photato or PSD, or use Save a Copy to convert to 16-bit."
    }
    if format == .jpeg {
      guard document.depth == .u8 else {
        return "JPEG needs an 8-bit document. Use Save a Copy to convert."
      }
      for y in 0..<pixels.height {
        for x in 0..<pixels.width where pixels.pixel(x: x, y: y).a != 1 {
          return "JPEG cannot retain transparency. Use Save a Copy for a white-matte version."
        }
      }
    }
    return nil
  }
  static func encodeForPersistence(_ document: CraftDocument, format: Format) throws -> Data {
    if let issue = persistenceIssue(document, format: format) {
      throw CraftError.unsupported(issue)
    }
    return try encode(document, format: format)
  }
}
