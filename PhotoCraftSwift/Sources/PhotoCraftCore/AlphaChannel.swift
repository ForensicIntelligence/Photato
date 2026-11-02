import Foundation

/// Permanent grayscale masks and temporary Quick Mask, ported from PhotoCraft's channel model.
public struct ChannelDisplayOptions: Codable, Equatable, Sendable {
  public enum Indicates: String, Codable, CaseIterable, Sendable { case maskedAreas, selectedAreas }
  public var color = Pixel(1,0,0)
  public var opacity: Float = 0.5
  public var indicates: Indicates = .maskedAreas
  public init() {}
  public func validate() throws {
    guard color.isFinite, color.a == 1, [color.r,color.g,color.b,opacity].allSatisfy({ (0...1).contains($0) }) else { throw CraftError.invalid("Invalid channel overlay color or opacity.") }
  }
  public func overlay(_ value: Float) -> Float { (indicates == .maskedAreas ? 1-value:value)*opacity }
  public func display(_ value: Float) -> Float { indicates == .maskedAreas ? value:1-value }
}
public struct AlphaChannel: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  /// Grayscale values are coverage, never color-managed. RGB components are redundant; alpha is opaque.
  public var pixels: Surface
  public var options: ChannelDisplayOptions
  public var spot: SpotInk?
  /// Source display record and persistent channel ID; inert unless a PSD writer uses them.
  public var psdDisplay: Data?
  public var psdIdentifier: UInt32?
  public var psdQuickMaskInitiallyEmpty: Bool?
  /// Original numeric Photoshop gray for exact unchanged Float32 spot round trips.
  /// Density inversion is not bijective over Float32; retain its source plane.
  public var psdSpotGray: Surface?
  public init(id: UUID = UUID(),name: String,pixels: Surface,options: ChannelDisplayOptions = .init(),spot: SpotInk? = nil) {
    self.id = id; self.name = name; self.pixels = pixels; self.options = options; self.spot = spot
  }
  public func validate(width: Int,height: Int,depth: PixelDepth) throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.utf8.count <= 1024,
      pixels.width == width, pixels.height == height, pixels.depth == depth, pixels.colorEncoding == .sRGB else { throw CraftError.invalid("Channel name, size, depth or sample encoding is invalid.") }
    try options.validate(); try spot?.validate()
    guard psdDisplay == nil || psdDisplay?.count == 13 else {throw CraftError.invalid("Invalid retained PSD channel display record.")}
    if let gray=psdSpotGray {
      guard spot != nil,depth == .f32,gray.width==width,gray.height==height,gray.depth==depth,gray.colorEncoding == .sRGB else {throw CraftError.invalid("Invalid retained spot gray plane.")}
      try gray.validated()
    }
  }
  /// A depth change quantizes numeric coverage and invalidates the old Float32
  /// source-gray domain. Same-depth edits retain the exact original plane.
  public func convertedCoverage(to depth:PixelDepth)throws->Self {
    guard depth != pixels.depth else{return self}
    var result=self;result.pixels=try pixels.converted(to:depth);result.psdSpotGray=nil;return result
  }
  public func selection(invert: Bool = false) throws -> SelectionMask {
    if pixels.width>Surface.maximumDensePixels/pixels.height {
      let source=try invert ? pixels.mappedStoredSamples {p in let v=1-unit(p.r);return Pixel(v,v,v)}:pixels
      return try SelectionMask(coverage:source)
    }
    var bytes = [UInt8](repeating:0,count:pixels.width*pixels.height)
    for y in 0..<pixels.height { try Task.checkCancellation(); for x in 0..<pixels.width {
      let v = unit(pixels.pixel(x:x,y:y).r); bytes[y*pixels.width+x] = UInt8(((invert ? 1-v:v)*255).rounded())
    } }
    return try SelectionMask(width:pixels.width,height:pixels.height,bytes:bytes)
  }
  public static func coverage(_ selection: SelectionMask?,width: Int,height: Int,depth: PixelDepth) throws -> Surface {
    if let selection { guard selection.width == width, selection.height == height else { throw CraftError.invalid("Selection/channel canvas sizes differ.") } }
    if let selection,selection.isPaged {
      let mapped=try selection.coverageSurface().mappedStoredSamples {p in Pixel(p.r,p.r,p.r).quantized(depth)}
      return try mapped.retaggedCoverageStorage(depth:depth)
    }
    var surface = try Surface(width:width,height:height,depth:depth,fill:selection == nil ? .white:.black)
    if let selection {
      for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
        let value = Float(selection.byte(at:y*width+x))/255
        if value > 0 { surface.setPixel(x:x,y:y,Pixel(value,value,value)) }
      } }
    }
    return surface
  }
}
public enum ChannelPlaneTarget: Codable, Equatable, Sendable {
  case alpha(UUID), quickMask
}
public enum ChannelCommand: Sendable {
  case create(AlphaChannel)
  case delete(UUID)
  case duplicate(UUID,String?)
  case rename(UUID,String)
  case move(UUID,Int)
  case options(ChannelPlaneTarget,ChannelDisplayOptions)
  case configure(UUID,String,ChannelDisplayOptions,SpotInk?)
  case saveSelection(UUID?,String?,SelectionMode)
  case storeSelection(Surface,UUID?,String?,SelectionMode)
  case load(ChannelPlaneTarget,SelectionMode,Bool)
  case quickMask(Bool,ChannelDisplayOptions)
  case stroke(ChannelPlaneTarget,[StrokePoint],Brush)
  case fill(ChannelPlaneTarget,Float,Float)
  case invert(ChannelPlaneTarget)
  case filter(ChannelPlaneTarget,RasterFilter)
  public var label: String {
    switch self {
    case .create: "New Channel"; case .delete: "Delete Channel"; case .duplicate: "Duplicate Channel"
    case .rename: "Rename Channel"; case .move: "Channel Order"; case .options, .configure: "Channel Options"
    case .saveSelection, .storeSelection: "Save Selection"; case .load: "Load Selection"
    case .quickMask(let on,_): on ? "Edit in Quick Mask":"Exit Quick Mask"
    case .stroke: "Brush on Channel"; case .fill: "Fill Channel"; case .invert: "Invert Channel"
    case .filter(_,let filter): filter.kind.title
    }
  }
}
extension CraftDocument {
  public static let maximumAlphaChannels = 52
  public var hasAuxiliaryChannels: Bool { !(alphaChannels ?? []).isEmpty || quickMask != nil }
  public func channel(_ target: ChannelPlaneTarget) throws -> AlphaChannel {
    let value: AlphaChannel?
    switch target { case .alpha(let id): value = alphaChannels?.first(where:{ $0.id == id }); case .quickMask: value = quickMask }
    guard let value else { throw CraftError.invalid("The channel no longer exists.") }; return value
  }
  public var suggestedChannelName: String {
    let names = Set((alphaChannels ?? []).map(\.name)); var number = 1
    while names.contains("Alpha \(number)") { number += 1 }; return "Alpha \(number)"
  }
  mutating func setChannel(_ value: AlphaChannel,at target: ChannelPlaneTarget) throws {
    try value.validate(width:width,height:height,depth:depth)
    switch target {
    case .alpha(let id):
      guard let i = alphaChannels?.firstIndex(where:{ $0.id == id }), value.id == id else { throw CraftError.invalid("The channel no longer exists.") }; alphaChannels?[i] = value
    case .quickMask:
      guard quickMask?.id == value.id else { throw CraftError.invalid("Quick Mask is no longer active.") }; quickMask = value
    }
  }
  mutating func transformChannels(from old: CraftDocument,by transform: Transform2D,method: Resampling = .nearest) throws {
    guard old.hasAuxiliaryChannels else { return }
    func mapped(_ value: AlphaChannel) throws -> AlphaChannel {
      var result = value
      result.pixels = try RasterGeometry.renderChannel(value.pixels,transform:transform,
        bounds:IntRect(x:0,y:0,width:width,height:height),method:method)
      if let gray=value.psdSpotGray {result.psdSpotGray=try RasterGeometry.renderChannel(gray,transform:transform,bounds:IntRect(x:0,y:0,width:width,height:height),method:method)}
      return result
    }
    alphaChannels = try old.alphaChannels?.map(mapped); quickMask = try old.quickMask.map(mapped)
  }
}
