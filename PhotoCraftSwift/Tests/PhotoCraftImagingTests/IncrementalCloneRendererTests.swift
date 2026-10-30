import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class IncrementalCloneRendererTests: XCTestCase {
  func testLayeredSelectionAndMaskPreviewMatchCompleteCommands() throws {
    for mask in [false, true] {
      var doc = try CraftDocument(width: 96, height: 64, depth: .u16)
      let pixels = try Surface(width: 96, height: 64, depth: .u16, fill: Pixel(0.3, 0.4, 0.7, 0.7))
      doc.layers[0].content = .raster(pixels)
      if mask { doc.layers[0].mask = try Surface(width: 96, height: 64, depth: .u16, fill: .white) }
      doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.04, 0.2))))
      doc.selection = .init(x: 10, y: 8, width: 70, height: 48)
      let id = doc.layers[0].id
      var brush = CloneBrush(); brush.size = 17; brush.flow = 0.25; brush.opacity = 0.7
      var stroke = try CloneStroke(source: .init(surface: Surface(width: 96, height: 64, depth: .u16, fill: Pixel(0.7, 0.2, 0.1))), mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: brush, points: [.init(x: 14, y: 30)], mask: mask)
      let renderer = try IncrementalCloneRenderer(document: doc, layerID: id, initial: stroke)
      var previous = try Renderer.render(doc)
      for i in 0..<12 {
        let points: [StrokePoint] = i == 0 ? [] : [.init(x: 14 + Double(i)*5, y: 30 + sin(Double(i))*8)]
        stroke.points += points
        previous = try renderer.snapshot(appending: points, reusing: previous)
        var expected = doc; try Command.cloneStamp(id, stroke).apply(to: &expected)
        XCTAssertEqual(previous.document, expected)
        XCTAssertEqual(previous.surface, try Renderer.composite(expected))
      }
    }
  }
  func testExpandedAndLockedTargetsCannotBypassCommandAdmission() throws {
    var doc = try CraftDocument(width: 64, height: 48)
    var brush = CloneBrush(); brush.size = 3
    let stroke = CloneStroke(source: .init(surface: try Surface(width: 64, height: 48, fill: .white)), mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: brush, points: [.init(x: 9, y: 9)])
    let id = doc.layers[0].id
    doc.layers[0].locked = true
    XCTAssertThrowsError(try IncrementalCloneRenderer(document: doc, layerID: id, initial: stroke))
    doc.layers[0].locked = false
    doc.layers[0].content = .raster(try Surface(width: 8, height: 8))
    XCTAssertFalse(IncrementalCloneRenderer.supports(document: doc, layerID: id, stroke: stroke))
    XCTAssertThrowsError(try IncrementalCloneRenderer(document: doc, layerID: id, initial: stroke))
  }
}
