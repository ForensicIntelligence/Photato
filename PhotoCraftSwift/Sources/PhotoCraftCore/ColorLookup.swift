import Foundation

public struct ColorLUTCurve: Codable, Equatable, Sendable {
  public var values: [Float]
  public var minimum: [Float]
  public var maximum: [Float]
  public init(values: [Float], minimum: [Float] = [0,0,0], maximum: [Float] = [1,1,1]) {
    self.values = values; self.minimum = minimum; self.maximum = maximum
  }
  public func validate() throws {
    try ColorLUT.validateDomain(minimum,maximum)
    guard values.count % 3 == 0, (2...65536).contains(values.count/3), values.allSatisfy({ $0.isFinite && abs($0) <= 65504 }) else { throw CraftError.invalid("Invalid 1D LUT curve.") }
  }
  func sample(_ input: SIMD3<Float>) -> SIMD3<Float> {
    let n = values.count/3; var output = SIMD3<Float>.zero
    for c in 0..<3 {
      let x = min(1,max(0,(input[c]-minimum[c])/(maximum[c]-minimum[c]))) * Float(n-1)
      let i = min(n-2,Int(x)), t = x-Float(i)
      output[c] = values[i*3+c] + (values[(i+1)*3+c]-values[i*3+c])*t
    }
    return output
  }
}
/// RGB triplets, red index varying fastest. Values and domains survive native saves.
/// Adapted from PhotoCraft cms/lutfile.rs and compose/adjust.rs (MIT OR Apache-2.0).
public struct ColorLUT: Codable, Equatable, Sendable {
  public var title: String
  public var size: Int
  public var values: [Float]
  public var domainMin: [Float]
  public var domainMax: [Float]
  /// Normalized, strictly increasing 3DL input knot coordinates; nil is uniform.
  public var inputGrid: [Float]?
  public var curve: ColorLUTCurve?
  public var sourceFile: String?
  public var sourceData: Data?
  public static let maximumSize = 129
  public static let maximumFileBytes = 64 * 1024 * 1024
  public var estimatedBytes: Int { values.count*4 + (curve?.values.count ?? 0)*4 + (inputGrid?.count ?? 0)*4 + title.utf8.count + (sourceData?.count ?? 0) }
  public init(title: String = "", size: Int, values: [Float], domainMin: [Float] = [0,0,0], domainMax: [Float] = [1,1,1], inputGrid: [Float]? = nil, curve: ColorLUTCurve? = nil) {
    self.title = title; self.size = size; self.values = values; self.domainMin = domainMin; self.domainMax = domainMax; self.inputGrid = inputGrid; self.curve = curve
  }
  static func validateDomain(_ low: [Float], _ high: [Float]) throws {
    guard low.count == 3, high.count == 3, zip(low,high).allSatisfy({ $0.isFinite && $1.isFinite && abs($0) <= 65504 && abs($1) <= 65504 && $1-$0 >= 1e-8 }) else { throw CraftError.invalid("LUT input domains must be finite and increasing.") }
  }
  public func validate() throws {
    try Self.validateDomain(domainMin,domainMax); try curve?.validate()
    guard (sourceData?.count ?? 0) <= Self.maximumFileBytes, (sourceData == nil) == (sourceFile == nil), (sourceFile?.utf8.count ?? 0) <= 1024 else { throw CraftError.invalid("Invalid retained LUT source.") }
    guard (2...Self.maximumSize).contains(size), values.count == size*size*size*3,
      title.utf8.count <= 1024, !title.unicodeScalars.contains(where: { $0.value < 32 }),
      values.allSatisfy({ $0.isFinite && abs($0) <= 65504 }) else { throw CraftError.invalid("Invalid 3D LUT size, title or values.") }
    if let name = sourceFile {
      guard URL(fileURLWithPath:name).lastPathComponent == name, !name.unicodeScalars.contains(where: { $0.value < 32 }) else { throw CraftError.invalid("Invalid LUT source filename.") }
    }
    if let grid = inputGrid {
      guard grid.count == size, grid.first == 0, grid.last == 1,
        zip(grid,grid.dropFirst()).allSatisfy({ $0.isFinite && $1 > $0 }) else { throw CraftError.invalid("Invalid LUT input grid.") }
    }
  }
  public static func generated(title: String, size: Int, transform: (SIMD3<Float>) -> SIMD3<Float>) throws -> Self {
    guard (2...maximumSize).contains(size) else { throw CraftError.invalid("Unsupported LUT size.") }
    var values = [Float](); values.reserveCapacity(size*size*size*3)
    for b in 0..<size {
      try Task.checkCancellation()
      for g in 0..<size { for r in 0..<size {
        let p = transform(SIMD3(Float(r),Float(g),Float(b))/Float(size-1)); values += [p.x,p.y,p.z]
      } }
    }
    let result = Self(title:title,size:size,values:values); try result.validate(); return result
  }
  public static func identity(size: Int = 2) throws -> Self { try generated(title:"Identity",size:size) { $0 } }
  public enum Interpolation: String, Codable, CaseIterable, Sendable { case trilinear, tetrahedral }
  /// Requires validated data. Transfers validate once before entering a pixel loop.
  func sample(_ input: SIMD3<Float>, interpolation: Interpolation) -> SIMD3<Float> {
    let input = curve?.sample(input) ?? input
    var low = SIMD3<Int>.zero, f = SIMD3<Float>.zero
    for c in 0..<3 {
      let n = min(1,max(0,(input[c]-domainMin[c])/(domainMax[c]-domainMin[c])))
      if let grid = inputGrid {
        var a = 0, b = size-1
        while b-a > 1 { let mid = (a+b)/2; if n >= grid[mid] { a = mid } else { b = mid } }
        low[c] = min(size-2,a); f[c] = (n-grid[a])/(grid[b]-grid[a])
      } else { let p = n*Float(size-1); low[c] = min(size-2,Int(p)); f[c] = p-Float(low[c]) }
    }
    func at(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
      let i = (((low.z+b)*size+low.y+g)*size+low.x+r)*3
      return SIMD3(values[i],values[i+1],values[i+2])
    }
    if interpolation == .tetrahedral {
      let order = [0,1,2].sorted { f[$0] > f[$1] }
      var one = SIMD3<Int>.zero; one[order[0]] = 1
      var two = one; two[order[1]] = 1
      return at(0,0,0)*(1-f[order[0]]) + at(one.x,one.y,one.z)*(f[order[0]]-f[order[1]]) + at(two.x,two.y,two.z)*(f[order[1]]-f[order[2]]) + at(1,1,1)*f[order[2]]
    }
    func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a+(b-a)*t }
    return mix(mix(mix(at(0,0,0),at(1,0,0),f.x),mix(at(0,1,0),at(1,1,0),f.x),f.y),mix(mix(at(0,0,1),at(1,0,1),f.x),mix(at(0,1,1),at(1,1,1),f.x),f.y),f.z)
  }
}
public struct ColorLookupAdjustment: Codable, Equatable, Sendable {
  public var lut: ColorLUT?
  public var interpolation: ColorLUT.Interpolation
  public var dither: Bool
  public init(lut: ColorLUT? = nil, interpolation: ColorLUT.Interpolation = .trilinear, dither: Bool = true) { self.lut = lut; self.interpolation = interpolation; self.dither = dither }
  public func validate() throws { try lut?.validate() }
  public func layer(in document: CraftDocument, name: String = "Color Lookup") throws -> Layer {
    try validate(); var layer = Layer(name:name,content:.adjustment(.colorLookup(self)))
    var mask = try Surface(width:document.width,height:document.height,depth:document.depth,fill:.white)
    if document.selection != nil { mask.mapPixels { x,y,_ in let c = document.selectionCoverage(x:x,y:y); return Pixel(c,c,c) } }
    layer.mask = mask; return layer
  }
}
public struct ColorLookupTransfer: Sendable {
  let value: ColorLookupAdjustment
  let depth: PixelDepth
  public init(_ value: ColorLookupAdjustment, depth: PixelDepth) throws { try value.validate(); self.value = value; self.depth = depth }
  public func apply(_ pixel: Pixel, x: Int = 0, y: Int = 0) -> Pixel {
    guard let lut = value.lut, pixel.a > 0, pixel.isFinite else { return pixel }
    let input = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    guard input.isFinite else { return Pixel(.nan,.nan,.nan,pixel.a) }
    var rgb = lut.sample(input.rgb,interpolation:value.interpolation)
    if value.dither {
      let bayer: [Float] = [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5]
      // Source ordered dither; Photoshop stochastic noise is independently unqualified.
      let n = ((bayer[(y&3)*4+(x&3)]+0.5)/16-0.5)/255
      for c in 0..<3 { rgb[c] = min(1,max(0,rgb[c]+n)) }
    }
    let result = Pixel(rgb.x,rgb.y,rgb.z,pixel.a)
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
}
