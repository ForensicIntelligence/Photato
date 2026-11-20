import Foundation

/// Cylinder rims and silhouettes are in unwarped source pixels. Depth is
/// relative to the half-width and wrap controls how much artwork is visible.
public struct CylinderWarp: Codable, Equatable, Sendable {
  public static let archiveVersion = 98

  public var left: Double
  public var bottom: Double
  public var right: Double
  public var top: Double
  public var topDepth: Double
  public var bottomDepth: Double
  public var wrap: Double

  public init(left: Double, bottom: Double, right: Double, top: Double,
              topDepth: Double, bottomDepth: Double, wrap: Double) {
    self.left = left; self.bottom = bottom; self.right = right; self.top = top
    self.topDepth = topDepth; self.bottomDepth = bottomDepth; self.wrap = wrap
  }

  public init(photoshopValues values: [Double]) throws {
    guard values.count == 7 else { throw CraftError.invalid("Cylinder Warp requires seven values.") }
    self.init(left: values[0], bottom: values[1], right: values[2], top: values[3],
              topDepth: values[4], bottomDepth: values[5], wrap: values[6])
    try validate()
  }

  public var photoshopValues: [Double] { [left, bottom, right, top, topDepth, bottomDepth, wrap] }
  public var halfWidth: Double { (right - left) / 2 }
  public var surface: Surface { .init(self) }

  public func validate() throws {
    guard photoshopValues.allSatisfy(\.isFinite), [left, bottom, right, top].allSatisfy({ abs($0) <= 1_000_000 }),
          right - left >= 1e-6, bottom - top >= 1e-6, (0...1).contains(wrap) else {
      throw CraftError.invalid("Cylinder Warp needs ordered edges and wrap between 0 and 1.")
    }
    let surface = self.surface
    let bounds = surface.controlBounds
    guard abs(bounds.y) <= 1_000_000, abs(bounds.y + bounds.height) <= 1_000_000,
          bottom - top + min(0, (bottomDepth - topDepth) * halfWidth * surface.rimControlHeight) >= 1e-6 else {
      throw CraftError.invalid("Cylinder Warp rims cannot cross or exceed the supported coordinates.")
    }
  }

  /// Preserve physical rim heights when replacing artwork with a new aspect ratio.
  func scaled(x: Double, y: Double) -> Self {
    .init(left: left * x, bottom: bottom * y, right: right * x, top: top * y,
          topDepth: topDepth * y / x, bottomDepth: bottomDepth * y / x, wrap: wrap)
  }

  public struct Surface: Sendable {
    let cylinder: CylinderWarp
    let coefficients: SIMD4<Double>

    init(_ cylinder: CylinderWarp) {
      self.cylinder = cylinder
      let position = cylinder.wrap.isFinite ? max(0, min(1, cylinder.wrap)) * 40 : 0
      let index = min(Int(position), 39)
      let fraction = position - Double(index)
      let lower = Self.measured[index]
      coefficients = lower + (Self.measured[index + 1] - lower) * fraction
    }

    public var firstVisibleU: Double { coefficients.x }
    public var lastVisibleU: Double { 1 - firstVisibleU }
    var rimControlHeight: Double { coefficients.w }

    public var controlBounds: WarpSourceBounds {
      let topOffset = cylinder.topDepth * cylinder.halfWidth * rimControlHeight
      let bottomOffset = cylinder.bottomDepth * cylinder.halfWidth * rimControlHeight
      let top = cylinder.top + min(0, topOffset)
      let bottom = cylinder.bottom + max(0, bottomOffset)
      return .init(x: cylinder.left, y: top, width: cylinder.right - cylinder.left, height: bottom - top)
    }

    public func point(_ u: Double, _ v: Double) -> PathPoint {
      let reflected = u > 0.5
      let distance = (reflected ? 1 - u : u) - firstVisibleU
      let progress = max(0, min(1, distance / (0.5 - firstVisibleU)))
      let rest = 1 - progress
      let near = 3 * rest * rest * progress
      let far = 3 * rest * progress * progress
      let side = rest * rest * rest + near + far * coefficients.y
      let rim = near * coefficients.z + far * coefficients.w + progress * progress * progress
      return coordinate(reflected ? side : -side, rim: rim, height: max(0, min(1, v)))
    }

    public func mesh() -> WarpMesh {
      let xs = [-1, -1, -1, -1, -1, -coefficients.y, 0, coefficients.y, 1, 1, 1, 1, 1]
      let rims = [0, 0, 0, 0, coefficients.z, coefficients.w, 1, coefficients.w, coefficients.z, 0, 0, 0, 0]
      let points = (0..<4).flatMap { row in
        zip(xs, rims).map { coordinate($0, rim: $1, height: Double(row) / 3) }
      }
      return .init(us: [0, firstVisibleU, 0.5, lastVisibleU, 1], vs: [0, 1], points: points)
    }

    private func coordinate(_ side: Double, rim: Double, height: Double) -> PathPoint {
      let radius = cylinder.halfWidth
      let top = cylinder.top + radius * cylinder.topDepth * rim
      let bottom = cylinder.bottom + radius * cylinder.bottomDepth * rim
      return .init(cylinder.left + radius * (1 + side), top + (bottom - top) * height)
    }

    // Measurements reported against Photoshop 2026 in PhotoCraft issue #4112.
    // Columns are first visible U, inner X tangent, and two rim control heights.
    private static let measured: [SIMD4<Double>] = [
      .init(0.166169, 0.655404, 0.382374, 1.003104),
      .init(0.157304, 0.650228, 0.388326, 1.002685),
      .init(0.148438, 0.645374, 0.394211, 1.007918),
      .init(0.140060, 0.639652, 0.401415, 1.006938),
      .init(0.131885, 0.634064, 0.408465, 1.006069),
      .init(0.123875, 0.628845, 0.414586, 1.005743),
      .init(0.116162, 0.624035, 0.419629, 1.005499),
      .init(0.108674, 0.618563, 0.426905, 1.004990),
      .init(0.101198, 0.614439, 0.431943, 1.010787),
      .init(0.094322, 0.609611, 0.437749, 1.010560),
      .init(0.087757, 0.604929, 0.443406, 1.010361),
      .init(0.081514, 0.600390, 0.448907, 1.010190),
      .init(0.075599, 0.596012, 0.454288, 1.010019),
      .init(0.069994, 0.591836, 0.459420, 1.009888),
      .init(0.064709, 0.587844, 0.464361, 1.009768),
      .init(0.059740, 0.584026, 0.469109, 1.009669),
      .init(0.055072, 0.580427, 0.473609, 1.009588),
      .init(0.050712, 0.576990, 0.477904, 1.009528),
      .init(0.046635, 0.573760, 0.481968, 1.009477),
      .init(0.042824, 0.570758, 0.485764, 1.009440),
      .init(0.039295, 0.567910, 0.489377, 1.009411),
      .init(0.036023, 0.565229, 0.492800, 1.009382),
      .init(0.032681, 0.563478, 0.495519, 1.015285),
      .init(0.029877, 0.561152, 0.498513, 1.015270),
      .init(0.027282, 0.559012, 0.501313, 1.015245),
      .init(0.024894, 0.557004, 0.503913, 1.015241),
      .init(0.022693, 0.555163, 0.506331, 1.015225),
      .init(0.020668, 0.553463, 0.508575, 1.015213),
      .init(0.018816, 0.551877, 0.510651, 1.015217),
      .init(0.017106, 0.550434, 0.512556, 1.015214),
      .init(0.015542, 0.549100, 0.514319, 1.015213),
      .init(0.014115, 0.547868, 0.515936, 1.015223),
      .init(0.012806, 0.546743, 0.517432, 1.015223),
      .init(0.011600, 0.545730, 0.518775, 1.015228),
      .init(0.010506, 0.544788, 0.520034, 1.015230),
      .init(0.009510, 0.543920, 0.521179, 1.015238),
      .init(0.008600, 0.543134, 0.522224, 1.015244),
      .init(0.007763, 0.542420, 0.523173, 1.015251),
      .init(0.007006, 0.541757, 0.524065, 1.015252),
      .init(0.006315, 0.541164, 0.524867, 1.015252),
      .init(0.005686, 0.540608, 0.525602, 1.015261),
    ]
  }
}
