import Foundation

public enum PatternPresets {
  // PhotoCraft's seven original procedural (CC0) tiles; no Adobe artwork is bundled.
  public static func make() throws -> [RasterPattern] {
    func noise(_ x: UInt32, _ y: UInt32, _ seed: UInt32) -> Float {
      var h = x &* 0x8da6_b343 ^ y &* 0xd816_3841 ^ seed &* 0xcb1a_b31f
      h ^= h >> 13
      h = h &* 0x5bd1_e995
      h ^= h >> 15
      return Float(h & 0xffff) / 65535
    }
    func gray(_ value: Float) -> Pixel { Pixel(value, value, value) }
    func tile(_ name: String, _ w: Int, _ h: Int, _ sample: (Int, Int) -> Pixel) throws
      -> RasterPattern
    {
      var surface = try Surface(width: w, height: h)
      for y in 0..<h { for x in 0..<w { surface.setPixel(x: x, y: y, sample(x, y)) } }
      return try RasterPattern(name: name, surface: surface)
    }
    return try [
      tile("Checkerboard", 16, 16) { x, y in gray((x / 8 + y / 8) % 2 == 0 ? 0.8 : 1) },
      tile("Diagonal Lines", 8, 8) { x, y in gray((x + y) % 8 < 2 ? 0.2 : 1) },
      tile("Dots", 12, 12) { x, y in
        let dx = Float(x) + 0.5 - 6
        let dy = Float(y) + 0.5 - 6
        return gray(unit(sqrt(dx * dx + dy * dy) - 3))
      },
      tile("Grid", 16, 16) { x, y in gray(x == 0 || y == 0 ? 0.55 : 1) },
      tile("Bricks", 32, 16) { x, y in
        let row = y / 8
        let xo = (x + (row % 2 == 1 ? 8 : 0)) % 16
        let n = noise(UInt32(x), UInt32(y), 7) * 0.08
        return y % 8 == 7 || xo == 15
          ? Pixel(0.78 + n, 0.76 + n, 0.72 + n) : Pixel(0.62 + n, 0.27 + n * 0.5, 0.2)
      },
      tile("Weave", 16, 16) { x, y in
        let over = (x / 4 + y / 4) % 2 == 0
        let t = Float(over ? y % 4 : x % 4) / 3
        let v: Float = 0.55 + 0.35 * (1 - abs(2 * t - 1))
        return Pixel(v, v * 0.92, v * 0.8)
      },
      tile("Paper Noise", 64, 64) { x, y in
        func octave(_ cell: Int, _ seed: UInt32) -> Float {
          let cx = x / cell
          let cy = y / cell
          let n = 64 / cell
          let fx = Float(x % cell) / Float(cell)
          let fy = Float(y % cell) / Float(cell)
          func value(_ x: Int, _ y: Int) -> Float { noise(UInt32(x % n), UInt32(y % n), seed) }
          func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }
          let sx = smooth(fx)
          let sy = smooth(fy)
          let a = value(cx, cy) + (value(cx + 1, cy) - value(cx, cy)) * sx
          let b = value(cx, cy + 1) + (value(cx + 1, cy + 1) - value(cx, cy + 1)) * sx
          return a + (b - a) * sy
        }
        return gray(0.78 + 0.14 * octave(8, 1) + 0.08 * octave(2, 2))
      },
    ]
  }
}
