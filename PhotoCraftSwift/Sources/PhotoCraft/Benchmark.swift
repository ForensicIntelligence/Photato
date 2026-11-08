import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum Benchmark {
  static func colorBalance(to url: URL) throws {
    let settings = ColorBalanceAdjustment(
      shadows: .init(cyanRed: 20, magentaGreen: -10, yellowBlue: 5),
      midtones: .init(cyanRed: -15, magentaGreen: 10, yellowBlue: 30),
      highlights: .init(magentaGreen: 5, yellowBlue: -20))
    try adjustment(.colorBalance(settings), name: "Color Balance", to: url)
  }
  static func curves(to url: URL) throws {
    try adjustment(.curves(BuiltInCurvesPreset.crossProcess.curves), name: "Curves", to: url)
  }
  static func hueSaturation(to url: URL) throws {
    var settings = HueSaturationAdjustment(master: .init(hue: 10, saturation: 20, lightness: -5))
    settings.ranges[0].values = .init(hue: 30, saturation: -60, lightness: 15)
    settings.ranges[3].values = .init(hue: -25, saturation: 40, lightness: -20)
    try adjustment(.hueSaturation(settings), name: "Hue/Saturation", to: url)
  }
  private static func adjustment(_ adjustment: Adjustment, name: String, to url: URL) throws {
    let width = 6000
    let height = 4000
    var pixels = try Surface(width: width, height: height, depth: .u16)
    pixels.mapPixels { x, y, _ in
      Pixel(Float(x) / Float(width - 1), Float(y) / Float(height - 1), Float((x + y) % 256) / 255)
    }
    var doc = try CraftDocument(width: width, height: height, depth: .u16)
    doc.layers[0].content = .raster(pixels)
    let start = ProcessInfo.processInfo.systemUptime
    do {
      var edited = doc
      try Command.applyAdjustment(doc.layers[0].id, adjustment).apply(to: &edited)
      guard edited != doc else {
        throw CraftError.invalid("\(name) did not alter the test gradient.")
      }
    }
    let applied = ProcessInfo.processInfo.systemUptime
    doc.layers.append(Layer(name: name, content: .adjustment(adjustment)))
    let output = try Renderer.composite(doc)
    let rendered = ProcessInfo.processInfo.systemUptime
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let data = try JSONSerialization.data(
      withJSONObject: [
        "pixels": width * height, "depth": "16 bit",
        "destructive\(name.replacingOccurrences(of: "/", with: ""))MS": (applied - start) * 1000,
        "adjustmentLayerCompositeMS": (rendered - applied) * 1000,
        "peakResidentBytes": usage.ru_maxrss,
        "sampleFinite": output.pixel(x: width / 2, y: height / 2).isFinite,
        "note":
          "Single dense 24 MP RGB/16 release sample with \(name). Full pixel application and complete two-layer CPU composition. Excludes UI latency; no Photoshop performance or p95 comparison.",
      ], options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
    print(String(decoding: data, as: UTF8.self))
  }
  static func levels(to url: URL) throws {
    let width = 6000
    let height = 4000
    var pixels = try Surface(width: width, height: height, depth: .u16)
    pixels.mapPixels { x, y, _ in
      Pixel(
        0.15 + Float(x) / Float(width - 1) * 0.65,
        0.2 + Float(y) / Float(height - 1) * 0.6, 0.25 + Float((x + y) % 256) / 512)
    }
    var doc = try CraftDocument(width: width, height: height, depth: .u16)
    doc.layers[0].content = .raster(pixels)
    let start = ProcessInfo.processInfo.systemUptime
    let histogram = try RGBHistogram.pixelLayer(doc.layers[0].id, in: doc)
    let analyzed = ProcessInfo.processInfo.systemUptime
    let levels = try AutoCorrection.tone.levels(from: histogram)
    let estimated = ProcessInfo.processInfo.systemUptime
    let editStart = ProcessInfo.processInfo.systemUptime
    do {
      var edited = doc
      try Command.autoCorrection(doc.layers[0].id, .tone).apply(to: &edited)
      guard edited != doc else {
        throw CraftError.invalid("Auto Tone did not alter the test gradient.")
      }
    }
    let edited = ProcessInfo.processInfo.systemUptime
    let adjustment = Layer(name: "Levels", content: .adjustment(.levels(levels)))
    doc.layers.append(adjustment)
    let inputHistogram = try Renderer.levelsHistogram(adjustment.id, in: doc)
    let finished = ProcessInfo.processInfo.systemUptime
    guard inputHistogram == histogram, histogram.samples == UInt64(width * height) else {
      throw CraftError.invalid("Adjustment input histogram differs from the opaque source.")
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let result: [String: Any] = [
      "pixels": width * height, "depth": "16 bit", "samples": histogram.samples,
      "pixelLayerHistogramMS": (analyzed - start) * 1000,
      "autoEstimatorMS": (estimated - analyzed) * 1000,
      "autoToneIncludingHistogramMS": (edited - editStart) * 1000,
      "adjustmentInputHistogramMS": (finished - edited) * 1000,
      "peakResidentBytes": usage.ru_maxrss, "inputHistogramMatches": true,
      "note":
        "Single dense 24 MP RGB/16 release sample, full-resolution counts, no UI/IPC or Photoshop performance comparison. Peak residency covers the entire benchmark.",
    ]
    let data = try JSONSerialization.data(
      withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
    print(String(decoding: data, as: UTF8.self))
  }
  static func packing(to url: URL, large: Bool = false) throws {
    let width = large ? 6000 : 1024
    let height = large ? 4000 : 1024
    var pixels = try Surface(width: width, height: height, depth: .u16)
    for y in 0..<height {
      for x in 0..<width {
        pixels.setPixel(
          x: x, y: y,
          Pixel(
            Float(x) / Float(width - 1),
            Float(y) / Float(height - 1), Float((x * 17 + y * 13) % 65536) / 65535,
            Float((x + y) % 257) / 256))
      }
    }
    var doc = try CraftDocument(width: width, height: height, depth: .u16)
    doc.layers[0].content = .raster(pixels)
    let t0 = ProcessInfo.processInfo.systemUptime
    let archive = try NativeArchive.encode(doc)
    let t1 = ProcessInfo.processInfo.systemUptime
    let decoded = try NativeArchive.decode(archive)
    let t2 = ProcessInfo.processInfo.systemUptime
    let cg = try RasterIO.cgImage(pixels)
    let t3 = ProcessInfo.processInfo.systemUptime
    let display = try RasterIO.displayImage(pixels)
    let t4 = ProcessInfo.processInfo.systemUptime
    let tiff = try ClipboardRenderer.imageData(pixels, type: .tiff)
    let t5 = ProcessInfo.processInfo.systemUptime
    let png = try ClipboardRenderer.imageData(pixels, type: .png)
    let t6 = ProcessInfo.processInfo.systemUptime
    guard decoded == doc else {
      throw CraftError.invalid("Packed archive changed document samples.")
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "pixels": width * height, "width": width, "height": height, "depth": "16 bit",
      "archiveEncodeMS": (t1 - t0) * 1000, "archiveDecodeMS": (t2 - t1) * 1000,
      "floatImageMS": (t3 - t2) * 1000, "displayImageMS": (t4 - t3) * 1000,
      "tiffMS": (t5 - t4) * 1000, "pngMS": (t6 - t5) * 1000,
      "archiveBytes": archive.count, "tiffBytes": tiff.count, "pngBytes": png.count,
      "peakResidentBytes": usage.ru_maxrss, "exact": true,
      "imageWidths": [cg.width, display.width],
      "note":
        "Single dense gradient/alpha release sample; native archive and image packing measured separately. Peak resident bytes cover this whole process, not per-operation peaks. Not a p95 or Photoshop equivalence qualification.",
    ]
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
    print(String(decoding: data, as: UTF8.self))
  }

  static func clipboard(to url: URL) throws {
    var source = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    source.layers[0].content = .raster(
      try Surface(width: 6000, height: 4000, depth: .u16, fill: Pixel(0.2, 0.4, 0.8, 0.5)))
    let start = ProcessInfo.processInfo.systemUptime
    let content = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id])
    let copied = ProcessInfo.processInfo.systemUptime
    let representations = try ClipboardRepresentations(content)
    guard let tiff = representations.tiff, let png = representations.png else {
      throw CraftError.unavailable("This clipboard benchmark requires TIFF and PNG representations.")
    }
    let encoded = ProcessInfo.processInfo.systemUptime
    let decoded = try ClipboardContent.decode(representations.native)
    var target = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    try Command.paste(decoded, .inPlace, nil).apply(to: &target)
    let pasted = ProcessInfo.processInfo.systemUptime
    guard target.layers.last?.content == source.layers[0].content else {
      throw CraftError.invalid("Clipboard benchmark changed the pixels.")
    }
    let report: [String: Any] = [
      "canvas": "6000 × 4000", "megapixels": 24, "depth": "16 bit",
      "layerCopyMS": (copied - start) * 1000,
      "nativeTIFFPNGEncodingMS": (encoded - copied) * 1000,
      "nativeDecodeAndPasteMS": (pasted - encoded) * 1000,
      "nativeBytes": representations.native.count, "tiffBytes": tiff.count,
      "pngBytes": png.count, "nativePixelsExact": true,
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "note":
        "Single release sample of a constant-color sparse layer. Includes all three transfer encodings, excludes system pasteboard IPC. Dense/selection/merged copies and p95/peak-memory budgets remain unqualified.",
    ]
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
    print(String(decoding: data, as: UTF8.self))
  }

  static func masks(to url: URL) throws {
    var document = try CraftDocument(width: 6000, height: 4000, depth: .u16)
    let id = document.layers[0].id
    document.layers[0].content = .raster(
      try Surface(width: 6000, height: 4000, depth: .u16, fill: Pixel(0.2, 0.4, 0.8, 0.5)))
    document.layers[0].mask = try Surface(
      width: 6000, height: 4000, depth: .u16, fill: Pixel(0.4, 0.4, 0.4))
    let applyStart = ProcessInfo.processInfo.systemUptime
    try Command.applyMask(id).apply(to: &document)
    let applyMS = (ProcessInfo.processInfo.systemUptime - applyStart) * 1000
    let appliedBytes = document.estimatedBytes
    let splitStart = ProcessInfo.processInfo.systemUptime
    try Command.createMask(id, .fromTransparency).apply(to: &document)
    let splitMS = (ProcessInfo.processInfo.systemUptime - splitStart) * 1000
    let alpha = document.layers[0].mask?.pixel(x: 3000, y: 2000).r ?? -1
    guard abs(alpha - 0.2) < 0.00002 else {
      throw CraftError.invalid("Mask benchmark result differs.")
    }
    let report: [String: Any] = [
      "canvas": "6000 × 4000", "megapixels": 24, "depth": "16 bit",
      "applyMaskMS": applyMS, "fromTransparencyMS": splitMS,
      "appliedDocumentMiB": Double(appliedBytes) / 1_048_576,
      "splitDocumentMiB": Double(document.estimatedBytes) / 1_048_576,
      "resultAlpha": alpha, "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "note":
        "Single release sample; constant RGB and fractional alpha/mask. No feather or affine transform. Not a p95 qualification.",
    ]
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
    print(String(decoding: data, as: UTF8.self))
  }
  static func run(to url: URL) throws {
    let width = 6000
    let height = 4000
    var document = try CraftDocument(width: width, height: height, depth: .u16)
    let initial = ProcessInfo.processInfo.systemUptime
    var raster = try Surface(width: width, height: height, depth: .u16)
    var brush = Brush()
    brush.size = 60
    let brushStart = ProcessInfo.processInfo.systemUptime
    try Painter.stroke(
      surface: &raster, points: [StrokePoint(x: 3000, y: 2000), StrokePoint(x: 3200, y: 2200)],
      brush: brush)
    let brushMS = (ProcessInfo.processInfo.systemUptime - brushStart) * 1000
    document.layers.append(Layer(name: "Paint", content: .raster(raster)))
    let renderStart = ProcessInfo.processInfo.systemUptime
    let composite = try Renderer.composite(document)
    let renderMS = (ProcessInfo.processInfo.systemUptime - renderStart) * 1000
    let center = composite.pixel(x: 3000, y: 2000)
    let rotateStart = ProcessInfo.processInfo.systemUptime
    let rotated = try RasterGeometry.render(
      composite, transform: CanvasTurn.clockwise.transform(width: width, height: height),
      bounds: IntRect(x: 0, y: 0, width: height, height: width), method: .nearest)
    let rotateMS = (ProcessInfo.processInfo.systemUptime - rotateStart) * 1000
    let resizeStart = ProcessInfo.processInfo.systemUptime
    let resized = try RasterGeometry.render(
      composite, transform: .scale(0.5, 0.5),
      bounds: IntRect(x: 0, y: 0, width: width / 2, height: height / 2), method: .bicubic,
      clampEdges: true)
    let resizeMS = (ProcessInfo.processInfo.systemUptime - resizeStart) * 1000
    let report: [String: Any] = [
      "canvas": "6000 × 4000", "megapixels": 24, "depth": "16 bit",
      "renderer": "Swift CPU reference",
      "brushStrokeMS": brushMS, "fullCompositeMS": renderMS,
      "rotate24MPMS": rotateMS, "bicubic24MPTo6MPMS": resizeMS,
      "geometryOutputSizes": [
        "\(rotated.width)x\(rotated.height)", "\(resized.width)x\(resized.height)",
      ],
      "compositeAllocatedMiB": Double(composite.allocatedBytes) / 1_048_576,
      "centerPixel": [center.r, center.g, center.b, center.a],
      "wallMS": (ProcessInfo.processInfo.systemUptime - initial) * 1000,
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "note":
        "Single release-build sample, not a p95 budget certification. Large-canvas acceleration is still pending.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: url, options: .atomic)
    print(
      String(
        data: try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted),
        encoding: .utf8) ?? "Benchmark complete")
  }
}
