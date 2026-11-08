import Foundation

public enum SelectionMode: String, CaseIterable, Codable, Sendable {
  case replace = "New"
  case add = "Add"
  case subtract = "Subtract"
  case intersect = "Intersect"
}
public struct SelectionPoint: Equatable, Sendable, Codable {
  public var x: Double
  public var y: Double
  public init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
}
public enum SelectionShape: Sendable, Codable {
  case rectangle(IntRect)
  case ellipse(IntRect)
  case polygon([SelectionPoint])
}

/// Canvas-space GRAY8 coverage, matching PhotoCraft's quantized selection semantics.
/// Bytes use value semantics and compact Data encoding rather than plist integer arrays.
private final class SelectionCoverageStorage:Equatable,Sendable {
  let dense:[UInt8]?
  let paged:PagedSelectionCoverage?
  init(dense:[UInt8]?,paged:PagedSelectionCoverage?) {self.dense=dense;self.paged=paged}
  static func ==(lhs:SelectionCoverageStorage,rhs:SelectionCoverageStorage)->Bool {
    lhs === rhs || (lhs.dense==rhs.dense && lhs.paged==rhs.paged)
  }
}

public struct SelectionMask: Equatable, Sendable, Codable {
  public let width: Int
  public let height: Int
  private let storage:SelectionCoverageStorage
  private var dense:[UInt8]? {storage.dense}
  private var paged:PagedSelectionCoverage? {storage.paged}
  public let bounds: IntRect?
  public var isPaged: Bool { paged != nil }
  public var pixelCount: Int { width*height }
  public var allocatedBytes: Int { dense?.count ?? paged!.allocatedBytes }
  public var mappedBytes: Int { paged?.mappedBytes ?? 0 }
  public var mappedIndexBytes: Int { paged?.surface.mappedTileIndexBytes ?? 0 }
  /// Checked compatibility view. Large consumers must sample or request a
  /// deliberately bounded extraction instead of allocating a logical plane.
  public var bytes: [UInt8] { get throws { try denseBytes() } }
  public func denseBytes(maximumPixels:Int = Surface.maximumDensePixels)throws->[UInt8] {
    guard maximumPixels>=0,width<=maximumPixels/height else {throw CraftError.unsupported("This operation requires bounded dense selection coverage.")}
    if let dense {return dense}
    return try paged!.denseBytes(maximumPixels:maximumPixels)
  }
  public init(width: Int, height: Int, bytes: [UInt8]) throws {
    _ = try Surface(width: width, height: height)
    guard bytes.count == width*height else {throw CraftError.invalid("Invalid selection coverage.")}
    if width > Surface.maximumDensePixels/height {
      try self.init(paged:PagedSelectionCoverage(width:width,height:height,bytes:bytes));return
    }
    self.init(rawWidth:width,height:height,dense:bytes,paged:nil,bounds:try Self.findBounds(bytes,width:width,height:height))
  }
  init(paged plane:PagedSelectionCoverage)throws {
    if plane.width<=Surface.maximumDensePixels/plane.height {
      try self.init(width:plane.width,height:plane.height,bytes:plane.denseBytes());return
    }
    self.init(rawWidth:plane.width,height:plane.height,dense:nil,paged:plane,bounds:try plane.bounds)
  }
  private init(rawWidth:Int,height:Int,dense:[UInt8]?,paged:PagedSelectionCoverage?,bounds:IntRect?) {
    width=rawWidth;self.height=height;storage=SelectionCoverageStorage(dense:dense,paged:paged);self.bounds=bounds
  }
  public init(coverage surface:Surface)throws {try self.init(paged:PagedSelectionCoverage(surface:surface))}
  /// Assemble quantized document-space coverage through bounded, deduplicated
  /// patches. Unlisted regions are zero; no logical full-canvas byte array is made.
  public static func sampledCoverage(width: Int, height: Int, regions: [IntRect],
    sample: (Int, Int) throws -> UInt8) throws -> Self {
    _ = try Surface(width: width, height: height); try Task.checkCancellation()
    guard regions.allSatisfy({ r in
      r.x >= 0 && r.y >= 0 && r.x <= width && r.y <= height && r.width >= 0 && r.height >= 0
        && r.width <= width - r.x && r.height <= height - r.y
    }) else { throw CraftError.invalid("Selection sampling regions must lie inside the canvas.") }
    return try Self(paged: PagedSelectionCoverage.assemble(width: width, height: height, regions: regions, sample: sample))
  }
  public func coverageSurface()throws->Surface {
    if let paged {return paged.surface}
    return try PagedSelectionCoverage(width:width,height:height,bytes:dense!).surface
  }
  public var isFullCoverage:Bool {get throws {
    if let dense {return dense.allSatisfy {$0==255}}
    return try paged!.surface.allStoredSamplesSatisfy {$0.r==1}
  }}
  enum CodingKeys: CodingKey { case width, height, bytes, historyBytes, pagedCoverage }
  public init(from decoder: Decoder) throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    let w=try c.decode(Int.self,forKey:.width),h=try c.decode(Int.self,forKey:.height)
    _ = try Surface(width:w,height:h)
    if c.contains(.pagedCoverage) {
      guard w>Surface.maximumDensePixels/h,!c.contains(.bytes),!c.contains(.historyBytes) else {throw CraftError.invalid("Invalid paged selection payload.")}
      let surface=try c.decode(Surface.self,forKey:.pagedCoverage)
      guard surface.width==w,surface.height==h,surface.depth == .u8,surface.colorEncoding == .sRGB,
        try surface.allStoredSamplesSatisfy({p in p.r>=0 && p.r<=1 && p.r==p.g && p.r==p.b && p.a==1 && (p.r*255).rounded()/255==p.r}) else {throw CraftError.invalid("Invalid GRAY8 selection storage.")}
      try self.init(paged:PagedSelectionCoverage(surface:surface));return
    }
    guard w<=Surface.maximumDensePixels/h else {throw CraftError.invalid("Large selections require paged coverage storage.")}
    let data:Data
    if c.contains(.historyBytes) {
      guard !c.contains(.bytes),let context=decoder.userInfo[.historyTileDecoder]as?(any RasterBlobDecoding) else {throw CraftError.invalid("Selection blob data requires its owned raster context.")}
      data=try context.bytes(c.decode(String.self,forKey:.historyBytes),maximumBytes:Surface.maximumDensePixels)
    } else {data=try c.decode(Data.self,forKey:.bytes)}
    try self.init(width:w,height:h,bytes:Array(data))
  }
  public func encode(to encoder: Encoder) throws {
    var c=encoder.container(keyedBy:CodingKeys.self)
    try c.encode(width,forKey:.width);try c.encode(height,forKey:.height)
    if let paged {
      guard encoder.userInfo[.historyTileEncoder]is(any RasterBlobEncoding) else {throw CraftError.unsupported("Paged selection encoding requires an owned tile context.")}
      try c.encode(paged.surface,forKey:.pagedCoverage)
    } else if let context=encoder.userInfo[.historyTileEncoder]as?(any RasterBlobEncoding) {
      try c.encode(context.storeBytes(Data(dense!)),forKey:.historyBytes)
    } else {try c.encode(Data(dense!),forKey:.bytes)}
  }
  @inline(__always) public func byte(at index:Int)->UInt8 {
    guard index>=0,index<pixelCount else {return 0}
    return dense?[index] ?? paged!.byte(x:index%width,y:index/width)
  }
  @inline(__always) public func coverage(x: Int, y: Int) -> Float {
    guard x>=0,y>=0,x<width,y<height else {return 0}
    return Float(byte(at:y*width+x))/255
  }
  private static func findBounds(_ bytes: [UInt8], width: Int, height: Int) throws -> IntRect? {
    var x0 = width
    var y0 = height
    var x1 = -1
    var y1 = -1
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width where bytes[y * width + x] != 0 {
        x0 = min(x0, x)
        x1 = max(x1, x)
        y0 = min(y0, y)
        y1 = y
      }
    }
    return x1 >= x0 ? IntRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1) : nil
  }
  public static func make(_ shape: SelectionShape, width: Int, height: Int, antiAlias: Bool = true)
    throws -> Self
  {
    _ = try Surface(width: width, height: height)
    if width > Surface.maximumDensePixels/height {return try Self(paged:PagedSelectionCoverage.make(shape,width:width,height:height,antiAlias:antiAlias))}
    var out = [UInt8](repeating: 0, count: width * height)
    let sub = antiAlias ? 4 : 1
    switch shape {
    case .rectangle(let r), .ellipse(let r):
      guard r.width > 0, r.height > 0, r.width <= Surface.maxDimension,
        r.height <= Surface.maxDimension,
        abs(Double(r.x)) <= 1_000_000, abs(Double(r.y)) <= 1_000_000
      else {
        throw CraftError.invalid("Invalid selection rectangle.")
      }
      let x0 = max(0, min(width, r.x))
      let y0 = max(0, min(height, r.y))
      let x1 = max(x0, min(width, r.x + r.width))
      let y1 = max(y0, min(height, r.y + r.height))
      let ellipse: Bool = {
        if case .ellipse = shape { return true }
        return false
      }()
      for y in y0..<y1 {
        try Task.checkCancellation()
        for x in x0..<x1 {
          if !ellipse {
            out[y * width + x] = 255
            continue
          }
          var count = 0
          for sy in 0..<sub {
            for sx in 0..<sub {
              let dx =
                (Double(x - r.x) + (Double(sx) + 0.5) / Double(sub)) / Double(r.width) * 2 - 1
              let dy =
                (Double(y - r.y) + (Double(sy) + 0.5) / Double(sub)) / Double(r.height) * 2 - 1
              if dx * dx + dy * dy <= 1 { count += 1 }
            }
          }
          out[y * width + x] = UInt8((Double(count) / Double(sub * sub) * 255).rounded())
        }
      }
    case .polygon(let points):
      guard points.count <= 100_000,
        points.allSatisfy({
          $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000
        })
      else {
        throw CraftError.invalid("Invalid lasso path.")
      }
      if points.count >= 3 {
        // PhotoCraft algo/selection.rs polygon: even-odd spans with exact horizontal
        // coverage and four sub-rows. Scan only rows intersecting the path.
        let y0 = max(0, min(height, Int(floor(points.map(\.y).min()!))))
        let y1 = max(y0, min(height, Int(ceil(points.map(\.y).max()!))))
        for py in y0..<y1 {
          try Task.checkCancellation()
          var row = [Double](repeating: 0, count: width)
          for sample in 0..<sub {
            let y = Double(py) + (Double(sample) + 0.5) / Double(sub)
            var crossings: [Double] = []
            for i in points.indices {
              let a = points[i]
              let b = points[(i + 1) % points.count]
              if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
              }
            }
            crossings.sort()
            for i in stride(from: 0, to: crossings.count - crossings.count % 2, by: 2) {
              let lo = max(0, crossings[i])
              let hi = min(Double(width), crossings[i + 1])
              guard hi > lo else { continue }
              for x in Int(floor(lo))..<Int(ceil(hi)) {
                let cov =
                  antiAlias
                  ? min(Double(x + 1), hi) - max(Double(x), lo)
                  : (Double(x) + 0.5 >= lo && Double(x) + 0.5 < hi ? 1.0 : 0.0)
                row[x] += max(0, cov) / Double(sub)
              }
            }
          }
          for x in 0..<width { out[py * width + x] = UInt8((min(1, row[x]) * 255).rounded()) }
        }
      }
    }
    return try Self(width: width, height: height, bytes: out)
  }
  public func combined(with old: Self?, mode: SelectionMode) throws -> Self {
    guard old == nil || (old?.width == width && old?.height == height) else {
      throw CraftError.invalid("Selection canvas sizes differ.")
    }
    if mode == .replace { try Task.checkCancellation(); return self }
    if let paged {return try Self(paged:paged.combined(with:old?.paged,mode:mode))}
    var out = dense!
    for i in out.indices {
      if i % width == 0 { try Task.checkCancellation() }
      let a = old?.byte(at:i) ?? 0
      let b = dense![i]
      switch mode {
      case .replace: break
      case .add: out[i] = max(a, b)
      case .subtract: out[i] = a > b ? a - b : 0
      case .intersect: out[i] = min(a, b)
      }
    }
    return try Self(width: width, height: height, bytes: out)
  }
  public func inverted() throws -> Self {
    if let paged {return try Self(paged:paged.inverted())}
    return try Self(width:width,height:height,bytes:dense!.map {255-$0})
  }
  /// Same Gaussian definition as the source: sigma = radius / 2, truncated at 3 sigma,
  /// with zero coverage outside the canvas. Radius is currently capped for the CPU path.
  public func feathered(radius: Double) throws -> Self {
    guard radius.isFinite, (0...100).contains(radius) else {
      throw CraftError.invalid("Feather must be 0–100 pixels.")
    }
    if let paged {return try Self(paged:paged.feathered(radius:radius))}
    guard radius > 0, let box = bounds else { return self }
    let sigma = max(0.05, radius / 2)
    let r = Int(ceil(sigma * 3))
    var weights = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let sum = weights.reduce(0, +)
    weights = weights.map { $0 / sum }
    let x0 = max(0, box.x - r)
    let x1 = min(width, box.x + box.width + r)
    let y0 = max(0, box.y - r)
    let y1 = min(height, box.y + box.height + r)
    var horizontal = [Float](repeating: 0, count: width * height)
    for y in box.y..<box.y + box.height {
      try Task.checkCancellation()
      for x in x0..<x1 {
        var value = 0.0
        for k in -r...r where x + k >= 0 && x + k < width {
          value += Double(dense![y * width + x + k]) * weights[k + r]
        }
        horizontal[y * width + x] = Float(value)
      }
    }
    var out = [UInt8](repeating: 0, count: dense!.count)
    for y in y0..<y1 {
      try Task.checkCancellation()
      for x in x0..<x1 {
        var value = 0.0
        for k in -r...r where y + k >= 0 && y + k < height {
          value += Double(horizontal[(y + k) * width + x]) * weights[k + r]
        }
        out[y * width + x] = UInt8(min(255, max(0, value.rounded())))
      }
    }
    return try Self(width: width, height: height, bytes: out)
  }
  public func transformed(by delta: Transform2D, width: Int, height: Int) throws -> Self {
    _ = try Surface(width: width, height: height)
    if paged != nil || width > Surface.maximumDensePixels/height {
      let source=try paged ?? PagedSelectionCoverage(width:self.width,height:self.height,bytes:dense!)
      return try Self(paged:source.transformed(by:delta,width:width,height:height))
    }
    let inverse = try delta.inverted()
    var out = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let p = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
        let px = p.x - 0.5
        let py = p.y - 0.5
        guard px > -2, py > -2, px < Double(self.width), py < Double(self.height) else { continue }
        let ix = Int(floor(px))
        let iy = Int(floor(py))
        let fx = Float(px - floor(px))
        let fy = Float(py - floor(py))
        let top = coverage(x: ix, y: iy) * (1 - fx) + coverage(x: ix + 1, y: iy) * fx
        let bottom = coverage(x: ix, y: iy + 1) * (1 - fx) + coverage(x: ix + 1, y: iy + 1) * fx
        out[y * width + x] = UInt8((unit(top * (1 - fy) + bottom * fy) * 255).rounded())
      }
    }
    return try Self(width: width, height: height, bytes: out)
  }
}

extension CraftDocument {
  public func selectionCoverage(x: Int, y: Int) -> Float {
    if let selectionMask { return selectionMask.coverage(x: x, y: y) }
    return selection.map { $0.contains(x, y) ? 1 : 0 } ?? 1
  }
  public func coverageSelection() throws -> SelectionMask? {
    if let selectionMask { return selectionMask }
    guard let selection else { return nil }
    return try .make(.rectangle(selection), width: width, height: height, antiAlias: false)
  }
  public mutating func setCoverageSelection(_ mask: SelectionMask?) {
    selection = mask?.bounds
    selectionMask = selection == nil ? nil : mask
  }
  public mutating func mapSelection(from old: CraftDocument, by delta: Transform2D) throws {
    if let mask = old.selectionMask {
      setCoverageSelection(try mask.transformed(by: delta, width: width, height: height))
    } else {
      selection = try DocumentGeometry.mapSelection(
        old.selection, by: delta, width: width, height: height)
      selectionMask = nil
    }
  }
}

extension Pixel {
  /// Interpolate edits in premultiplied space so feathered clear/fill edges have no color halo.
  public func mixing(_ edited: Pixel, coverage: Float) -> Pixel {
    let t = unit(coverage)
    if t == 0 { return self }
    if t == 1 { return edited }
    let alpha = a * (1 - t) + edited.a * t
    guard alpha > 0 else { return .clear }
    return Pixel(
      (r * a * (1 - t) + edited.r * edited.a * t) / alpha,
      (g * a * (1 - t) + edited.g * edited.a * t) / alpha,
      (b * a * (1 - t) + edited.b * edited.a * t) / alpha, alpha)
  }
}
