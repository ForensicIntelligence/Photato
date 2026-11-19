import Foundation
import os

/// Counts binary Gray8 tiles over a piece. Mixed tiles are deliberately unknown.
package struct FeatherBinaryTiles: Sendable {
  private let stride: Int
  private let zeros: [UInt16]
  private let ones: [UInt16]

  package var residentBytes: Int { (zeros.count + ones.count) * MemoryLayout<UInt16>.stride }

  package func tiles(with sample: Float) -> Int { Int((sample == 0 ? zeros : ones).last ?? 0) }

  package init(columns: Int, rows: Int, values: [UInt8]) {
    precondition(values.count == columns * rows && values.count <= Int(UInt16.max))
    stride = columns + 1
    func prefix(for sample: UInt8) -> [UInt16] {
      var prefix = [UInt16](repeating: 0, count: (rows + 1) * (columns + 1))
      for y in 0..<rows {
        var count: UInt16 = 0
        for x in 0..<columns {
          if values[y * columns + x] == sample { count += 1 }
          prefix[(y + 1) * (columns + 1) + x + 1] = prefix[y * (columns + 1) + x + 1] + count
        }
      }
      return prefix
    }
    zeros = prefix(for: 0)
    ones = prefix(for: 1)
  }

  func constant(in region: IntRect) -> Float? {
    let side = Surface.tileSide
    let left = region.x / side, top = region.y / side
    let right = (region.x + region.width + side - 1) / side
    let bottom = (region.y + region.height + side - 1) / side
    let area = (right - left) * (bottom - top)
    func count(_ table: [UInt16]) -> Int {
      Int(table[bottom * stride + right]) + Int(table[top * stride + left])
        - Int(table[bottom * stride + left]) - Int(table[top * stride + right])
    }
    if count(zeros) == area { return 0 }
    if count(ones) == area { return 1 }
    return nil
  }
}

/// A scalar plane may be wider than an editable Surface when it includes a
/// virtual border. Disjoint pieces retain their own sparse raster storage.
package struct FeatherSamplePlane: Sendable {
  package static let vectorPieceSide = 8_192

  package struct Piece: Sendable {
    let x: Int
    let y: Int
    let samples: Surface
    let binaryTiles: FeatherBinaryTiles?

    package init(x: Int, y: Int, samples: Surface, binaryTiles: FeatherBinaryTiles? = nil) {
      self.x = x
      self.y = y
      self.samples = samples
      self.binaryTiles = binaryTiles
    }

    func overlap(with region: IntRect) -> IntRect {
      IntRect(x: region.x - x, y: region.y - y, width: region.width, height: region.height)
        .clipped(toWidth: samples.width, height: samples.height)
    }

    func constant(in local: IntRect) -> Float? {
      samples.tileCount == 0 ? samples.defaultPixel.r : binaryTiles?.constant(in: local)
    }
  }

  let width: Int
  let height: Int
  let implicit: Float
  private let surface: Surface?
  private let grid: PieceGrid?
  let rectangle: IntRect?

  init(_ surface: Surface) {
    self.surface = surface
    width = surface.width
    height = surface.height
    implicit = unit(surface.defaultPixel.r)
    grid = nil
    rectangle = nil
  }

  package init(width: Int, height: Int, outside: Float, pieces: [Piece]) {
    self.width = width
    self.height = height
    implicit = outside
    surface = nil
    grid = pieces.isEmpty ? nil : PieceGrid(width: width, pieces: pieces)
    rectangle = nil
  }

  /// Integer Gray8 edges divide the padded plane into two exact sample values.
  package init(width: Int, height: Int, outside: Float, rectangle: IntRect) {
    self.width = width
    self.height = height
    implicit = outside
    surface = nil
    grid = nil
    let clipped = rectangle.clipped(toWidth: width, height: height)
    self.rectangle = clipped.width > 0 && clipped.height > 0 ? clipped : nil
  }

  var isUniform: Bool {
    if let surface { return surface.tileCount == 0 }
    return grid == nil && rectangle == nil
  }

  /// A footprint can cross cells, but every contributing sample must agree.
  func constantFeatherSample(in region: IntRect) -> Float? {
    guard let grid else { return nil }
    if !grid.crossesCellBoundary(region) {
      guard let piece = grid.piece(atX: region.x, y: region.y) else { return implicit }
      let part = piece.overlap(with: region)
      if part.width == 0 || part.height == 0 { return implicit }
      guard let value = piece.constant(in: part) else { return nil }
      return value == implicit || (part.width == region.width && part.height == region.height) ? value : nil
    }
    var covered = 0
    var value: Float?
    for next in grid.overlapping(region, width: width, height: height) {
      let part = next.overlap(with: region)
      if part.width > 0 && part.height > 0 {
        guard let sample = next.constant(in: part), value == nil || value == sample else { return nil }
        value = sample
        covered += part.width * part.height
      }
    }
    if covered == 0 { return implicit }
    return covered == region.width * region.height || value == implicit ? value : nil
  }

  func hasFeatherSamples(in region: IntRect) -> Bool {
    if let surface { return surface.hasFeatherSamples(in: region) }
    if let rectangle {
      let overlap = Self.localOverlap(rectangle, in: region)
      return overlap.width > 0 && overlap.height > 0
    }
    return grid?.overlapping(region, width: width, height: height).contains { piece in
      let part = piece.overlap(with: region)
      return part.width > 0 && part.height > 0
        && (piece.samples.defaultPixel.r != implicit || piece.samples.hasFeatherSamples(in: part))
    } ?? false
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
    guard let grid else { return nil }
    var output: [Float]?
    for piece in grid.overlapping(region, width: width, height: height) {
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

  /// Vector preparation yields at most one bounded piece per grid cell.
  private struct PieceGrid: Sendable {
    private static let side = FeatherSamplePlane.vectorPieceSide
    private let columns: Int
    private let pieces: [Int: Piece]

    init(width: Int, pieces: [Piece]) {
      let side = Self.side
      let columns = (width + side - 1) / side
      self.columns = columns
      self.pieces = Dictionary(uniqueKeysWithValues: pieces.map {
        precondition($0.x % side + $0.samples.width <= side && $0.y % side + $0.samples.height <= side)
        return (($0.y / side) * columns + $0.x / side, $0)
      })
    }

    func piece(atX x: Int, y: Int) -> Piece? { pieces[(y / Self.side) * columns + x / Self.side] }

    func crossesCellBoundary(_ region: IntRect) -> Bool {
      region.x % Self.side + region.width > Self.side || region.y % Self.side + region.height > Self.side
    }

    func overlapping(_ region: IntRect, width: Int, height: Int) -> [Piece] {
      let scope = region.clipped(toWidth: width, height: height)
      guard scope.width > 0, scope.height > 0 else { return [] }
      let side = Self.side
      let columns = (scope.x / side)...((scope.x + scope.width - 1) / side)
      let rows = (scope.y / side)...((scope.y + scope.height - 1) / side)
      var result: [Piece] = []
      for row in rows {
        for column in columns {
          if let piece = pieces[row * self.columns + column] { result.append(piece) }
        }
      }
      return result
    }
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

  private struct Cache: Sendable {
    var positions: [Entry?]
    var rectangles: [AreaMaskFeather.RectangleWindow: Values] = [:]
    var order: [AreaMaskFeather.RectangleWindow] = []
    var next = 0

    mutating func insert(_ values: Values, for window: AreaMaskFeather.RectangleWindow) {
      let limit = FeatheredMask.rectangleCacheSlots
      if order.count == limit {
        rectangles.removeValue(forKey: order[next])
        order[next] = window
        next = (next + 1) % limit
      } else {
        order.append(window)
      }
      rectangles[window] = values
    }
  }

  private static let side = Surface.tileSide
  private static let slots = 64
  private static let rectangleCacheSlots = 48
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
  private let cache: OSAllocatedUnfairLock<Cache>

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

  package var maximumResidentBytes: Int {
    let templates = area != nil && source.rectangle != nil ? Self.rectangleCacheSlots : 0
    return cacheSide * cacheSide * (cacheSlots + templates) * MemoryLayout<Float>.stride
  }

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
    cache = OSAllocatedUnfairLock(initialState: Cache(positions: [Entry?](repeating: nil, count: cacheSlots)))
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
    return withTile(column: x / side, row: y / side) {
      $0.value(atX: x % side, y: y % side)
    } ?? outside
  }

  private func withTile<T: Sendable>(column: Int, row: Int, _ read: @Sendable (Values) -> T) -> T? {
    let side = cacheSide
    // Direct mapping retains consecutive tiles across a compositor patch.
    let slot = (column + row * 17) % cacheSlots
    return cache.withLock { state in
      if state.positions[slot]?.x != column || state.positions[slot]?.y != row {
        let originX = column * side, originY = row * side
        let tileWidth = min(side, width - originX), tileHeight = min(side, height - originY)
        let values: Values
        if let area, let window = area.rectangleWindow(source: source, outside: outside,
          x: originX, y: originY, width: tileWidth, height: tileHeight) {
          if let constant = window.uniformCoverage(outside: outside) {
            values = .uniform(constant)
          } else if let cached = state.rectangles[window] {
            values = cached
          } else {
            guard let samples = area.filterRectangle(window, outside: outside) else { return nil }
            values = .samples(samples, width: tileWidth)
            state.insert(values, for: window)
          }
        } else {
          guard let prepared = prepare(x: originX - padding, y: originY - padding,
            width: tileWidth, height: tileHeight) else { return nil }
          values = prepared
        }
        state.positions[slot] = Entry(x: column, y: row, values: values)
      }
      return read(state.positions[slot]!.values)
    }
  }

  private struct RectangleAxisWindow: Hashable {
    let extent: Int
    let sourceSamples: Range<Int>
    let insideRectangle: Range<Int>
    let requested: Range<Int>
  }

  /// For binary rectangles with unclamped edges, equal pairs of axis windows
  /// have the same full input and the same output subset. The raw-source range
  /// also preserves the short filter's special treatment of rows off the source.
  package func rectangleSamplesAreUnit(in region: IntRect, adjusted: @Sendable (Float) -> Float) throws -> Bool {
    try Task.checkCancellation()
    if isConstantOutside { return adjusted(outside) == 1 }
    let rect = source.rectangle
    let side = cacheSide, pad = support
    func representatives(start: Int, count: Int, origin: Int, extent: Int, sourceExtent: Int,
      inside: Range<Int>) -> [(tile: Int, samples: Range<Int>)] {
      let first = start - origin, end = first + count
      var seen: Set<RectangleAxisWindow> = []
      var result: [(Int, Range<Int>)] = []
      for tile in (first / side)...((end - 1) / side) {
        let offset = tile * side
        let length = min(side, extent - offset)
        let input = origin + offset - pad
        let inputEnd = input + length + 2 * pad
        func local(_ interval: Range<Int>) -> Range<Int> {
          let low = max(input, interval.lowerBound), high = min(inputEnd, interval.upperBound)
          return low < high ? (low - input)..<(high - input) : 0..<0
        }
        let samples = max(0, first - offset)..<min(length, end - offset)
        let key = RectangleAxisWindow(extent: length, sourceSamples: local(0..<sourceExtent),
          insideRectangle: local(inside), requested: samples)
        if seen.insert(key).inserted { result.append((tile, samples)) }
      }
      return result
    }
    let axes = origin
    let columns = representatives(start: region.x, count: region.width, origin: axes.x,
      extent: width, sourceExtent: source.width, inside: rect.map { $0.x..<($0.x + $0.width) } ?? 0..<0)
    let rows = representatives(start: region.y, count: region.height, origin: axes.y,
      extent: height, sourceExtent: source.height, inside: rect.map { $0.y..<($0.y + $0.height) } ?? 0..<0)
    for row in rows {
      for column in columns {
        try Task.checkCancellation()
        guard let unitTile = withTile(column: column.tile, row: row.tile, { values in
          switch values {
          case .uniform(let value): return adjusted(unit(value)) == 1
          case .samples(let values, let width):
            for y in row.samples {
              for x in column.samples where adjusted(unit(values[y * width + x])) != 1 { return false }
            }
            return true
          }
        }) else { throw CancellationError() }
        if !unitTile { return false }
      }
    }
    return true
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
    if box.width == inputWidth, box.height == inputHeight, let constant = source.constantFeatherSample(in: box) {
      return .uniform(filteredConstant(constant))
    }
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

  private func filteredConstant(_ sample: Float) -> Float {
    if area != nil { return sample }
    let horizontal = Self.weightedConstant(sample, weights: weights)
    return Self.stored(Self.weightedConstant(horizontal, weights: weights),
      outside: outside, threshold: storageThreshold)
  }

  /// Exact at integer centers for a whole binary vector plane. Wide rolling
  /// sums include the prefix from the start of each cache tile. Samples after
  /// the last requested output and its support cannot enter those sums.
  package func constantVectorCoverage(in region: IntRect) -> Float? {
    guard region.width > 0 && region.height > 0, edges.isEmpty, source.implicit == outside else { return nil }
    let side = cacheSide, pad = support
    let x = region.x - origin.x, y = region.y - origin.y
    let right = x + region.width, bottom = y + region.height
    guard x >= 0, y >= 0, right <= width, bottom <= height else { return nil }
    let left = (area == nil ? x : x / side * side) + origin.x - pad
    let top = (area == nil ? y : y / side * side) + origin.y - pad
    let endX = right + origin.x + pad
    let endY = bottom + origin.y + pad
    let footprint = IntRect(x: left, y: top, width: endX - left, height: endY - top)
    let read = footprint.clipped(toWidth: source.width, height: source.height)
    guard read.width > 0 && read.height > 0 else { return outside }
    let fullyInside = read == footprint
    if let sample = source.constantFeatherSample(in: read), fullyInside || sample == outside {
      if fullyInside { return filteredConstant(sample) }
      if implicitEqualsOutside { return outside }
    }
    if implicitEqualsOutside && !source.hasFeatherSamples(in: read) { return outside }
    return nil
  }
}
