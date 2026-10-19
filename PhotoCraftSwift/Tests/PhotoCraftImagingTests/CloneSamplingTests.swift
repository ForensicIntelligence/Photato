import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class CloneSamplingTests: XCTestCase {
  func testLayerModesVisibilityAndIgnoreAdjustments() throws {
    var d = try CraftDocument(width: 4, height: 4)
    d.layers[0].content = .raster(try Surface(width: 4, height: 4, fill: Pixel(1, 0, 0)))
    let empty = Layer(name: "Retouch", content: .raster(try Surface(width: 4, height: 4)))
    let top = Layer(name: "Top", content: .fill(Pixel(0, 0, 1)))
    d.layers.append(contentsOf: [empty, top])
    XCTAssertEqual(
      try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .current).surface.pixel(
        x: 1, y: 1), .clear)
    XCTAssertEqual(
      try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .currentAndBelow).surface.pixel(
        x: 1, y: 1), Pixel(1, 0, 0))
    XCTAssertEqual(
      try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .all).surface.pixel(x: 1, y: 1),
      Pixel(0, 0, 1))
    d.layers[2].visible = false
    d.layers.append(Layer(name: "Invert", content: .adjustment(.invert)))
    XCTAssertEqual(
      try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .all).surface.pixel(x: 1, y: 1),
      Pixel(0, 1, 1))
    XCTAssertEqual(
      try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .all, ignoreAdjustments: true)
        .surface.pixel(x: 1, y: 1), Pixel(1, 0, 0))
  }
  func testCurrentAndBelowPreservesAncestorGroupsAndMasks() throws {
    var d = try CraftDocument(width: 4, height: 4)
    let g = Layer(name: "Group", content: .group(.init(passThrough: false)))
    d.layers[0].content = .raster(try Surface(width: 4, height: 4, fill: .white))
    d.layers[0].parentID = g.id
    var empty = Layer(name: "Retouch", content: .raster(try Surface(width: 4, height: 4)))
    empty.parentID = g.id
    var above = Layer(name: "Above", content: .fill(.black))
    above.parentID = g.id
    d.layers.append(contentsOf: [empty, above, g])
    d.layers[3].opacity = 0.5
    let p = try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .currentAndBelow).surface
      .pixel(x: 1, y: 1)
    XCTAssertEqual(p.r, 1)
    XCTAssertEqual(p.a, 0.5, accuracy: 0.000001)
  }
  func testRawLayerTransformMaskAndEditablePSDOutput() throws {
    var d = try CraftDocument(width: 8, height: 4, depth: .u16)
    d.layers[0].x = 2
    d.layers[0].content = .raster(
      try Surface(width: 4, height: 4, depth: .u16, fill: Pixel(0.2, 0.4, 0.8)))
    d.layers[0].mask = try Surface(width: 4, height: 4, depth: .u16, fill: Pixel(0.5, 0.5, 0.5))
    let id = d.layers[0].id
    let sample = try Renderer.cloneSample(in: d, layerID: id, sampling: .current)
    XCTAssertEqual(sample.transform, .translation(2, 0))
    XCTAssertEqual(sample.surface.pixel(x: 1, y: 1).a, 1)
    let mask = try Renderer.cloneSample(in: d, layerID: id, sampling: .current, mask: true)
    XCTAssertEqual(mask.transform, d.layers[0].maskCoordinateTransform)
    var brush = CloneBrush()
    brush.hardness = 1
    brush.size = 2
    try Command.cloneStamp(
      id,
      .init(
        source: sample, mapping: .init(source: .init(2.5, 1.5), anchor: .init(4.5, 1.5)),
        brush: brush, points: [.init(x: 4.5, y: 1.5)])
    ).apply(to: &d)
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    guard case .raster(let a) = reopened.layers[0].content,
      case .raster(let b) = d.layers[0].content
    else { return XCTFail() }
    for y in 0..<4 { for x in 0..<4 { XCTAssertEqual(a.pixel(x: x, y: y), b.pixel(x: x, y: y)) } }
    XCTAssertThrowsError(try Renderer.cloneSample(in: d, layerID: UUID(), sampling: .all))
  }
}
