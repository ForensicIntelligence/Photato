import Foundation

public struct PaletteColor: Codable, Equatable, Hashable, Sendable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8
  public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
    self.red = red; self.green = green; self.blue = blue
  }
  public var pixel: Pixel { Pixel(Float(red) / 255, Float(green) / 255, Float(blue) / 255) }
  var vector: SIMD3<Float> { SIMD3(Float(red), Float(green), Float(blue)) }
  var key: UInt32 { UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue) }
  init(_ p: SIMD4<Float>) {
    self.init(UInt8((unit(p.x) * 255).rounded()), UInt8((unit(p.y) * 255).rounded()), UInt8((unit(p.z) * 255).rounded()))
  }
  init(vector: SIMD3<Float>) {
    self.init(UInt8(min(255, max(0, vector.x.rounded()))), UInt8(min(255, max(0, vector.y.rounded()))), UInt8(min(255, max(0, vector.z.rounded()))))
  }
}

public enum IndexedPaletteKind: String, Codable, CaseIterable, Sendable {
  case exact, systemMac, systemWindows, web, uniform
  case localPerceptual, localSelective, localAdaptive
  case masterPerceptual, masterSelective, masterAdaptive, custom, previous
  var local: Self {
    switch self {
    case .masterPerceptual: .localPerceptual
    case .masterSelective: .localSelective
    case .masterAdaptive: .localAdaptive
    default: self
    }
  }
  var isMaster: Bool { self != local }
}

public enum IndexedDither: String, Codable, CaseIterable, Sendable {
  case none, diffusion, pattern, noise
}

public enum IndexedForcedColors: String, Codable, CaseIterable, Sendable {
  case none, blackWhite, primaries, web, custom
  func colors(_ custom: [PaletteColor]) -> [PaletteColor] {
    switch self {
    case .none: []
    case .blackWhite: [.init(0, 0, 0), .init(255, 255, 255)]
    case .primaries: [.init(0, 0, 0), .init(255, 255, 255), .init(255, 0, 0), .init(0, 255, 0), .init(0, 0, 255), .init(0, 255, 255), .init(255, 0, 255), .init(255, 255, 0)]
    case .web: PaletteQuantization.webPalette
    case .custom: custom
    }
  }
}

/// Native translation of licensed PhotoCraft quantize.rs. Source parity does not
/// establish Adobe palette/dither equivalence. Index storage and exact-color
/// preservation are native extensions; a transparent index is excluded from
/// opaque matching, unlike the original RGB-cache-only implementation.
public enum PaletteQuantization {
  public typealias Sample = SIMD4<Float>
  public static let maximumPixels = NativeModeRaster.maximumPixels
  public static var webPalette: [PaletteColor] {
    var result = [PaletteColor]()
    for r in 0..<6 { for g in 0..<6 { for b in 0..<6 {
      result.append(.init(UInt8(r * 51), UInt8(g * 51), UInt8(b * 51)))
    } } }; return result
  }
  public static var macPalette: [PaletteColor] {
    var result = webPalette
    let steps = (1...15).map { UInt8($0 * 17) }.filter { $0 % 51 != 0 }.reversed()
    result += steps.map { .init($0, 0, 0) }; result += steps.map { .init(0, $0, 0) }
    result += steps.map { .init(0, 0, $0) }; result += steps.map { .init($0, $0, $0) }
    return result
  }
  public static var windowsPalette: [PaletteColor] {
    var result: [PaletteColor] = [
      .init(0, 0, 0), .init(128, 0, 0), .init(0, 128, 0), .init(128, 128, 0),
      .init(0, 0, 128), .init(128, 0, 128), .init(0, 128, 128), .init(192, 192, 192),
      .init(192, 220, 192), .init(166, 202, 240), .init(255, 251, 240), .init(160, 160, 164),
      .init(128, 128, 128), .init(255, 0, 0), .init(0, 255, 0), .init(255, 255, 0),
      .init(0, 0, 255), .init(255, 0, 255), .init(0, 255, 255), .init(255, 255, 255)
    ]
    for color in webPalette where !result.contains(color) { result.append(color) }
    var gray: UInt8 = 8
    while result.count < 256 {
      let color = PaletteColor(gray, gray, gray)
      if !result.contains(color) { result.append(color) }; gray &+= 12
    }; return result
  }
  public static func uniformPalette(colors: Int) -> [PaletteColor] {
    let count = min(256, max(2, colors)), k = max(2, Int(cbrt(Float(count)).rounded(.down)))
    func level(_ i: Int) -> UInt8 { UInt8((Float(i) / Float(k - 1) * 255).rounded()) }
    var result = [PaletteColor]()
    for r in 0..<k { for g in 0..<k { for b in 0..<k { result.append(.init(level(r), level(g), level(b))) } } }
    return result
  }

  static func validate(_ pixels: [Sample]) throws {
    guard !pixels.isEmpty, pixels.count <= maximumPixels else { throw CraftError.invalid("Palette input must contain 1 through 8,388,608 pixels.") }
    for (i, p) in pixels.enumerated() {
      if i % 4096 == 0 { try Task.checkCancellation() }
      guard (0..<4).allSatisfy({ p[$0].isFinite && (0...1).contains(p[$0]) }) else {
        throw CraftError.invalid("Indexed color requires finite SDR samples and alpha between zero and one.")
      }
    }
  }
  private struct Point { var v: SIMD3<Float>; var weight: Int }
  private static func medianCut(_ points: [Point], count: Int) throws -> [SIMD3<Float>] {
    guard !points.isEmpty, count > 0 else { return [] }
    var boxes = [points]
    while boxes.count < count {
      try Task.checkCancellation()
      var selected: Int?, axis = 0, score: Float = -1
      for (i, box) in boxes.enumerated() where box.count > 1 {
        var bestAxis = 0, extent: Float = -1
        for a in 0..<3 {
          var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
          for p in box { lo = min(lo, p.v[a]); hi = max(hi, p.v[a]) }
          if hi - lo > extent { bestAxis = a; extent = hi - lo }
        }
        let weight = box.reduce(Float.zero) { $0 + Float($1.weight) }, candidate = extent * sqrt(weight)
        if candidate > score { selected = i; axis = bestAxis; score = candidate }
      }
      guard let selected, score > 0 else { break }
      let removed = boxes[selected]; boxes[selected] = boxes[boxes.count - 1]; boxes.removeLast()
      // The Rust sort is stable. Keep explicit input-order ties in Swift too.
      let sorted = removed.enumerated().sorted {
        $0.element.v[axis] == $1.element.v[axis] ? $0.offset < $1.offset : $0.element.v[axis] < $1.element.v[axis]
      }.map(\.element)
      let total = sorted.reduce(0) { $0 + $1.weight }; var acc = 0, cut = 1
      for (i, p) in sorted.enumerated() {
        acc += p.weight
        if acc * 2 >= total { cut = min(sorted.count - 1, max(1, i + 1)); break }
      }
      boxes.append(Array(sorted[..<cut])); boxes.append(Array(sorted[cut...]))
    }
    return boxes.map { box in
      let weight = box.reduce(0.0) { $0 + Double($1.weight) }
      var mean = SIMD3<Float>.zero
      for c in 0..<3 { mean[c] = Float(box.reduce(0.0) { $0 + Double($1.v[c]) * Double($1.weight) } / weight) }
      return mean
    }
  }
  private static func nearestVector(_ centers: [SIMD3<Float>], _ p: SIMD3<Float>) -> Int {
    var best = 0, distance = Float.greatestFiniteMagnitude
    for (i, c) in centers.enumerated() {
      let d = c - p, value = d.x * d.x + d.y * d.y + d.z * d.z
      if value < distance { best = i; distance = value }
    }; return best
  }
  private static func refine(_ points: [Point], _ centers: inout [SIMD3<Float>], iterations: Int) throws {
    guard !centers.isEmpty else { return }
    for _ in 0..<iterations {
      var sums = [SIMD3<Double>](repeating: .zero, count: centers.count), counts = [Double](repeating: 0, count: centers.count)
      for (index, p) in points.enumerated() {
        if index % 1024 == 0 { try Task.checkCancellation() }
        let i = nearestVector(centers, p.v), w = Double(p.weight)
        for c in 0..<3 { sums[i][c] += Double(p.v[c]) * w }; counts[i] += w
      }
      for i in centers.indices where counts[i] > 0 { for c in 0..<3 { centers[i][c] = Float(sums[i][c] / counts[i]) } }
    }
  }
  public static func palette(_ pixels: [Sample], kind: IndexedPaletteKind, colors: Int,
    forced: [PaletteColor] = [], sourceProfile: Data? = nil) throws -> [PaletteColor] {
    try validate(pixels)
    guard (1...256).contains(colors), forced.count <= 256, Set(forced).count == forced.count,
      !kind.isMaster, kind != .custom, kind != .previous else { throw CraftError.invalid("Invalid palette calculation or unresolved palette source.") }
    if let sourceProfile { try NativeModeProfile.validate(sourceProfile, mode: .rgb, depth: .u8) }
    var histogram = [PaletteColor: Int]()
    for (i, p) in pixels.enumerated() {
      if i % 4096 == 0 { try Task.checkCancellation() }
      if p.w >= 0.5 { histogram[PaletteColor(p), default: 0] += 1 }
    }
    let entries = histogram.sorted { $0.key.key < $1.key.key }, room = max(0, colors - forced.count)
    let computed: [PaletteColor]
    switch kind {
    case .exact:
      guard Set(entries.map(\.key) + forced).count <= 256 else { throw CraftError.invalid("Exact palette requires at most 256 opaque and forced colors.") }
      computed = entries.map(\.key)
    case .systemMac: computed = macPalette
    case .systemWindows: computed = windowsPalette
    case .web: computed = webPalette
    case .uniform: computed = uniformPalette(colors: max(8, room))
    case .localAdaptive, .localPerceptual, .localSelective:
      if entries.count <= room { computed = entries.map(\.key) }
      else {
        let adaptive = kind == .localAdaptive
        let standard = try NativeModeProfile.standard(.rgb, depth: .u8)
        let managed = !adaptive && sourceProfile != nil && sourceProfile != standard
        let toSRGB = try managed ? NativeModeTransform(mode: .rgb, depth: .u8, profile: standard, rgbProfile: sourceProfile) : nil
        let fromSRGB = try managed ? NativeModeTransform(mode: .rgb, depth: .u8, profile: sourceProfile, rgbProfile: standard) : nil
        let points = try entries.map { entry -> Point in
          let c = entry.key.vector; var sample = SIMD4(c.x / 255, c.y / 255, c.z / 255, 1)
          if let toSRGB { let p = try toSRGB.components(entry.key.pixel); sample = SIMD4(p[0], p[1], p[2], 1) }
          return Point(v: adaptive ? c : ClassicToneEngine.lab(sample), weight: entry.value)
        }
        var centers = try medianCut(points, count: room)
        try refine(points, &centers, iterations: adaptive ? 2 : 4)
        computed = try centers.map { center in
          var values = adaptive ? center : ClassicToneEngine.rgb(center) * 255
          if let fromSRGB { let p = try fromSRGB.components(Pixel(values.x / 255, values.y / 255, values.z / 255)); values = SIMD3(p[0], p[1], p[2]) * 255 }
          var color = PaletteColor(vector: values)
          if kind == .localSelective {
            let c = color.vector, snap = SIMD3<Float>((c.x / 51).rounded() * 51, (c.y / 51).rounded() * 51, (c.z / 51).rounded() * 51)
            if (0..<3).allSatisfy({ abs(c[$0] - snap[$0]) <= 10 }) { color = PaletteColor(vector: snap) }
          }; return color
        }
      }
    default: throw CraftError.invalid("Resolve master, custom and previous palette sources before quantization.")
    }
    var result = forced
    for color in computed where !result.contains(color) { if result.count >= 256 { break }; result.append(color) }
    if [.localAdaptive, .localPerceptual, .localSelective, .uniform].contains(kind) {
      result = Array(result.prefix(max(colors, forced.count)))
    }
    return result.isEmpty ? [.init(0, 0, 0)] : result
  }
  static func nearest(_ palette: [PaletteColor], _ p: SIMD3<Float>, excluding: Int? = nil) -> Int {
    var best = 0, distance = Float.greatestFiniteMagnitude
    for (i, c) in palette.enumerated() where i != excluding {
      let d = p * 255 - c.vector, value = d.x * d.x + d.y * d.y + d.z * d.z
      if value < distance { distance = value; best = i }
    }; return best
  }
  static func bayer(_ x: Int, _ y: Int) -> Float {
    let matrix: [UInt8] = [0,32,8,40,2,34,10,42,48,16,56,24,50,18,58,26,12,44,4,36,14,46,6,38,60,28,52,20,62,30,54,22,3,35,11,43,1,33,9,41,51,19,59,27,49,17,57,25,15,47,7,39,13,45,5,37,63,31,55,23,61,29,53,21]
    return (Float(matrix[(y % 8) * 8 + x % 8]) + 0.5) / 64 - 0.5
  }
  private static func noise(_ x: Int, _ y: Int) -> Float {
    var h = UInt32(truncatingIfNeeded: x) &* 0x8da6b343 ^ UInt32(truncatingIfNeeded: y) &* 0xd8163841 ^ UInt32(7) &* 0xcb1ab31f
    h ^= h >> 13; h &*= 0x5bd1e995; h ^= h >> 15; return Float(h & 65535) / 65535
  }
  public static func indices(_ pixels: [Sample], width: Int, palette: [PaletteColor],
    dither: IndexedDither, amount: Float = 1, transparentIndex: Int? = nil, preserveExact: Bool = false) throws -> Data {
    try validate(pixels)
    guard width > 0, width <= Surface.maxDimension, pixels.count % width == 0,
      pixels.count / width <= Surface.maxDimension, (1...256).contains(palette.count),
      amount.isFinite, (0...1).contains(amount) else { throw CraftError.invalid("Invalid indexed raster layout or dither amount.") }
    if let t = transparentIndex {
      guard palette.indices.contains(t), palette.count > 1 || pixels.allSatisfy({ $0.w < 0.5 }) else {
        throw CraftError.invalid("Transparent palette entry is missing or leaves no opaque colors.")
      }
    }
    let spread = min(1 / max(1, cbrt(Float(palette.count))), 0.5) * amount
    var result = Data(count: pixels.count), current = [SIMD3<Float>](repeating: .zero, count: width + 2), next = current
    var exact = [PaletteColor: Int]()
    if preserveExact { for (i, color) in palette.enumerated() where i != transparentIndex && exact[color] == nil { exact[color] = i } }
    for y in 0..<(pixels.count / width) {
      try Task.checkCancellation()
      if dither == .diffusion { swap(&current, &next); next = [SIMD3<Float>](repeating: .zero, count: width + 2) }
      for x in 0..<width {
        let i = y * width + x, p = pixels[i]
        if p.w < 0.5, let t = transparentIndex { result[i] = UInt8(t); continue }
        if p.w <= 0 { continue }
        if preserveExact, let index = exact[PaletteColor(p)] { result[i] = UInt8(index); continue }
        var c = SIMD3(p.x, p.y, p.z)
        switch dither {
        case .none: break
        case .diffusion: c += current[x + 1]
        case .pattern: c += SIMD3(repeating: bayer(x, y) * spread)
        case .noise: c += SIMD3(repeating: (noise(x, y) - 0.5) * spread)
        }
        for a in 0..<3 { c[a] = unit(c[a]) }
        let index = nearest(palette, c, excluding: transparentIndex); result[i] = UInt8(index)
        if dither == .diffusion {
          let error = (c - palette[index].vector / 255) * amount
          current[x + 2] += error * 7 / 16; next[x] += error * 3 / 16
          next[x + 1] += error * 5 / 16; next[x + 2] += error / 16
        }
      }
    }; return result
  }
}
