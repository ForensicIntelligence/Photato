import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Benchmark {
  static func healing(to url: URL) throws {
    var d = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    // Dense, textured RGB/16 baseline: timing excludes creating the input and initial cache.
    var pixels = try Surface(width: 6000, height: 4000, depth: .u16)
    for y in 0..<4000 {
      for x in 0..<6000 {
        let t: Float = x % 16 < 8 ? 0.04 : -0.04
        pixels.setPixel(
          x: x, y: y, Pixel(0.2 + Float(x) / 12000 + t, 0.2 + Float(y) / 8000 + t, 0.4 + t))
      }
    }
    d.layers[0].content = .raster(pixels)
    let baseline = try Renderer.render(d)
    let id = d.layers[0].id
    let source = try Renderer.cloneSample(in: d, layerID: id, sampling: .current)
    var brush = CloneBrush()
    brush.size = 300
    brush.hardness = 0.8
    brush.pressureSize = false
    let stroke = CloneStroke(
      source: source, mapping: .init(source: .init(1200, 1500), anchor: .init(3500, 2500)),
      brush: brush,
      points: [.init(x: 3500, y: 2500), .init(x: 3800, y: 2600)])
    var samples: [[String: Double]] = []
    var last = d
    for _ in 0..<3 {
      var probe = d
      let start = CFAbsoluteTimeGetCurrent()
      try Command.healingBrush(id, .init(stroke: stroke)).apply(to: &probe)
      let applied = CFAbsoluteTimeGetCurrent()
      let snapshot = try Renderer.render(probe, reusing: baseline)
      let rendered = CFAbsoluteTimeGetCurrent()
      _ = try RasterIO.displayImage(snapshot.surface)
      let packed = CFAbsoluteTimeGetCurrent()
      samples.append([
        "repair_ms": (applied - start) * 1000, "regional_composite_ms": (rendered - applied) * 1000,
        "full_sdr_pack_ms": (packed - rendered) * 1000,
      ])
      last = probe
    }
    let full = try Renderer.composite(last)
    let regional = try Renderer.render(last, reusing: baseline)
    let exact = try full.rgbaData(depth: .f32) == regional.surface.rgbaData(depth: .f32)
    guard exact else {
      throw CraftError.invalid("Healing regional rendering differs from full rendering.")
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "canvas": [6000, 4000], "depth": 16, "brush_size": 300, "samples": samples,
      "regional_matches_full_float_bits": exact, "peak_resident_bytes": usage.ru_maxrss,
      "scope":
        "Native release process; source/initial cache setup, AppKit latency, p95 and Photoshop output comparisons excluded.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
  }
}
