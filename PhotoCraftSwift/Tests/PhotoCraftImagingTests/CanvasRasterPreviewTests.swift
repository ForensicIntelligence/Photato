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
