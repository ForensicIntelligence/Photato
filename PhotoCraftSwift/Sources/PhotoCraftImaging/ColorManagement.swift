import AppKit
import CoreGraphics
import Foundation
import PhotoCraftCore

/// Colour conversion happens at document boundaries. Editing samples stay in working coordinates.
public enum ColorManagement {
  public static func space(for document: CraftDocument) throws -> CGColorSpace {
    if let profile = document.workingICC {
      try ICCProfile.validate(profile, linear: document.depth == .f32)
      guard let space = CGColorSpace(iccData: profile as CFData), space.model == .rgb else {
        throw CraftError.invalid("The working RGB ICC profile cannot be used by ColorSync.")
      }
      return space
    }
    return document.depth == .f32
      ? CGColorSpace(name: CGColorSpace.linearSRGB)! : try RasterIO.colorSpace()
  }
  public static func importedProfile(_ profile: Data?, depth: PixelDepth) throws -> Data? {
    guard let profile else { return nil }
    try ICCProfile.validate(profile, linear: false)
    guard let source = CGColorSpace(iccData: profile as CFData), source.model == .rgb else {
      throw CraftError.invalid("Invalid embedded RGB ICC profile.")
    }
    if try depth != .f32 || ICCProfile.isLinear(profile) { return profile }
    // Photoshop RGB32 uses linear light. Retain the matrix primaries when linearizing.
    guard let linear = CGColorSpaceCreateLinearized(source),
      let data = linear.copyICCData() as Data?
    else {
      throw CraftError.unsupported("This RGB32 profile cannot be linearized.")
    }
    try ICCProfile.validate(data, linear: true)
    return data
  }
  public static func name(_ document: CraftDocument) -> String {
    if document.modeDescriptor != nil || document.profileIsUntagged == true { return ColorProfileInput.name(document) }
    guard document.workingICC != nil else { return document.depth == .f32 ? "Linear sRGB" : "sRGB" }
    return (try? NSColorSpace(cgColorSpace: space(for: document))?.localizedName) ?? "Embedded RGB"
  }
  public static func image(_ surface: Surface, in document: CraftDocument) throws -> CGImage {
    try RasterIO.cgImage(
      surface, space: space(for: document),
      colorEncoding: document.depth == .f32 ? .linearRGB : .sRGB)
  }
  /// An SDR preview is converted to sRGB before quantization; the editing buffer is untouched.
  public static func displayImage(_ surface: Surface, in document: CraftDocument) throws -> CGImage
  {
    guard document.workingICC != nil else { return try RasterIO.displayImage(surface) }
    let display = try converted(surface, from: document, to: CraftDocument(width: 1, height: 1))
    return try RasterIO.displayImage(display)
  }
  public static func converted(
    _ surface: Surface, from source: CraftDocument,
    to target: CraftDocument
  ) throws -> Surface {
    if surface.width * surface.height > Surface.maximumDensePixels {
      return try convertedPaged(surface, from: source, to: target)
    }
    let fromSpace = try space(for: source)
    let toSpace = try space(for: target)
    let encoding: SurfaceColorEncoding = target.depth == .f32 ? .linearRGB : .sRGB
    if fromSpace == toSpace && (source.depth == .f32) == (target.depth == .f32) {
      return try surface.converted(to: target.depth)
    }
    // Convert opaque RGB so transparent pixels keep hidden colour. Alpha is never colour-managed.
    let inputEncoding: SurfaceColorEncoding = source.depth == .f32 ? .linearRGB : .sRGB
    var opaque = try surface.interpretingSamples(as: surface.colorEncoding)
    if opaque.colorEncoding == .linearRGB {
      for y in 0..<opaque.height {
        try Task.checkCancellation()
        for x in 0..<opaque.width {
          let p = opaque.linearPixel(x: x, y: y)
          opaque.setLinearPixel(x: x, y: y, Pixel(p.r, p.g, p.b))
        }
      }
    } else {
      opaque.mapPixels { _, _, p in Pixel(p.r, p.g, p.b) }
    }
    var result = try RasterIO.surface(
      RasterIO.cgImage(opaque, space: fromSpace, colorEncoding: inputEncoding),
      depth: target.depth, space: toSpace, colorEncoding: encoding)
    for y in 0..<result.height {
      try Task.checkCancellation()
      for x in 0..<result.width {
        var p = encoding == .linearRGB ? result.linearPixel(x: x, y: y) : result.pixel(x: x, y: y)
        p.a = surface.pixel(x: x, y: y).a
        if encoding == .linearRGB {
          result.setLinearPixel(x: x, y: y, p)
        } else {
          result.setPixel(x: x, y: y, p)
        }
      }
    }
    return result
  }
  public static func color(_ pixel: Pixel, in document: CraftDocument) throws -> CGColor {
    let p = document.depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    guard
      let color = CGColor(
        colorSpace: try space(for: document),
        components: [CGFloat(p.r), CGFloat(p.g), CGFloat(p.b), CGFloat(p.a)])
    else {
      throw CraftError.invalid("Invalid document colour.")
    }
    return color
  }
  public static func pixel(_ color: CGColor, in document: CraftDocument) throws -> Pixel {
    guard
      let values = color.converted(
        to: try space(for: document),
        intent: .relativeColorimetric, options: nil)?.components, values.count == 4
    else {
      throw CraftError.invalid("Could not convert the chosen colour to the document profile.")
    }
    let pixel = Pixel(Float(values[0]), Float(values[1]), Float(values[2]), Float(values[3]))
    return document.depth == .f32 ? SRGBTransfer.encoded(pixel) : pixel
  }
  /// Raster transfer preserves the target profile. Editable profile-dependent adjustments
  /// require a separate conversion policy and are rejected, never silently re-tagged.
  public static func converted(_ content: ClipboardContent, to target: CraftDocument) throws
    -> ClipboardContent
  {
    if content.document.restrictedMode != nil { return try converted(ClipboardRenderer.flattened(content), to: target) }
    if content.document.workingICC == target.workingICC,
      (content.document.depth == .f32) == (target.depth == .f32)
    {
      return content
    }
    let source = content.document
    var result = content
    result.restrictedSamples = nil // Profile/depth conversion invalidates direct sample identity.
    for i in result.document.layers.indices {
      switch result.document.layers[i].content {
      case .raster(let s):
        result.document.layers[i].content = .raster(try converted(s, from: source, to: target))
      case .fill(let p):
        result.document.layers[i].content = .fill(try pixel(color(p, in: source), in: target))
      case .shape(var s):
        if var definition=s.definition {
          guard [.none,.solid].contains(definition.fill.kind),[.none,.solid].contains(definition.stroke.paint.kind) else {throw CraftError.unsupported("Rasterize gradient/pattern shapes before transferring between different profiles.")}
          definition.fill.color=try pixel(color(definition.fill.color,in:source),in:target)
          definition.stroke.paint.color=try pixel(color(definition.stroke.paint.color,in:source),in:target)
          s.definition=definition
        }
        s.color = try pixel(color(s.color, in: source), in: target)
        result.document.layers[i].content = .shape(s)
      case .text(var t):
        t.color = try pixel(color(t.color, in: source), in: target)
        result.document.layers[i].content = .text(t)
      case .group: break
      default:
        throw CraftError.unsupported(
          "Convert profile-dependent fill and adjustment layers to pixels before transferring between colour profiles."
        )
      }
    }
    result.document.depth = target.depth
    result.document.workingICC = target.workingICC
    try result.validate()
    return result
  }
}


extension ColorManagement {
  static func convertedPaged(_ surface: Surface, from source: CraftDocument, to target: CraftDocument) throws -> Surface {
    var output = try Surface(width: surface.width, height: surface.height, depth: target.depth,
      colorEncoding: target.depth == .f32 ? .linearRGB : .sRGB)
    let store = try RasterTileStore()
    for y in stride(from: 0, to: surface.height, by: Surface.tileSide) {
      for x in stride(from: 0, to: surface.width, by: 2048) {
        try Task.checkCancellation()
        let bounds = IntRect(x: x, y: y, width: min(2048, surface.width - x), height: min(Surface.tileSide, surface.height - y))
        let patch = try converted(surface.cropped(to: bounds), from: source, to: target)
        try output.importPatch(patch, atX: x, atY: y, backing: store)
      }
    }
    return output
  }
}
