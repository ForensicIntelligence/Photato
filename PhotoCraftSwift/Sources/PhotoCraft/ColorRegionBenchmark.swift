import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Benchmark {
  static func colorRegion(to url: URL, pattern: Bool = false) throws {
    let fillPattern = pattern ? try PatternPresets.make()[4] : nil
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    var pixels = try Surface(width: 6000, height: 4000, depth: .u16)
    for y in 0..<4000 {
      for x in 0..<6000 {
        pixels.setPixel(x: x, y: y, Pixel(x < 3000 ? 0.8 : 0.2, 0.4, 0.6))
      }
    }
    document.layers[0].content = .raster(pixels)
    let baseline = try Renderer.render(document)
    var samples: [[String: Any]] = []
    for _ in 0..<2 {
      let source = CloneSample(surface: pixels)
      let start = CFAbsoluteTimeGetCurrent()
      let selection = try ColorRegion.selection(
        source: source, width: 6000, height: 4000,
        seed: .init(1000, 2000), options: ColorMatchOptions())
      let selected = CFAbsoluteTimeGetCurrent()
      guard selection.coverage(x: 1000, y: 2000) == 1,
        selection.coverage(x: 4500, y: 2000) == 0
      else {
        throw CraftError.invalid("Incorrect benchmark selection.")
      }
      var probe = document
      let fill = BucketFill(
        source: source, seed: .init(1000, 2000), color: Pixel(0.2, 0.7, 0.4), pattern: fillPattern)
      try Command.paintBucket(probe.layers[0].id, fill).apply(to: &probe)
      let painted = CFAbsoluteTimeGetCurrent()
      let snapshot = try Renderer.render(probe, reusing: baseline)
      let rendered = CFAbsoluteTimeGetCurrent()
      _ = try RasterIO.displayImage(snapshot.surface)
      let packed = CFAbsoluteTimeGetCurrent()
      let full = try Renderer.composite(probe)
      let exact = try full.rgbaData(depth: .f32) == snapshot.surface.rgbaData(depth: .f32)
      guard exact, probe != document else {
        throw CraftError.invalid("Paint Bucket benchmark render mismatch or no edit.")
      }
      samples.append([
        "wand_ms": (selected - start) * 1000,
        "bucket_including_matching_ms": (painted - selected) * 1000,
        "regional_composite_ms": (rendered - painted) * 1000,
        "full_sdr_pack_ms": (packed - rendered) * 1000,
        "regional_matches_full_float_bits": exact,
      ])
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "canvas": [6000, 4000], "depth": 16, "tolerance": 32,
      "contiguous": true, "anti_alias": true, "sample_all_layers": false,
      "fill_source": pattern ? "Pattern: Bricks at 100%, canvas origin" : "Foreground color",
      "samples": samples, "peak_resident_bytes": usage.ru_maxrss,
      "scope":
        "Native release process; dense 24 MP image, left half filled. Two samples, not p95. Input/cache creation and selection outline generation excluded. Peak includes full-reference buffers. No live AppKit or Photoshop comparison.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
  }
}
