import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class IncrementalFocusRendererTests: XCTestCase {
  func testBatchedNeighborhoodsAndFixedMasksMatchCompleteCommands() throws {
    for tool in FocusTool.allCases {
      for mask in [false, true] {
        var doc = try CraftDocument(width: 96, height: 64, depth: .u16)
        var pixels = try Surface(width: 128, height: 128, depth: .u16)
        for y in 0..<128 {
          for x in 0..<128 {
            pixels.setPixel(
              x: x, y: y, Pixel(Float(x % 17) / 16, Float(y % 13) / 12, 0.7, Float((x + y) % 7) / 6)
            )
          }
        }
        doc.layers[0].content = .raster(pixels)
        doc.layers[0].x = -20
        doc.layers[0].y = -25
        doc.layers[0].affine = .rotation(6)
        if mask { doc.layers[0].mask = pixels }
        doc.layers.append(
          Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.04, 0.2))))
        doc.selection = .init(x: 10, y: 8, width: 70, height: 48)
        let id = doc.layers[0].id
        var brush = CloneBrush()
        brush.size = 17
        brush.flow = 0.25
        brush.opacity = 0.7
        var options = FocusOptions()
        options.sampleAllLayers = !mask
        var stroke = FocusStroke(
          tool: tool, options: options, brush: brush,
          points: [.init(x: 14, y: 30)], mask: mask,
          sample: mask ? nil : CloneSample(surface: try Renderer.composite(doc)))
        let renderer = try IncrementalFocusRenderer(document: doc, layerID: id, initial: stroke)
        var previous = try Renderer.render(doc)
        for i in 0..<8 {
          let points: [StrokePoint] =
            i == 0
            ? []
            : (0..<3).map { j in
              .init(
                x: 14 + Double(i * 3 + j) * 2, y: 30 + sin(Double(i * 3 + j)) * 8, pressure: 0.7)
            }
          stroke.points += points
          previous = try renderer.snapshot(appending: points, reusing: previous)
          var expected = doc
          try Command.focus(id, stroke).apply(to: &expected)
          XCTAssertEqual(previous.document, expected)
          XCTAssertNil(
            try previous.surface.changedTileBounds(comparedTo: Renderer.composite(expected)))
        }
      }
    }
  }
  func testAdmissionRejectsLockedTargetsAndExpandingStorage() throws {
    var doc = try CraftDocument(width: 64, height: 48)
    var brush = CloneBrush()
    brush.size = 9
    let stroke = FocusStroke(tool: .blur, brush: brush, points: [.init(x: 20, y: 20)])
    let id = doc.layers[0].id
    doc.layers[0].locked = true
    XCTAssertThrowsError(try IncrementalFocusRenderer(document: doc, layerID: id, initial: stroke))
    doc.layers[0].locked = false
    doc.layers[0].content = .raster(try Surface(width: 8, height: 8))
    XCTAssertFalse(IncrementalFocusRenderer.supports(document: doc, layerID: id, stroke: stroke))
    XCTAssertThrowsError(try IncrementalFocusRenderer(document: doc, layerID: id, initial: stroke))
  }
}
