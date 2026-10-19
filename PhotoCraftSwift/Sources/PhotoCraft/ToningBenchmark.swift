import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Benchmark {
  static func toning(to url: URL) throws {
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    var pixels = try Surface(width: 6000, height: 4000, depth: .u16)
    for y in 0..<4000 {
      for x in 0..<6000 {
        pixels.setPixel(x: x, y: y, Pixel(0.2 + Float(x) / 12000, 0.2 + Float(y) / 8000, 0.4))
      }
    }
    document.layers[0].content = .raster(pixels)
    let baseline = try Renderer.render(document)
    var samples: [[String: Any]] = []
    for kind in ToningTool.allCases {
      for _ in 0..<2 {
        var probe = document
        var brush = CloneBrush()
        brush.size = 300
        brush.hardness = 0.8
        brush.pressureSize = false
        let stroke = ToningStroke(
          tool: kind, brush: brush, points: [.init(x: 3000, y: 2000), .init(x: 3600, y: 2200)])
        let start = CFAbsoluteTimeGetCurrent()
        try Command.toning(probe.layers[0].id, stroke).apply(to: &probe)
        let applied = CFAbsoluteTimeGetCurrent()
        let snapshot = try Renderer.render(probe, reusing: baseline)
        let rendered = CFAbsoluteTimeGetCurrent()
        _ = try RasterIO.displayImage(snapshot.surface)
        let packed = CFAbsoluteTimeGetCurrent()
        let full = try Renderer.composite(probe)
        let exact = try full.rgbaData(depth: .f32) == snapshot.surface.rgbaData(depth: .f32)
        guard exact,
          snapshot.surface.pixel(x: 3300, y: 2100) != baseline.surface.pixel(x: 3300, y: 2100)
        else {
          throw CraftError.invalid("Toning benchmark result failed verification.")
        }
        samples.append([
          "tool": kind.rawValue, "edit_ms": (applied - start) * 1000,
          "regional_composite_ms": (rendered - applied) * 1000,
          "full_sdr_pack_ms": (packed - rendered) * 1000,
          "regional_matches_full_float_bits": exact,
        ])
      }
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "canvas": [6000, 4000], "depth": 16, "brush_size": 300,
      "stroke_points": [[3000, 2000], [3600, 2200]], "samples": samples,
      "peak_resident_bytes": usage.ru_maxrss,
      "scope":
        "Native release process; two samples per tool. Dense input and initial render excluded; peak includes full-reference buffers. No AppKit latency, p95 or Photoshop comparison.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
  }
}
