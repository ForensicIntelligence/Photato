import Foundation

/// Native port of PhotoCraft compose/src/adjust.rs (MIT OR Apache-2.0).
/// These bounded RGB approximations do not establish Photoshop pixel equality.
public struct ClassicAdjustment: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case vibrance, blackWhite, photoFilter, channelMixer, selectiveColor
    public var title: String {
      switch self {
      case .vibrance: "Vibrance"
      case .blackWhite: "Black & White"
      case .photoFilter: "Photo Filter"
      case .channelMixer: "Channel Mixer"
      case .selectiveColor: "Selective Color"
      }
    }
    public var parameters: Set<String> {
      switch self {
      case .vibrance: ["vibrance", "saturation"]
      case .blackWhite: ["weights", "tint"]
      case .photoFilter: ["color", "density", "preserveLuminosity"]
      case .channelMixer: ["matrix", "monochrome"]
      case .selectiveColor: ["adjustments", "relative"]
      }
    }
  }
  public var kind: Kind
  public var vibrance = 0
  public var saturation = 0
  public var weights = [40, 60, 40, 60, 20, 80]
  public var tint: Pixel?
  public var color = Pixel(0.9255, 0.5412, 0)
  public var density = 25
  public var preserveLuminosity = true
  /// Rows are Red, Green, Blue output; columns are RGB source and Constant, percent.
  public var matrix = [[100, 0, 0, 0], [0, 100, 0, 0], [0, 0, 100, 0]]
  public var monochrome = false
  public var relative = true
  /// Reds, Yellows, Greens, Cyans, Blues, Magentas, Whites, Neutrals, Blacks; CMYK percent.
  public var adjustments = Array(repeating: [0, 0, 0, 0], count: 9)
  public init(_ kind: Kind) { self.kind = kind }
  public static let rangeNames = ["Reds", "Yellows", "Greens", "Cyans", "Blues", "Magentas", "Whites", "Neutrals", "Blacks"]
  public static let defaultTint = Pixel(225.0 / 255, 211.0 / 255, 179.0 / 255)
  public func validate() throws {
    func validColor(_ p: Pixel) -> Bool { p.isFinite && p.a == 1 && [p.r,p.g,p.b].allSatisfy { (0...1).contains($0) } }
    guard (-100...100).contains(vibrance), (-100...100).contains(saturation),
      weights.count == 6, weights.allSatisfy({ (-200...300).contains($0) }),
      validColor(color), tint.map(validColor) != false, (0...100).contains(density),
      matrix.count == 3, matrix.allSatisfy({ $0.count == 4 && $0.allSatisfy { (-200...200).contains($0) } }),
      adjustments.count == 9, adjustments.allSatisfy({ $0.count == 4 && $0.allSatisfy { (-100...100).contains($0) } })
    else { throw CraftError.invalid("Invalid classic adjustment values, color or channel array dimensions.") }
  }
  public var isIdentity: Bool {
    switch kind {
    case .vibrance: vibrance == 0 && saturation == 0
    case .blackWhite: false
    case .photoFilter: density == 0
    case .channelMixer: !monochrome && matrix == [[100,0,0,0], [0,100,0,0], [0,0,100,0]]
    case .selectiveColor: adjustments.allSatisfy { $0.allSatisfy { $0 == 0 } }
    }
  }
  /// Build the same selection-derived mask for desktop and API creation.
  public func layer(in document: CraftDocument, name: String? = nil) throws -> Layer {
    try validate()
    var layer = Layer(name: name ?? kind.title, content: .adjustment(.classic(self)))
    var mask = try Surface(width: document.width, height: document.height, depth: document.depth, fill: .white)
    if document.selection != nil { mask.mapPixels { x,y,_ in let v = document.selectionCoverage(x:x,y:y); return Pixel(v,v,v) } }
    layer.mask = mask
    return layer
  }
}

public struct ClassicAdjustmentTransfer: Sendable {
  let value: ClassicAdjustment
  let depth: PixelDepth
  let valid: Bool
  public init(_ value: ClassicAdjustment, depth: PixelDepth) {
    self.value = value; self.depth = depth; valid = (try? value.validate()) != nil
  }
  public func apply(_ pixel: Pixel) -> Pixel {
    guard valid, !value.isIdentity, pixel.a > 0, pixel.isFinite else { return pixel }
    // Renderer/Command pass document tone-space coordinates. RGB32 has already
    // been encoded by that bridge, matching the existing Color Balance transfer.
    let input = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    func clamp(_ v: Float) -> Float { min(1,max(0,v)) }
    let c = SIMD3(clamp(input.r), clamp(input.g), clamp(input.b))
    func luma(_ v: SIMD3<Float>) -> Float { 0.299 * v.x + 0.587 * v.y + 0.114 * v.z }
    var out = c
    switch value.kind {
    case .vibrance:
      let hsl = HSLColor.components(c)
      // Greys have no hue: keep them neutral rather than inventing red.
      if hsl.y > 0 {
        let boost = Float(value.vibrance) / 100 * (1 - hsl.y)
        let s = clamp(hsl.y * (1 + Float(value.saturation) / 100) + boost * max(hsl.y, 0.1))
        out = HSLColor.rgb(hue:hsl.x, saturation:s, lightness:hsl.z)
      }
    case .blackWhite:
      let hi = max(c.x,max(c.y,c.z)), lo = min(c.x,min(c.y,c.z))
      let mid = c.x + c.y + c.z - hi - lo
      let primary = c.x >= c.y && c.x >= c.z ? 0 : c.y >= c.z ? 2 : 4
      let secondary = c.z <= c.x && c.z <= c.y ? 1 : c.x <= c.y ? 3 : 5
      let gray = clamp(lo + (mid-lo) * Float(value.weights[secondary])/100 + (hi-mid) * Float(value.weights[primary])/100)
      out = SIMD3(repeating:gray)
      if let tint = value.tint { for i in 0..<3 { out[i] = clamp(gray * tint.rgb[i] * 2) * 0.5 + gray * 0.5 } }
    case .photoFilter:
      let density = Float(value.density)/100
      out = c * (SIMD3(repeating:1-density) + value.color.rgb * density)
      if value.preserveLuminosity { out *= luma(c)/max(luma(out),1e-6) }
    case .channelMixer:
      for i in 0..<3 {
        let row = value.matrix[value.monochrome ? 0 : i]
        out[i] = (Float(row[0])*c.x + Float(row[1])*c.y + Float(row[2])*c.z + Float(row[3]))/100
      }
    case .selectiveColor:
      let hi = max(c.x,max(c.y,c.z)), lo = min(c.x,min(c.y,c.z)), mid = c.x+c.y+c.z-max(c.x,max(c.y,c.z))-min(c.x,min(c.y,c.z))
      func top(_ i: Int) -> Float { c[i] >= hi ? hi-mid : 0 }
      func bottom(_ i: Int) -> Float { c[i] <= lo ? mid-lo : 0 }
      let w = [top(0),bottom(2),top(1),bottom(0),top(2),bottom(1),max(0,(lo-0.5)*2),clamp(1-abs(hi-0.5)-abs(lo-0.5)),max(0,(0.5-hi)*2)]
      for r in 0..<9 where w[r] > 0 {
        for i in 0..<3 { out[i] -= Float(value.adjustments[r][i]+value.adjustments[r][3])/100 * (value.relative ? 1-c[i] : 1) * w[r] }
      }
    }
    let result = Pixel(clamp(out.x),clamp(out.y),clamp(out.z),pixel.a)
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
}
