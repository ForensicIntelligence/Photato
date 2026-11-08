import Foundation
import PhotoCraftCore
import UniformTypeIdentifiers

/// Explicit encoding choices; nil retains the existing platform encoder defaults.
/// Lossless compression does not change the rendering or color conversion path.
public struct RasterEncodingOptions: Codable, Hashable, Sendable {
  public enum JPEGFormat: String, Codable, CaseIterable, Sendable {
    case baseline, optimized, progressive
  }
  public var jpegQuality: Int?
  public var jpegFormat: JPEGFormat?
  /// Opaque sRGB matte, three finite components in 0...1.
  public var jpegMatte: [Double]?
  public var jpegEmbedProfile: Bool?
  public enum PhotoshopCompression: String, Codable, CaseIterable, Sendable {
    case raw, rle, zip, zipPrediction
    public var codec: PSDCompression {
      switch self { case .raw: .raw; case .rle: .rle; case .zip: .zip; case .zipPrediction: .zipPrediction }
    }
  }
  public enum TIFFCompression: String, Codable, CaseIterable, Sendable {
    case none, lzw, zip
    public var tag: Int { switch self { case .none: 1; case .lzw: 5; case .zip: 8 } }
  }
  public enum TIFFByteOrder: String, Codable, CaseIterable, Sendable {
    case bigEndian, littleEndian
  }
  public enum TIFFPixelOrder: String, Codable, CaseIterable, Sendable {
    case interleaved, perChannel
  }
  public enum TIFFLayerCompression: String, Codable, CaseIterable, Sendable {
    case rle, zip
    public var codec: PSDCompression { self == .rle ? .rle : .zip }
  }
  public var exrCompression: OpenEXR.Compression?
  public var exrSample: OpenEXR.Sample?
  public var exrTransparency: Bool?
  public var pngCompression: Int?
  public var pngInterlaced: Bool?
  public var tiffCompression: TIFFCompression?
  public var tiffByteOrder: TIFFByteOrder?
  public var tiffPixelOrder: TIFFPixelOrder?
  public var tiffPredictor: Bool?
  public var tiffLayers: Bool?
  public var tiffLayerCompression: TIFFLayerCompression?
  public var psdLayerCompression: PhotoshopCompression?
  public var psdCompositeCompression: PhotoshopCompression?
  public init(pngCompression: Int? = nil, pngInterlaced: Bool? = nil,
    tiffCompression: TIFFCompression? = nil, psdLayerCompression: PhotoshopCompression? = nil,
    psdCompositeCompression: PhotoshopCompression? = nil,
    tiffByteOrder: TIFFByteOrder? = nil, tiffPixelOrder: TIFFPixelOrder? = nil,
    tiffPredictor: Bool? = nil, tiffLayers: Bool? = nil,
    tiffLayerCompression: TIFFLayerCompression? = nil,
    jpegQuality: Int? = nil, jpegFormat: JPEGFormat? = nil,
    jpegMatte: [Double]? = nil, jpegEmbedProfile: Bool? = nil,
    exrCompression: OpenEXR.Compression? = nil, exrSample: OpenEXR.Sample? = nil, exrTransparency: Bool? = nil)
  {
    self.exrCompression = exrCompression; self.exrSample = exrSample; self.exrTransparency = exrTransparency
    self.jpegQuality = jpegQuality
    self.jpegFormat = jpegFormat
    self.jpegMatte = jpegMatte
    self.jpegEmbedProfile = jpegEmbedProfile
    self.pngCompression = pngCompression
    self.pngInterlaced = pngInterlaced
    self.tiffCompression = tiffCompression
    self.tiffByteOrder = tiffByteOrder
    self.tiffPixelOrder = tiffPixelOrder
    self.tiffPredictor = tiffPredictor
    self.tiffLayers = tiffLayers
    self.tiffLayerCompression = tiffLayerCompression
    self.psdLayerCompression = psdLayerCompression
    self.psdCompositeCompression = psdCompositeCompression
  }
  public var isEmpty: Bool {
    pngCompression == nil && pngInterlaced == nil && tiffCompression == nil
      && psdLayerCompression == nil && psdCompositeCompression == nil && !hasTIFFStorageOptions
      && tiffLayers == nil && tiffLayerCompression == nil
      && !hasJPEGOptions && exrCompression == nil && exrSample == nil && exrTransparency == nil
  }
  public var hasJPEGOptions: Bool {
    jpegQuality != nil || jpegFormat != nil || jpegMatte != nil || jpegEmbedProfile != nil
  }
  public var hasTIFFStorageOptions: Bool {
    tiffByteOrder != nil || tiffPixelOrder != nil || tiffPredictor != nil
  }
  public func validate(for type: UTType) throws {
    if let quality = jpegQuality, !(0...12).contains(quality) {
      throw CraftError.invalid("JPEG quality must be an integer from 0 through 12.")
    }
    if let matte = jpegMatte,
      matte.count != 3 || !matte.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
      throw CraftError.invalid("JPEG matte requires three sRGB components from 0 through 1.")
    }
    if let level = pngCompression, !(0...9).contains(level) {
      throw CraftError.invalid("PNG compression must be an integer from 0 through 9.")
    }
    guard (type == .png || (pngCompression == nil && pngInterlaced == nil)),
      (type == .jpeg || !hasJPEGOptions),
      (type == OpenEXR.contentType || (exrCompression == nil && exrSample == nil && exrTransparency == nil)),
      (type == .tiff || (tiffCompression == nil && !hasTIFFStorageOptions
        && tiffLayers == nil && tiffLayerCompression == nil)),
      (["com.adobe.photoshop-image", "com.adobe.photoshop-large-image"].contains(type.identifier)
        || (psdLayerCompression == nil && psdCompositeCompression == nil)) else {
      throw CraftError.invalid("Encoding options do not match the selected output format.")
    }
    if tiffPredictor == true, tiffCompression != .lzw && tiffCompression != .zip {
      throw CraftError.invalid("TIFF predictor requires LZW or ZIP compression.")
    }
    if tiffLayerCompression != nil, tiffLayers != true {
      throw CraftError.invalid("TIFF layer compression requires tiffLayers=true.")
    }
  }
}
