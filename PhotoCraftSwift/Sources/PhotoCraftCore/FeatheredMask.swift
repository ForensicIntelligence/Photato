import Foundation
import os

/// A scalar plane may be wider than an editable Surface when it includes a
/// virtual border. Disjoint pieces retain their own sparse raster storage.
package struct FeatherSamplePlane: Sendable {
  package struct Piece: Sendable {
    let x: Int
    let y: Int
    let samples: Surface

    package init(x: Int, y: Int, samples: Surface) {
      self.x = x
      self.y = y
      self.samples = samples
    }

    func overlap(with region: IntRect) -> IntRect {
      IntRect(x: region.x - x, y: region.y - y, width: region.width, height: region.height)
        .clipped(toWidth: samples.width, height: samples.height)
    }
  }

  let width: Int
  let height: Int
  let implicit: Float
  private let surface: Surface?
  private let pieces: [Piece]
  private let rectangle: IntRect?

  init(_ surface: Surface) {
    self.surface = surface
    width = surface.width
    height = surface.height
    implicit = unit(surface.defaultPixel.r)
    pieces = []
    rectangle = nil
  }

  package init(width: Int, height: Int, outside: Float, pieces: [Piece]) {
    self.width = width
    self.height = height
    implicit = outside
    surface = nil
    self.pieces = pieces
    rectangle = nil
  }

  /// Integer Gray8 edges divide the padded plane into two exact sample values.
  package init(width: Int, height: Int, outside: Float, rectangle: IntRect) {
    self.width = width
    self.height = height
    implicit = outside
    surface = nil
    pieces = []
    self.rectangle = rectangle.width > 0 && rectangle.height > 0 ? rectangle : nil
  }

  var isUniform: Bool {
    if let surface { return surface.tileCount == 0 }
    return pieces.isEmpty && rectangle == nil
  }

  func hasFeatherSamples(in region: IntRect) -> Bool {
    if let surface { return surface.hasFeatherSamples(in: region) }
    if let rectangle {
      let overlap = Self.localOverlap(rectangle, in: region)
      return overlap.width > 0 && overlap.height > 0
    }
    return pieces.contains { piece in
      let part = piece.overlap(with: region)
      return part.width > 0 && part.height > 0
        && (piece.samples.defaultPixel.r != implicit || piece.samples.hasFeatherSamples(in: part))
    }
  }

  func featherInput(in region: IntRect) -> [Float]? {
    if let surface { return surface.featherInput(in: region) }
    if let rectangle {
      let overlap = Self.localOverlap(rectangle, in: region)
      guard overlap.width > 0, overlap.height > 0 else { return nil }
      let inside = 1 - implicit
      if overlap.width == region.width && overlap.height == region.height {
        return [Float](repeating: inside, count: region.width * region.height)
      }
      var samples = [Float](repeating: implicit, count: region.width * region.height)
      for y in overlap.y..<(overlap.y + overlap.height) {
        let start = y * region.width + overlap.x
        for x in start..<(start + overlap.width) { samples[x] = inside }
      }
      return samples
    }
    var output: [Float]?
    for piece in pieces {
      let overlap = piece.overlap(with: region)
      guard overlap.width > 0, overlap.height > 0 else { continue }
      let input = piece.samples.featherInput(in: overlap)
      let fill = unit(piece.samples.defaultPixel.r)
      guard input != nil || fill != implicit else { continue }
      if output == nil {
        output = [Float](repeating: implicit, count: region.width * region.height)
      }
      let dx = piece.x + overlap.x - region.x
      let dy = piece.y + overlap.y - region.y
      for y in 0..<overlap.height {
        let destination = (dy + y) * region.width + dx
        for x in 0..<overlap.width {
          output![destination + x] = input?[y * overlap.width + x] ?? fill
        }
      }
    }
    return output
  }

  private static func localOverlap(_ rectangle: IntRect, in region: IntRect) -> IntRect {
    IntRect(x: rectangle.x - region.x, y: rectangle.y - region.y,
      width: rectangle.width, height: rectangle.height)
      .clipped(toWidth: region.width, height: region.height)
  }
}

/// Evaluate pixel-mask Feather on demand. Kernel coordinates are virtual,
/// including when the source already spans 300,000 pixels.
package final class FeatheredMask: Sendable {
  struct ClampedEdges: OptionSet, Sendable {
    let rawValue: UInt8
    static let left = Self(rawValue: 1)
    static let right = Self(rawValue: 2)
    static let top = Self(rawValue: 4)
    static let bottom = Self(rawValue: 8)
  }

  enum Values: Sendable {
    case uniform(Float)
    case samples([Float], width: Int)

    func value(atX x: Int, y: Int) -> Float {
      switch self {
      case .uniform(let value): value
      case .samples(let samples, let width): samples[y * width + x]
      }
    }
  }

  private struct Entry: Sendable {
    let x: Int
    let y: Int
    let values: Values
  }

  private static let side = Surface.tileSide
  private static let slots = 64
  static let maximumCacheBytes = side * side * slots * MemoryLayout<Float>.stride

  private let source: FeatherSamplePlane
  private let cacheSide: Int
  private let cacheSlots: Int
  private let weights: [Float]
  private let outside: Float
  private let edges: ClampedEdges
  private let area: AreaMaskFeather?
  private let defaultSample: Float
  private let horizontalDefault: Float
  private let filteredDefault: Float
  private let implicitEqualsOutside: Bool
  private let storageThreshold: Float
  private let padding: Int
  var origin: (x: Int, y: Int) { (area?.bounds.x ?? -padding, area?.bounds.y ?? -padding) }
  var width: Int { area?.bounds.width ?? (source.width + 2 * padding) }
  var height: Int { area?.bounds.height ?? (source.height + 2 * padding) }
  var implicitMatchesOutside: Bool { implicitEqualsOutside }
  package var isConstantOutside: Bool { source.isUniform && implicitMatchesOutside }
  var support: Int { area?.support ?? padding }
  package var implicitInterior: Float { area?.interiorSample(defaultSample) ?? filteredDefault }
  var clampedSourceEdges: ClampedEdges {
    guard let area else { return edges }
    guard area.extendEdges else { return [] }
    var clamped: ClampedEdges = []
    if area.bounds.x == 0 { clamped.insert(.left) }
    if area.bounds.y == 0 { clamped.insert(.top) }
    if area.bounds.x + area.bounds.width == source.width { clamped.insert(.right) }
    if area.bounds.y + area.bounds.height == source.height { clamped.insert(.bottom) }
    return clamped
  }
  private let cache: OSAllocatedUnfairLock<[Entry?]>

  convenience init(source: Surface, radius: Double, outside: Float, edges: ClampedEdges,
    area: AreaMaskFeather? = nil
  ) {
    self.init(source: FeatherSamplePlane(source), radius: radius, outside: outside, edges: edges,
      area: area, cacheSide: Self.side, cacheSlots: Self.slots)
  }

  package convenience init(vectorPlane: FeatherSamplePlane, radius: Double, outside: Float) {
    let area = AreaMaskFeather(wideRadius: radius, width: vectorPlane.width, height: vectorPlane.height)
    self.init(source: vectorPlane, radius: radius, outside: outside, edges: [], area: area,
      cacheSide: Self.vectorTileSide(radius: radius), cacheSlots: area == nil ? Self.slots : 16,
      measuredWeights: Self.measuredVectorWeights(radius))
  }

  package static func vectorTileSide(radius: Double) -> Int { radius > 100 ? 512 : side }

  // Normalized edges and corners in the archived Photoshop RGB32 vector PSD.
  // The two separable passes retain the binary fractions on aligned contours.
  private static func measuredVectorWeights(_ radius: Double) -> [Float]? {
    let taps: [Int]
    switch radius {
    case 1.5: taps = [3, 11, 29, 52, 66, 52, 29, 11, 3]
    case 2: taps = [1, 3, 8, 17, 31, 44, 48, 44, 31, 17, 8, 3, 1]
    default: return nil
    }
    return taps.map { Float($0) / 256 }
  }

  package var maximumResidentBytes: Int { cacheSide * cacheSide * cacheSlots * MemoryLayout<Float>.stride }

  package func sampleInSource(x: Double, y: Double) -> Float {
    let x = x - Double(origin.x), y = y - Double(origin.y)
    if let px = Int(exactly: x - 0.5), let py = Int(exactly: y - 0.5) {
      if px < 0 || py < 0 || px >= width || py >= height { return outside }
      return unit(value(px, py))
    }
    return MaskSampler.sample(width: width, height: height, x: x, y: y, outside: outside, value: value)
  }

  private init(source: FeatherSamplePlane, radius: Double, outside: Float, edges: ClampedEdges,
    area: AreaMaskFeather?, cacheSide: Int, cacheSlots: Int, measuredWeights: [Float]? = nil
  ) {
    self.source = source
    self.cacheSide = cacheSide
    self.cacheSlots = cacheSlots
    cache = OSAllocatedUnfairLock(initialState: [Entry?](repeating: nil, count: cacheSlots))
    self.outside = outside
    self.edges = edges
    self.area = area
    let sigma = max(0.05, radius)
    let pad = measuredWeights.map { $0.count / 2 } ?? (area == nil ? Int(ceil(3 * sigma)) : 0)
    padding = pad
    let kernel: [Float]
    let threshold: Float
    if let measuredWeights {
      kernel = measuredWeights
      threshold = 0
    } else {
      let raw = (-pad...pad).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
      let total = raw.reduce(0, +)
      kernel = raw.map { $0 / total }
      threshold = 0.000001
    }
    weights = kernel
    storageThreshold = threshold
    let implicit = source.implicit
    defaultSample = implicit
    let horizontal = Self.weightedConstant(implicit, weights: kernel)
    horizontalDefault = horizontal
    filteredDefault = Self.stored(Self.weightedConstant(horizontal, weights: kernel), outside: outside,
      threshold: threshold)
    // Outside rows bypass the horizontal pass. For equal implicit and outside
    // samples, bound the possible vertical results before eliding their edges.
    let low = Self.weightedConstant(min(horizontal, outside), weights: kernel)
    let high = Self.weightedConstant(max(horizontal, outside), weights: kernel)
    implicitEqualsOutside = implicit == outside && (area?.interiorSample(implicit) ?? implicit) == outside
      && abs(low - outside) <= threshold
      && abs(high - outside) <= threshold
  }

  func value(_ x: Int, _ y: Int) -> Float {
    if isConstantOutside { return outside }
    let side = cacheSide
    let column = x / side, row = y / side
    // Direct mapping retains consecutive tiles across a compositor patch.
    let slot = (column + row * 17) % cacheSlots
    return cache.withLock { entries in
      if entries[slot]?.x != column || entries[slot]?.y != row {
        let originX = column * side, originY = row * side
        guard let values = prepare(x: originX - padding, y: originY - padding,
          width: min(side, width - originX), height: min(side, height - originY)) else { return outside }
        entries[slot] = Entry(x: column, y: row, values: values)
      }
      return entries[slot]!.values.value(atX: x % side, y: y % side)
    }
  }

  func region(_ bounds: IntRect) throws -> Values {
    if isConstantOutside { return .uniform(outside) }
    try Task.checkCancellation()
    guard let values = prepare(x: bounds.x - padding, y: bounds.y - padding,
      width: bounds.width, height: bounds.height)
    else { throw CancellationError() }
    return values
  }

  private static func weightedConstant(_ value: Float, weights: [Float]) -> Float {
    weights.reduce(0) { $0 + value * $1 }
  }

  private static func stored(_ value: Float, outside: Float, threshold: Float) -> Float {
    abs(value - outside) > threshold ? unit(value) : outside
  }

  private func prepare(x: Int, y: Int, width: Int, height: Int) -> Values? {
    if let area {
      guard !Task.isCancelled,
        let result = area.prepare(source: source, outside: outside, x: x, y: y, width: width, height: height)
      else { return nil }
      if let samples = result.samples { return .samples(samples, width: width) }
      return .uniform(result.uniform)
    }
    let inputLeft = x - padding, inputTop = y - padding
    let inputWidth = width + 2 * padding, inputHeight = height + 2 * padding
    let inputRight = inputLeft + inputWidth, inputBottom = inputTop + inputHeight
    let left = max(0, inputLeft), top = max(0, inputTop)
    let right = min(source.width, inputRight), bottom = min(source.height, inputBottom)
    let box = IntRect(x: left, y: top, width: right - left, height: bottom - top)
    let input = source.featherInput(in: box)
    let clampLeft = edges.contains(.left), clampRight = edges.contains(.right)
    let clampTop = edges.contains(.top), clampBottom = edges.contains(.bottom)
    let uniformX = (inputLeft >= 0 || clampLeft) && (inputRight <= source.width || clampRight)
    let uniformY = inputTop >= -padding && inputBottom <= source.height + padding
      && (inputTop >= 0 || clampTop) && (inputBottom <= source.height || clampBottom)
    if input == nil {
      if implicitEqualsOutside { return .uniform(outside) }
      if uniformX && uniformY { return .uniform(filteredDefault) }
    }

    // The first pass uses real source rows only. Clamped edge rows can reuse
    // their result, and unstored source rows are identical in the implicit case.
    let rows = input == nil ? 1 : box.height
    var horizontal = [Float](repeating: horizontalDefault, count: rows * width)
    if input != nil || !uniformX {
      var line = [Float](repeating: outside, count: inputWidth)
      for row in 0..<rows {
        for offset in line.indices {
          var sx = inputLeft + offset
          if sx < 0 && clampLeft { sx = 0 }
          if sx >= source.width && clampRight { sx = source.width - 1 }
          if sx < 0 || sx >= source.width { line[offset] = outside }
          else { line[offset] = input?[row * box.width + sx - left] ?? defaultSample }
        }
        for column in 0..<width {
          var value: Float = 0
          for i in weights.indices { value += line[column + i] * weights[i] }
          horizontal[row * width + column] = value
        }
      }
    }

    var output = [Float](repeating: outside, count: height * width)
    var line = [Float](repeating: outside, count: inputHeight)
    for column in 0..<width {
      for offset in line.indices {
        var sy = inputTop + offset
        if sy >= -padding && sy < source.height + padding {
          if sy < 0 && clampTop { sy = 0 }
          if sy >= source.height && clampBottom { sy = source.height - 1 }
        }
        if sy < 0 || sy >= source.height { line[offset] = outside }
        else { line[offset] = horizontal[(input == nil ? 0 : sy - top) * width + column] }
      }
      for row in 0..<height {
        var value: Float = 0
        for i in weights.indices { value += line[row + i] * weights[i] }
        output[row * width + column] = Self.stored(value, outside: outside, threshold: storageThreshold)
      }
    }
    return .samples(output, width: width)
  }
}
