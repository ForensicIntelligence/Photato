import CryptoKit
import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Benchmark {
  static func patternFill(to url: URL) throws {
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    var pixels = try Surface(width: 6000, height: 4000, depth: .u16)
    for y in 0..<4000 {
      for x in 0..<6000 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x) / 6000, Float(y) / 4000, 0.4))
      }
    }
    document.layers[0].content = .raster(pixels)
    let pattern = try PatternPresets.make()[4]
    var layer = Layer(
      name: "Pattern Fill", content: .patternFill(PatternFill(patternID: pattern.id)))
    layer.opacity = 0.75
    try Command.addPatternFill(layer, pattern, true).apply(to: &document)
    let baseline = try Renderer.render(document)
    let pickingStart = CFAbsoluteTimeGetCurrent()
    for i in 0..<100 {
      let pixel = try Renderer.patternPixel(
        PatternFill(patternID: pattern.id), in: document,
        x: i * 59, y: i * 39)
      guard pixel.a == 1 else { throw CraftError.invalid("Pattern picking benchmark mismatch.") }
    }
    let pickingMilliseconds = (CFAbsoluteTimeGetCurrent() - pickingStart) * 1000
    var samples: [[String: Any]] = []
    for i in 0..<2 {
      var fill = PatternFill(patternID: pattern.id)
      fill.placement.scale = 137
      fill.placement.angle = Float(17 + i * 10)
      var probe = document
      let start = CFAbsoluteTimeGetCurrent()
      try Command.setPatternFill(layer.id, fill, nil).apply(to: &probe)
      let changed = CFAbsoluteTimeGetCurrent()
      let snapshot = try Renderer.render(probe, reusing: baseline)
      let rendered = CFAbsoluteTimeGetCurrent()
      _ = try RasterIO.displayImage(snapshot.surface)
      let packed = CFAbsoluteTimeGetCurrent()
      let full = try Renderer.composite(probe)
      let exact = try full.rgbaData(depth: .f32) == snapshot.surface.rgbaData(depth: .f32)
      guard exact else {
        throw CraftError.invalid("Pattern parameter preview differs from full render.")
      }
      probe.layers[1].mask?.setPixel(x: 3000, y: 2000, .black)
      let maskStart = CFAbsoluteTimeGetCurrent()
      let regional = try Renderer.render(probe, reusing: snapshot)
      let maskRendered = CFAbsoluteTimeGetCurrent()
      let regionExact =
        try Renderer.composite(probe).rgbaData(depth: .f32)
        == regional.surface.rgbaData(depth: .f32)
      guard regionExact, case .region = regional.update else {
        throw CraftError.invalid("Pattern mask regional render mismatch.")
      }
      samples.append([
        "parameter_command_ms": (changed - start) * 1000,
        "parameter_full_composite_ms": (rendered - changed) * 1000,
        "full_sdr_pack_ms": (packed - rendered) * 1000,
        "mask_regional_composite_ms": (maskRendered - maskStart) * 1000,
        "parameter_matches_full_float_bits": exact,
        "mask_regional_matches_full_float_bits": regionExact,
      ])
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "canvas": [6000, 4000], "depth": 16, "samples": samples,
      "direct_content_pixel_queries": 100,
      "direct_content_pixel_queries_ms": pickingMilliseconds,
      "peak_resident_bytes": usage.ru_maxrss,
      "scope":
        "Native release process; dense 24 MP backdrop and editable Bricks pattern at 75% opacity. Scale/angle changes and one mask-pixel edit. Two samples, not p95; setup excluded; peak includes full-reference buffers. No live AppKit or Photoshop performance comparison.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url)
  }
  static func inspectPatterns(at url: URL, to output: URL) throws {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let start = CFAbsoluteTimeGetCurrent()
    let library = try PATCodec.readLibrary(data)
    let patterns = library.patterns
    let loaded = CFAbsoluteTimeGetCurrent()
    let encoded = try PATCodec.write(patterns)
    let decoded = try PATCodec.read(encoded)
    guard decoded == patterns else { throw CraftError.invalid("PAT semantic round trip failed.") }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "path": url.path,
      "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      "bytes": data.count, "count": patterns.count, "read_ms": (loaded - start) * 1000,
      "native_pat_round_trip_exact": true, "peak_resident_bytes": usage.ru_maxrss,
      "imported_folders_flattened": library.foldersFlattened,
      "identical_duplicate_records_merged": library.duplicateRecordsMerged,
      "source_record_count": patterns.count + library.duplicateRecordsMerged,
      "patterns": patterns.map {
        [
          "id": $0.id, "name": $0.displayName,
          "width": $0.surface.width, "height": $0.surface.height,
          "depth": $0.surface.depth.rawValue,
        ] as [String: Any]
      },
      "scope":
        "Read-only installed preset inspection. Native PAT round trip compares pattern identity, names and every stored sample; imported presets are not bundled or redistributed. Live Photoshop loading of native exports is not verified.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: output)
  }
}
