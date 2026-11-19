import Foundation
import os

/// Evaluate pixel-mask Feather on demand. Kernel coordinates are virtual,
/// including when the source already spans 300,000 pixels.
final class FeatheredMask: Sendable {
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

  private let source: Surface
  private let weights: [Float]
  private let outside: Float
  private let edges: ClampedEdges
  private let area: AreaMaskFeather?
  private let defaultSample: Float
  private let horizontalDefault: Float
  private let filteredDefault: Float
  private let implicitEqualsOutside: Bool
  private let padding: Int
  var origin: (x: Int, y: Int) { (area?.bounds.x ?? -padding, area?.bounds.y ?? -padding) }
  var width: Int { area?.bounds.width ?? (source.width + 2 * padding) }
  var height: Int { area?.bounds.height ?? (source.height + 2 * padding) }
  var implicitMatchesOutside: Bool { implicitEqualsOutside }
  var isConstantOutside: Bool { source.tileCount == 0 && implicitMatchesOutside }
  var support: Int { area?.support ?? padding }
  var implicitInterior: Float { area?.interiorSample(defaultSample) ?? filteredDefault }
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
  private let cache = OSAllocatedUnfairLock(initialState: [Entry?](repeating: nil, count: FeatheredMask.slots))

  init(source: Surface, radius: Double, outside: Float, edges: ClampedEdges, area: AreaMaskFeather? = nil) {
    self.source = source
    self.outside = outside
    self.edges = edges
    self.area = area
    let sigma = max(0.05, radius)
    let pad = area == nil ? Int(ceil(3 * sigma)) : 0
    padding = pad
    let raw = (-pad...pad).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
    let total = raw.reduce(0, +)
    let kernel = raw.map { $0 / total }
    weights = kernel
    let implicit = unit(source.defaultPixel.r)
    defaultSample = implicit
    let horizontal = Self.weightedConstant(implicit, weights: kernel)
    horizontalDefault = horizontal
    filteredDefault = Self.stored(Self.weightedConstant(horizontal, weights: kernel), outside: outside)
    // Outside rows bypass the horizontal pass. For equal implicit and outside
    // samples, bound the possible vertical results before eliding their edges.
    let low = Self.weightedConstant(min(horizontal, outside), weights: kernel)
    let high = Self.weightedConstant(max(horizontal, outside), weights: kernel)
    implicitEqualsOutside = implicit == outside && (area?.interiorSample(implicit) ?? implicit) == outside
      && abs(low - outside) <= 0.000001
      && abs(high - outside) <= 0.000001
  }

  func value(_ x: Int, _ y: Int) -> Float {
    if isConstantOutside { return outside }
    let side = Self.side
    let column = x / side, row = y / side
    // Direct mapping retains consecutive tiles across a compositor patch.
    let slot = (column + row * 17) % Self.slots
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

  private static func stored(_ value: Float, outside: Float) -> Float {
    // Preserve the previous Float32 storage threshold and read-time clamp.
    abs(value - outside) > 0.000001 ? unit(value) : outside
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
        output[row * width + column] = Self.stored(value, outside: outside)
      }
    }
    return .samples(output, width: width)
  }
}
