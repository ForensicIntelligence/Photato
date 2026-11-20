import Foundation
import PhotoCraftCore

/// A small merged-composite band, rendered in bounded regions. Channel-major
/// output revisits bands instead of retaining a complete merged raster.
final class PSDCompositeRows {
  static let preferredBandPixels = 131_072
  private let document:CraftDocument
  private let transparency:Bool
  private var firstRow = -1,height = 0
  private var pixels:[Pixel] = []
  private var prepared:CraftDocument?
  private var video:VideoTransitionRenderContext?
  private var facts:CompositionFacts?
  init(_ document:CraftDocument,transparency:Bool=true) {self.document=document;self.transparency=transparency}
  private func prepare() throws {
    if prepared == nil {
      try document.validate()
      let (snapshot,transitions) = try Renderer.preparedSources(document)
      prepared=snapshot;video=transitions
      if snapshot.width>Surface.maximumDensePixels/snapshot.height {facts=CompositionFacts(snapshot)}
    }
  }
  func sparseRows() throws -> PSDStoredRows? {
    guard document.colorMode == .rgb, document.inkMode == nil, document.restrictedMode == nil,
      document.width > Surface.maximumDensePixels / document.height else { return nil }
    try prepare()
    guard let prepared, let facts, video == nil,
      let result = try PagedCanvasRenderer.sparseExportComposite(prepared, facts: facts)
    else { return nil }
    return PSDStoredRows(result, kind: .merged(transparency: transparency))
  }
  private func render(_ region:IntRect) throws -> Surface {
    // Non-RGB composition keeps its separate native mode/ink path.
    guard document.colorMode == .rgb,document.inkMode == nil,document.restrictedMode == nil else {
      return try Renderer.composite(document,region:region)
    }
    try prepare()
    return try Renderer.compositePrepared(prepared!,region:region,video:video,facts:facts)
  }
  func row(_ y:Int,channel:Int,depth:Int) throws -> [UInt8] {
    guard (0..<document.height).contains(y),(0..<4).contains(channel) else {throw CraftError.invalid("Invalid Photoshop composite row.")}
    if y < firstRow || y >= firstRow+height {
      firstRow=y;height=min(document.height-y,max(1,min(64,Self.preferredBandPixels/document.width)))
      pixels=Array(repeating:.clear,count:document.width*height)
      for x in stride(from:0,to:document.width,by:2048) {
        try Task.checkCancellation()
        let width=min(2048,document.width-x)
        let rendered=try render(IntRect(x:x,y:y,width:width,height:height))
        for py in 0..<height {for px in 0..<width {
          pixels[py*document.width+x+px] = depth == 32
            ? PSDMergedSample.encodeLinear(rendered.linearPixel(x:x+px,y:y+py),transparency:transparency)
            : PSDMergedSample.encode(rendered.pixel(x:x+px,y:y+py),depth:depth)
        }}
      }
    }
    var bytes:[UInt8]=[];bytes.reserveCapacity(document.width*(depth/8))
    for x in 0..<document.width {
      let p=pixels[(y-firstRow)*document.width+x]
      let value:Float
      switch channel {case 0:value=p.r;case 1:value=p.g;case 2:value=p.b;default:value=p.a}
      try PSDChannelCodec.append(value,depth:depth,to:&bytes)
    }
    return bytes
  }
}

/// For sparse layer and merged planes, rows outside stored tile bands are
/// identical. Within a band only the stored columns can differ from the default.
struct PSDStoredRows {
  /// The accelerated path retains at most this many Float32 sample bytes in
  /// the merged scratch raster. The export can stream wider coverage in bands.
  static let retainedSampleBytes = PSDChannelCodec.byteLimit
  static let retainedTileCount = retainedSampleBytes / (Surface.tileSide * Surface.tileSide * MemoryLayout<Pixel>.stride)

  enum Kind {
    case layer, filterSource, mask, merged(transparency: Bool)
    case auxiliary(inverted: Bool, original: Surface?)

    var usesLinearSamples: Bool {
      switch self {
      case .layer, .filterSource, .merged: return true
      case .mask, .auxiliary: return false
      }
    }
  }

  private let surface: Surface
  private let kind: Kind
  private let columnsByBand: [[Int]]
  private let emptyBandEnds: [Int]

  init?(_ surface: Surface, kind: Kind, minimumPixels: Int = Surface.maximumDensePixels) {
    guard surface.width > minimumPixels / surface.height,
      surface.tileCount <= Self.retainedTileCount else { return nil }
    let original: Surface?
    if case .auxiliary(_, let gray) = kind { original = gray }
    else { original = nil }
    guard (original?.tileCount ?? 0) <= Self.retainedTileCount - surface.tileCount else { return nil }
    self.surface = surface
    self.kind = kind
    let side = Surface.tileSide
    let columns = (surface.width + side - 1) / side
    var bands = [[Int]](repeating: [], count: (surface.height + side - 1) / side)
    for key in surface.storedTileKeys { bands[key / columns].append(key % columns) }
    if let original {
      // Original Float32 words can differ even where their inverted coverage rounds
      // to the implicit value, so rows must include both tile grids.
      for key in original.storedTileKeys { bands[key / columns].append(key % columns) }
      for band in bands.indices where !bands[band].isEmpty {
        bands[band] = Set(bands[band]).sorted()
      }
    }
    columnsByBand = bands
    var end = surface.height
    var ends = [Int](repeating: end, count: bands.count)
    for band in bands.indices.reversed() {
      ends[band] = end
      if !bands[band].isEmpty { end = band * side }
    }
    emptyBandEnds = ends
  }

  func repeatedRows(from y: Int) -> Int {
    let band = y / Surface.tileSide
    return columnsByBand[band].isEmpty ? emptyBandEnds[band] - y : 1
  }

  func row(_ y: Int, channel: Int, depth: Int) throws -> [UInt8] {
    let side = Surface.tileSide, sampleBytes = depth / 8
    let linear = depth == 32 && kind.usesLinearSamples
    func sample(_ pixel: Pixel, x: Int? = nil) -> Float {
      let stored: Pixel
      switch kind {
      case .mask: return unit(pixel.r)
      case .auxiliary(let inverted, let original):
        return PSDAuxiliaryChannels.sample(pixel.r, inverted: inverted, depth: depth,
          original: original.map { gray in
            guard let x else { return gray.defaultPixel.r }
            return gray.pixel(x: x, y: y).r
          })
      case .layer: stored = pixel
      case .filterSource:
        if channel != 3, pixel.a == 0 { return 1 }
        stored = pixel
      case .merged(let transparency):
        stored = linear ? PSDMergedSample.encodeLinear(pixel, transparency: transparency)
          : PSDMergedSample.encode(pixel, depth: depth)
      }
      switch channel { case 0: return stored.r; case 1: return stored.g; case 2: return stored.b; default: return stored.a }
    }
    var pattern: [UInt8] = []
    try PSDChannelCodec.append(sample(linear ? surface.linearDefaultPixel : surface.defaultPixel), depth: depth, to: &pattern)
    var bytes = Array(PSDChannelWriter.repeating(Data(pattern), count: surface.width))
    var patch: [UInt8] = []
    patch.reserveCapacity(side * sampleBytes)
    for column in columnsByBand[y / side] {
      try Task.checkCancellation()
      let start = column * side, end = min(surface.width, start + side)
      patch.removeAll(keepingCapacity: true)
      for x in start..<end {
        let p = linear ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
        try PSDChannelCodec.append(sample(p, x: x), depth: depth, to: &patch)
      }
      bytes.replaceSubrange((start * sampleBytes)..<(end * sampleBytes), with: patch)
    }
    return bytes
  }
}
