import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class IncrementalToningRendererTests: XCTestCase {
  func testCroppedTransformedPixelsAndFixedMasksMatchCompleteCommands() throws {
    for tool in ToningTool.allCases { for mask in [false, true] {
      var doc = try CraftDocument(width: 96, height: 64, depth: .u16)
      let pixels = try Surface(width: mask ? 128 : 42, height: mask ? 128 : 32, depth: .u16, fill: Pixel(0.3, 0.6, 0.7, 0.7))
      doc.layers[0].content = .raster(pixels)
      if mask { doc.layers[0].mask = pixels }
      else { doc.layers[0].x = 18; doc.layers[0].y = 12; doc.layers[0].affine = .rotation(12) }
      doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.04, 0.2))))
      doc.selection = .init(x: 10, y: 8, width: 70, height: 48)
      let id = doc.layers[0].id
      var brush = CloneBrush(); brush.size = 17; brush.flow = 0.25; brush.opacity = 0.7
      var stroke = ToningStroke(tool: tool, brush: brush, points: [.init(x: 14, y: 30)], mask: mask)
      let renderer = try IncrementalToningRenderer(document: doc, layerID: id, initial: stroke)
      var previous = try Renderer.render(doc)
      for i in 0..<8 {
        let points: [StrokePoint] = i == 0 ? [] : (0..<3).map { j in .init(x: 14 + Double(i*3+j)*2, y: 30 + sin(Double(i*3+j))*8, pressure: 0.7) }
        stroke.points += points
        previous = try renderer.snapshot(appending: points, reusing: previous)
        var expected = doc; try Command.toning(id, stroke).apply(to: &expected)
        XCTAssertEqual(previous.document, expected)
        XCTAssertNil(try previous.surface.changedTileBounds(comparedTo: Renderer.composite(expected)))
      }
    }}
  }
  func testAdmissionRejectsLockedTargetsAndExpandableMasks() throws {
    var doc = try CraftDocument(width: 64, height: 48)
    var stroke = ToningStroke(tool: .burn, brush: CloneBrush(), points: [.init(x: 9, y: 9)])
    let id = doc.layers[0].id
    doc.layers[0].locked = true
    XCTAssertThrowsError(try IncrementalToningRenderer(document: doc, layerID: id, initial: stroke))
    doc.layers[0].locked = false; doc.layers[0].mask = try Surface(width: 8, height: 8, fill: .white)
    stroke.mask = true
    XCTAssertFalse(IncrementalToningRenderer.supports(document: doc, layerID: id, stroke: stroke))
    XCTAssertThrowsError(try IncrementalToningRenderer(document: doc, layerID: id, initial: stroke))
  }
}
