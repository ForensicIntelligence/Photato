import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Benchmark {
  static func spotHealing(to url: URL) throws {
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    var pixels = try Surface(width: 6000, height: 4000, depth: .u16)
    for y in 0..<4000 {
      for x in 0..<6000 {
        let t: Float = x % 16 < 8 ? 0.04 : -0.04
        let dirty = (x - 3500) * (x - 3500) + (y - 2500) * (y - 2500) < 144
        pixels.setPixel(
          x: x, y: y,
          dirty
            ? Pixel(0.03, 0.03, 0.03)
            : Pixel(0.2 + Float(x) / 12000 + t, 0.2 + Float(y) / 8000 + t, 0.4 + t))
      }
    }
    document.layers[0].content = .raster(pixels)
    let id = document.layers[0].id
    let baseline = try Renderer.render(document)
    let source = try Renderer.cloneSample(in: document, layerID: id, sampling: .current)
    var samples: [[String: Any]] = []
    var last = document
    for size in [64.0, 300.0] {
      for kind in SpotHealingType.allCases {
        for _ in 0..<2 {
          var probe = document
          var brush = CloneBrush()
          brush.size = size
          brush.hardness = 1
          brush.pressureSize = false
          let stroke = SpotHealingStroke(
            sample: source, brush: brush, points: [.init(x: 3500, y: 2500)], kind: kind)
          let start = CFAbsoluteTimeGetCurrent()
          try Command.spotHealing(id, stroke).apply(to: &probe)
          let applied = CFAbsoluteTimeGetCurrent()
          let snapshot = try Renderer.render(probe, reusing: baseline)
          let rendered = CFAbsoluteTimeGetCurrent()
          _ = try RasterIO.displayImage(snapshot.surface)
          let packed = CFAbsoluteTimeGetCurrent()
          let center = snapshot.surface.pixel(x: 3500, y: 2500)
          guard center.r > 0.3, center.a > 0.99 else {
            throw CraftError.invalid("Spot Healing benchmark failed to remove its blemish.")
          }
          samples.append([
            "kind": kind.rawValue, "brush_size": size, "repair_ms": (applied - start) * 1000,
            "regional_composite_ms": (rendered - applied) * 1000,
            "full_sdr_pack_ms": (packed - rendered) * 1000,
            "repaired_center": [center.r, center.g, center.b, center.a],
          ])
          last = probe
        }
      }
    }
    let full = try Renderer.composite(last)
    let regional = try Renderer.render(last, reusing: baseline)
    let exact = try full.rgbaData(depth: .f32) == regional.surface.rgbaData(depth: .f32)
    guard exact else {
      throw CraftError.invalid("Spot Healing regional output differs from full rendering.")
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "canvas": [6000, 4000], "depth": 16, "samples": samples,
      "regional_matches_full_float_bits": exact, "peak_resident_bytes": usage.ru_maxrss,
      "scope":
        "Native release process, two samples per brush/type. Input generation, source capture and initial cache excluded. Peak includes full-reference verification buffers. No AppKit latency, p95 or Photoshop comparison.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
  }
}
