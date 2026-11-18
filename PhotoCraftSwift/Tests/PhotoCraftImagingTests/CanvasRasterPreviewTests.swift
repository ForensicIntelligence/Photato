import CoreGraphics
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class CanvasRasterPreviewTests: XCTestCase {
  func rendered(_ preview: CanvasRasterPreview, scale: Double = 1) throws -> Data {
    let width = Int(ceil(Double(preview.base.width) * scale)), height = Int(ceil(Double(preview.base.height) * scale))
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: Double(height)); context.scaleBy(x: scale, y: -scale)
    context.interpolationQuality = scale >= 1 ? .none : .high
    preview.draw(in: context)
    return Data(bytes: context.data!, count: width * height * 4)
  }
  func testPatchesMatchFullDisplayIncludingEraseTileEdgesAndFractionalZoom() throws {
    var doc = try CraftDocument(width: 385, height: 257)
    var pixels = try Surface(width: 385, height: 257, fill: Pixel(0.1, 0.5, 0.8, 0.6))
    doc.layers[0].content = .raster(pixels)
    var snapshot = try Renderer.render(doc)
    var display = CanvasRasterPreview(base: try ColorManagement.displayImage(snapshot.surface, in: doc))
    for i in 0..<4 {
      for y in 118..<140 { for x in (120 + i * 5)..<(140 + i * 5) {
        pixels.setPixel(x: x, y: y, i % 2 == 0 ? .clear : Pixel(0.9, 0.2, 0.4, 0.8))
      } }
      doc.layers[0].content = .raster(pixels)
      snapshot = try Renderer.render(doc, reusing: snapshot)
      display = try display.updating(snapshot)
      let full = CanvasRasterPreview(base: try ColorManagement.displayImage(snapshot.surface, in: doc))
      XCTAssertLessThan(display.repackedPixels, doc.width * doc.height)
      for scale in [1.0, 2.0, 0.75, 0.4, 0.25, 1.25] {
        let actual = try rendered(display, scale: scale), expected = try rendered(full, scale: scale)
        let maxDelta = zip(actual, expected).map { abs(Int($0) - Int($1)) }.max()!
        XCTAssertLessThanOrEqual(maxDelta, 0, "scale \(scale), frame \(i)")
      }
    }
    let retained = display
    let saved = try rendered(display)
    let unchanged = try display.updating(Renderer.render(doc, reusing: snapshot))
    XCTAssertEqual(try rendered(unchanged), saved)
    doc.layers[0].opacity = 0.4
    let reset = try display.updating(Renderer.render(doc, reusing: snapshot))
    XCTAssertEqual(reset.repackedPixels, doc.width * doc.height)
    XCTAssertEqual(try rendered(retained), saved, "New frames must not mutate a retained image")
  }
}

extension CanvasRasterPreviewTests {
  func testRegionalDisplayPacksMappedSamplesAndPreservesManagedColor() throws {
    let cases: [(PixelDepth, SurfaceColorEncoding, CFString?)] = [
      (.u8, .sRGB, nil), (.u16, .sRGB, nil), (.f32, .linearRGB, nil),
      (.u8, .sRGB, CGColorSpace.displayP3),
    ]
    for (depth, encoding, profileName) in cases {
      var document = try CraftDocument(width: 259, height: 201, depth: depth)
      if let profileName {
        document.workingICC = try XCTUnwrap(CGColorSpace(name: profileName)?.copyICCData()) as Data
      }
      var source = try Surface(width: document.width, height: document.height, depth: depth,
        fill: Pixel(0.81, 0.26, 0.37, 0.64), colorEncoding: encoding)
      source.setPixel(x: 190, y: 122, Pixel(0.12, 0.61, 0.79, 0.47))
      source = try source.spillingTiles(to: RasterTileStore())
      document.layers[0].content = .raster(source)
      let before = try Renderer.render(document)
      let preview = try CanvasRasterPreview(base: ColorManagement.displayImage(before.surface, in: document)).scaled(to: 0.5)
      let retained = try XCTUnwrap(preview.base.dataProvider?.data) as Data
      source.setPixel(x: 191, y: 129, Pixel(0.21, 0.88, 0.42, 0.503))
      source.setPixel(x: 254, y: 191, .clear)
      if depth == .f32 { source.setLinearPixel(x: 256, y: 198, Pixel(-0.0, 3.4, -0.22, 0.63)) }
      document.layers[0].content = .raster(source)
      let after = try Renderer.render(document, reusing: before)
      guard case .region = after.update else { return XCTFail("Expected partial display damage") }
      let patched = try preview.updating(after, scale: 0.5)
      let full = try CanvasRasterPreview(base: ColorManagement.displayImage(after.surface, in: document)).scaled(to: 0.5)
      XCTAssertEqual(patched.base.dataProvider?.data as Data?, full.base.dataProvider?.data as Data?)
      XCTAssertEqual(patched.presentation?.bytes, full.presentation?.bytes)
      XCTAssertEqual(preview.base.dataProvider?.data as Data?, retained)
      XCTAssertLessThan(patched.repackedPixels, source.width * source.height)
    }
  }

  func testWholePixelBoxesMatchIndependentAlphaWeightedBytes() throws {
    let cases: [(Int, Int, Double)] = [(96, 48, 0.125), (12, 10, 0.16), (384, 256, 0.0001)]
    for (width, height, scale) in cases {
      var source = Data()
      for index in 0..<(width * height) {
        let alpha: UInt8 = index % width < width / 4 ? 0 : UInt8((index * 53) % 256)
        source.append(contentsOf: [UInt8((index * 61) % 256), UInt8((index * 13) % 256),
          UInt8((index * 23) % 256), alpha])
      }
      let provider = try XCTUnwrap(CGDataProvider(data: source as CFData))
      let base = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: width * 4, space: RasterIO.colorSpace(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .relativeColorimetric))
      let view = try XCTUnwrap(CanvasRasterPreview(base: base).scaled(to: scale).presentation)
      let dx = width / view.image.width, dy = height / view.image.height
      XCTAssertEqual(view.image.width * dx, width)
      XCTAssertEqual(view.image.height * dy, height)
      var expected = Data()
      for y in 0..<view.image.height {
        for x in 0..<view.image.width {
          var rgb = [Int](repeating: 0, count: 3)
          var alpha = 0
          for iy in (y * dy)..<((y + 1) * dy) {
            for ix in (x * dx)..<((x + 1) * dx) {
              let i = (iy * width + ix) * 4, coverage = Int(source[i + 3])
              alpha += coverage
              for channel in rgb.indices { rgb[channel] += Int(source[i + channel]) * coverage }
            }
          }
          let colors = rgb.map { UInt8(alpha == 0 ? 0 : (2 * $0 + alpha) / (2 * alpha)) }
          expected.append(contentsOf: colors)
          expected.append(UInt8((2 * alpha + dx * dy) / (2 * dx * dy)))
        }
      }
      XCTAssertEqual(view.bytes, expected)
    }
  }

  func testReducedRegionalDisplayMatchesFullAndPreservesAlpha() throws {
    var doc = try CraftDocument(width: 385, height: 257)
    var pixels = try Surface(width: 385, height: 257, fill: Pixel(0.1, 0.5, 0.8, 0.6))
    doc.layers[0].content = .raster(pixels)
    for scale in [0.1, 0.4, 0.7683] {
      var snapshot = try Renderer.render(doc)
      var display = try CanvasRasterPreview(base: ColorManagement.displayImage(snapshot.surface, in: doc)).scaled(to: scale)
      let retained = display.presentation!.image.dataProvider!.data! as Data
      let first = display
      for i in 0..<4 {
        for y in 118..<140 { for x in 120..<150 { pixels.setPixel(x: x, y: y, i % 2 == 0 ? .clear : .black) } }
        doc.layers[0].content = .raster(pixels)
        snapshot = try Renderer.render(doc, reusing: snapshot)
        display = try display.updating(snapshot, scale: scale)
        let full = try CanvasRasterPreview(base: ColorManagement.displayImage(snapshot.surface, in: doc)).scaled(to: scale)
        XCTAssertEqual(display.presentation!.image.dataProvider!.data! as Data, full.presentation!.image.dataProvider!.data! as Data)
      }
      XCTAssertEqual(first.presentation!.image.dataProvider!.data! as Data, retained)
    }
    // Independent analytic 2x2 →1 sample: opaque red + transparent hidden blue.
    var tiny = try CraftDocument(width: 2, height: 2)
    var source = try Surface(width: 2, height: 2, fill: Pixel(0, 0, 1, 0))
    source.setPixel(x: 0, y: 0, Pixel(1, 0, 0)); tiny.layers[0].content = .raster(source)
    let reduced = try CanvasRasterPreview(base: ColorManagement.displayImage(Renderer.composite(tiny), in: tiny)).scaled(to: 0.5)
    XCTAssertEqual(reduced.presentation!.image.dataProvider!.data! as Data, Data([255, 0, 0, 64]))
  }
  func testSealedBrushRendererMatchesValidatedCompositionAndProtection() throws {
    var doc = try CraftDocument(width: 96, height: 72)
    doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.1, 0.2))))
    let id = doc.layers[0].id
    var brush = Brush(); brush.settings = .init(); brush.size = 15; brush.color = Pixel(1, 0, 0)
    let renderer = try IncrementalBrushRenderer(document: doc, layerID: id, brush: brush)
    var previous = try Renderer.render(doc), points: [StrokePoint] = []
    for i in 0..<10 {
      let point = StrokePoint(x: 10 + Double(i) * 5, y: 35, time: Double(i))
      points.append(point); previous = try renderer.append([point], reusing: previous)
      var expected = doc; try Command.stroke(id, points, brush).apply(to: &expected)
      XCTAssertEqual(previous.document, expected)
      XCTAssertNil(try previous.surface.changedTileBounds(comparedTo: Renderer.composite(expected)))
    }
    doc.layers[0].protection = [.image]
    XCTAssertThrowsError(try IncrementalBrushRenderer(document: doc, layerID: id, brush: brush))
  }
}
