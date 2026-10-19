import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Benchmark {
  static func expandedClone(to url: URL) throws {
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    var original = try Surface(width: 5600, height: 3600, depth: .u16)
    for y in 0..<3600 {
      for x in 0..<5600 {
        original.setPixel(
          x: x, y: y, Pixel(Float(x) / 5599, Float(y) / 3599, Float((x + y) % 256) / 255))
      }
    }
    document.layers[0].content = .raster(original)
    document.layers[0].x = 200
    document.layers[0].y = 200
    let id = document.layers[0].id
    var brush = CloneBrush()
    brush.size = 120
    brush.hardness = 1
    brush.pressureSize = false
    let sample = CloneSample(surface: original, transform: .translation(200, 200))
    let stroke = CloneStroke(
      source: sample, mapping: .init(source: .init(1000.5, 1000.5), anchor: .init(50.5, 50.5)),
      brush: brush, points: [.init(x: 50.5, y: 50.5), .init(x: 170.5, y: 130.5)])
    let start = CFAbsoluteTimeGetCurrent()
    try Command.cloneStamp(id, stroke).apply(to: &document)
    let applied = CFAbsoluteTimeGetCurrent()
    let composite = try Renderer.composite(document)
    let rendered = CFAbsoluteTimeGetCurrent()
    let display = try RasterIO.displayImage(composite)
    let displayed = CFAbsoluteTimeGetCurrent()
    guard case .raster(let output) = document.layers[0].content else {
      throw CraftError.invalid("Missing benchmark raster.")
    }
    let layer = document.layers[0]
    let originalPreserved = output.pixel(x: 1000 - layer.x, y: 1000 - layer.y).hasSameBits(
      as: original.pixel(x: 800, y: 800))
    let sourceCopied = output.pixel(x: 50 - layer.x, y: 50 - layer.y).hasSameBits(
      as: original.pixel(x: 800, y: 800))
    guard originalPreserved, sourceCopied, display.width == 6000 else {
      throw CraftError.invalid("Expanded clone verification failed.")
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "document_pixels": 24_000_000, "original_layer_pixels": 20_160_000, "depth": 16,
      "original_layer_bounds": [200, 200, 5600, 3600],
      "expanded_layer_bounds": [layer.x, layer.y, output.width, output.height],
      "expand_and_paint_ms": (applied - start) * 1000,
      "full_composite_ms": (rendered - applied) * 1000,
      "display_pack_ms": (displayed - rendered) * 1000,
      "peak_resident_bytes": usage.ru_maxrss,
      "original_probe_bits_preserved": originalPreserved, "clone_probe_bits_exact": sourceCopied,
      "scope":
        "One dense 20.16 MP cropped RGB/16 layer in a 24 MP document. Reframes storage and paints toward the canvas edge, then fully composes and packs SDR output. Geometry changes currently require full preview composition. Two exact pixel probes supplement the small exhaustive regression cases. Excludes AppKit, p95, Photoshop equivalence and history memory behavior.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
    print("Expanded Clone Stamp benchmark: \(url.path)")
  }
  static func cloneStamp(to url: URL) throws {
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    var pixels = try Surface(width: 6000, height: 4000, depth: .u16)
    for y in 0..<4000 {
      for x in 0..<6000 {
        pixels.setPixel(
          x: x, y: y, Pixel(Float(x) / 5999, Float(y) / 3999, Float((x + y) % 256) / 255))
      }
    }
    document.layers[0].content = .raster(pixels)
    let initialStart = CFAbsoluteTimeGetCurrent()
    let baseline = try Renderer.render(document)
    let initialMS = (CFAbsoluteTimeGetCurrent() - initialStart) * 1000
    let id = document.layers[0].id
    var brush = CloneBrush()
    brush.size = 120
    brush.hardness = 0.8
    brush.flow = 0.5
    let start = CFAbsoluteTimeGetCurrent()
    let source = try Renderer.cloneSample(in: document, layerID: id, sampling: .current)
    let sampled = CFAbsoluteTimeGetCurrent()
    let stroke = CloneStroke(
      source: source, mapping: .init(source: .init(1000.5, 1000.5), anchor: .init(3000.5, 2000.5)),
      brush: brush,
      points: (0..<21).map { .init(x: 3000.5 + Double($0) * 20, y: 2000.5 + Double($0) * 8) })
    try Command.cloneStamp(id, stroke).apply(to: &document)
    let applied = CFAbsoluteTimeGetCurrent()
    let composite = try Renderer.composite(document)
    let rendered = CFAbsoluteTimeGetCurrent()
    var incrementalMS: [Double] = []
    var displayMS: [Double] = []
    var cached = baseline
    for _ in 0..<5 {
      let tick = CFAbsoluteTimeGetCurrent()
      cached = try Renderer.render(document, reusing: baseline)
      let composed = CFAbsoluteTimeGetCurrent()
      let image = try RasterIO.displayImage(cached.surface)
      let displayed = CFAbsoluteTimeGetCurrent()
      guard image.width == document.width else {
        throw CraftError.invalid("Invalid benchmark image.")
      }
      incrementalMS.append((composed - tick) * 1000)
      displayMS.append((displayed - composed) * 1000)
    }
    let exact = try cached.surface.changedTileBounds(comparedTo: composite) == nil
    guard exact else {
      throw CraftError.invalid("Incremental render differs from full composition.")
    }
    guard case .region(let region) = cached.update else {
      throw CraftError.invalid("Benchmark did not exercise regional rendering.")
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "pixels": 24_000_000, "depth": 16, "brush_size": brush.size,
      "input_points": stroke.points.count,
      "sample_ms": (sampled - start) * 1000, "apply_ms": (applied - sampled) * 1000,
      "composite_ms": (rendered - applied) * 1000, "peak_resident_bytes": usage.ru_maxrss,
      "initial_cache_ms": initialMS,
      "incremental_ms": incrementalMS, "incremental_median_ms": incrementalMS.sorted()[2],
      "full_display_pack_ms": displayMS, "display_pack_median_ms": displayMS.sorted()[2],
      "region": [region.x, region.y, region.width, region.height],
      "incremental_matches_full_float_bits": exact,
      "composite_tiles": composite.tileCount,
      "scope":
        "One dense 24 MP release document and stroke; current-layer source, localized round brush. Full composition once; five incremental updates from the same immutable baseline and five full SDR display packs. Includes validation and damage detection. Exact native Float32 composite comparison passes. Excludes AppKit events, overlays, UI latency, p95 and Photoshop comparison.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
    print("Clone Stamp benchmark: \(url.path)")
  }
}
