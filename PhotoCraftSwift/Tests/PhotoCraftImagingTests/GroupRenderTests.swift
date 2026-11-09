import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GroupRenderTests: XCTestCase {
  func doc(_ layers: [Layer], depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 4, depth: depth)
    d.layers = layers
    d.activeLayerID = layers.last?.id
    return d
  }
  func raster(_ name: String, _ color: Pixel, depth: PixelDepth = .u8) throws -> Layer {
    Layer(name: name, content: .raster(try Surface(width: 4, height: 4, depth: depth, fill: color)))
  }
  func testMalformedPSDGroupDividersReject() throws {
    let source = try PSDCodec.writeRasterLayers(fixture())
    var broken = source
    let marker = try XCTUnwrap(
      broken.range(of: Data([0x6c, 0x73, 0x63, 0x74, 0, 0, 0, 12, 0, 0, 0, 3])))
    broken[marker.lowerBound + 11] = 1
    XCTAssertThrowsError(try PSDCodec.read(broken))
  }
  func testGroupTemporaryBudgetUsesWholeTilesForThinCanvases() throws {
    var d = try CraftDocument(width: 32768, height: 1)
    d.layers = []
    for _ in 0..<24 {
      let group = Layer(name: "Nested", content: .group(GroupContent()))
      if !d.layers.isEmpty { d.layers[d.layers.count - 1].parentID = group.id }
      d.layers.append(group)
    }
    d.activeLayerID = d.layers.last!.id
    let region=IntRect(x:0,y:0,width:d.width,height:d.height)
    // The dense path still rejects the full touched-tile working set. The public
    // compositor now evaluates the same canvas through bounded patches instead.
    XCTAssertTrue(Renderer.groupCompositionExceedsBudget(d,region:region))
    XCTAssertThrowsError(try Renderer.compositePrepared(d,region:region))
    let preview=try Renderer.composite(d)
    XCTAssertEqual(preview.pixel(x:0,y:0),.clear)
    XCTAssertEqual(preview.pixel(x:d.width-1,y:0),.clear)
  }
  func testPassThroughAdjustmentReachesBackdropAndNormalGroupIsolates() throws {
    let background = try raster("Background", Pixel(0.2, 0.4, 0.8))
    var group = Layer(name: "Folder", content: .group(GroupContent()))
    var adjustment = Layer(name: "Invert", content: .adjustment(.invert))
    adjustment.parentID = group.id
    let p = try Renderer.composite(doc([background, adjustment, group])).pixel(x: 0, y: 0)
    XCTAssertEqual(p.r, 0.8, accuracy: 0.005)
    XCTAssertEqual(p.b, 0.2, accuracy: 0.005)
    group.content = .group(GroupContent(passThrough: false))
    let q = try Renderer.composite(doc([background, adjustment, group])).pixel(x: 0, y: 0)
    XCTAssertEqual(q.r, 0.2, accuracy: 0.005)
    XCTAssertEqual(q.b, 0.8, accuracy: 0.005)
  }
  func testGroupOpacityInterpolatesPremultipliedAlphaAndAppliesMaskOnce() throws {
    var group = Layer(name: "Folder", content: .group(GroupContent()))
    group.opacity = 0.5
    group.mask = try Surface(width: 4, height: 4, depth: .f32, fill: Pixel(0.5, 0.5, 0.5))
    var red = try raster("Red", Pixel(1, 0, 0))
    red.parentID = group.id
    let p = try Renderer.composite(doc([red, group])).pixel(x: 0, y: 0)
    XCTAssertEqual(p.a, 0.25, accuracy: 0.00001)
    XCTAssertEqual(p.r, 1, accuracy: 0.00001)
    group.content = .group(GroupContent(passThrough: false))
    let q = try Renderer.composite(doc([red, group])).pixel(x: 0, y: 0)
    XCTAssertEqual(q, p)
  }
  func testClippingKeepsBaseAlphaAndOpacityAcrossChainAndHiddenBase() throws {
    var base = try raster("Base", Pixel(1, 0, 0, 0.4), depth: .f32)
    base.opacity = 0.5
    var clip = try raster("Clip", Pixel(0, 0, 1))
    clip.clipped = true
    var adjust = Layer(name: "Invert", content: .adjustment(.invert))
    adjust.clipped = true
    var d = try doc([base, clip, adjust])
    let p = try Renderer.composite(d).pixel(x: 0, y: 0)
    XCTAssertEqual(p.a, 0.2, accuracy: 0.00001)
    XCTAssertEqual(p.r, 1, accuracy: 0.00001)
    XCTAssertEqual(p.g, 1, accuracy: 0.00001)
    XCTAssertEqual(p.b, 0, accuracy: 0.00001)
    d.layers[0].visible = false
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0), .clear)
    d.layers = [clip]
    d.activeLayerID = clip.id
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0), .clear)
  }
  func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(
      width: 96, height: 64, depth: depth, name: "Nested groups and clipping")
    var background = try Surface(width: 96, height: 64, depth: depth)
    for y in 0..<64 {
      for x in 0..<96 { background.setPixel(x: x, y: y, Pixel(Float(x) / 95, Float(y) / 63, 0.3)) }
    }
    let backdrop = Layer(name: "Gradient backdrop", content: .raster(background))
    var outer = Layer(name: "Pass Through folder", content: .group(GroupContent()))
    outer.opacity = 0.8
    var inner = Layer(
      name: "Isolated nested folder",
      content: .group(GroupContent(passThrough: false, expanded: true)))
    inner.parentID = outer.id
    inner.opacity = 0.7
    inner.blendMode = .multiply
    var base = Layer(
      name: "Base with transparent edge",
      content: .raster(
        try Surface(width: 55, height: 42, depth: depth, fill: Pixel(1, 0.4, 0.2, 0.5))))
    base.parentID = inner.id
    base.x = 9
    base.y = 8
    base.opacity = 0.8
    var clip = Layer(
      name: "Blue clipped to base",
      content: .raster(
        try Surface(width: 32, height: 50, depth: depth, fill: Pixel(0.1, 0.4, 1, 0.75))))
    clip.parentID = inner.id
    clip.clipped = true
    clip.x = 24
    clip.y = 4
    var mask = try Surface(width: 96, height: 64, depth: depth, fill: .white)
    for y in 0..<64 {
      for x in 0..<96 {
        let v = Float(x) / 95
        mask.setPixel(x: x, y: y, Pixel(v, v, v))
      }
    }
    outer.mask = mask
    var screen = Layer(
      name: "Screen inside pass through",
      content: .raster(try Surface(width: 30, height: 25, depth: depth, fill: Pixel(0.5, 0.8, 0.1)))
    )
    screen.blendMode = .screen
    screen.x = 48
    screen.y = 24
    screen.parentID = outer.id
    d.layers = [backdrop, base, clip, inner, screen, outer]
    d.activeLayerID = outer.id
    return d
  }
  func testPSDGroupsClippingMasksAndAllDepthsRoundTrip() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth: depth)
      let data = try PSDCodec.writeRasterLayers(source)
      let decoded = try PSDCodec.read(data)
      XCTAssertEqual(decoded.layers.map(\.name), source.layers.map(\.name))
      XCTAssertEqual(decoded.layers.map(\.isGroup), source.layers.map(\.isGroup))
      XCTAssertEqual(decoded.layers.map(\.isClipped), source.layers.map(\.isClipped))
      XCTAssertEqual(
        decoded.ancestors(of: decoded.layers[2].id).map(\.name),
        ["Isolated nested folder", "Pass Through folder"])
      XCTAssertEqual(decoded.layers[3].group?.passThrough, false)
      XCTAssertEqual(decoded.layers[5].group?.passThrough, true)
      let a = try Renderer.composite(source)
      let b = try Renderer.composite(decoded)
      for y in 0..<a.height {
        for x in 0..<a.width {
          let p = a.pixel(x: x, y: y)
          let q = b.pixel(x: x, y: y)
          XCTAssertEqual(p.r, q.r, accuracy: 0.004)
          XCTAssertEqual(p.g, q.g, accuracy: 0.004)
          XCTAssertEqual(p.b, q.b, accuracy: 0.004)
        }
      }
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      try data.write(
        to: root.appendingPathComponent(
          "artifacts/native-groups-\(depth == .u8 ? 8 : depth == .u16 ? 16 : 32).psd"))
    }
  }
  func testExportClippingMatrix() throws {
    var d = try CraftDocument(width: 128, height: 128)
    d.layers[0].content = .raster(
      try Surface(width: 128, height: 128, fill: Pixel(0.25, 0.5, 0.75)))
    for i in 0..<16 {
      var group = Layer(name: "Case \(i)", content: .group(GroupContent()))
      group.opacity = i & 1 == 0 ? 1 : 0.7
      var child = Layer(
        name: "Screen",
        content: .raster(
          try Surface(width: 28, height: 28, fill: Pixel(0.8, 0.4, 0.1, i & 2 == 0 ? 1 : 0.6))))
      child.parentID = group.id
      child.blendMode = .screen
      child.x = (i % 4) * 32
      child.y = (i / 4) * 32
      var clip = Layer(
        name: "Clip",
        content: .raster(
          try Surface(width: 28, height: 28, fill: Pixel(0.2, 0.4, 0.9, i & 4 == 0 ? 1 : 0.8))))
      clip.clipped = true
      clip.blendMode = i & 8 == 0 ? .normal : .multiply
      clip.x = child.x
      clip.y = child.y
      d.layers += [child, group, clip]
    }
    d.activeLayerID = d.layers.last!.id
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try PSDCodec.writeRasterLayers(d).write(
      to: root.appendingPathComponent("artifacts/native-group-matrix.psd"))
  }
  func testExportClippingMatrix2() throws {
    var d = try CraftDocument(width: 128, height: 128)
    d.layers[0].content = .raster(
      try Surface(width: 128, height: 128, fill: Pixel(0.25, 0.5, 0.75)))
    for i in 0..<16 {
      var group = Layer(name: "Case \(i)", content: .group(GroupContent()))
      group.opacity = i & 1 == 0 ? 1 : 0.7
      var child = Layer(
        name: "Screen",
        content: .raster(
          try Surface(width: 28, height: 28, fill: Pixel(0.8, 0.4, 0.1, i & 2 == 0 ? 0.8 : 0.4))))
      child.parentID = group.id
      child.blendMode = .screen
      child.x = (i % 4) * 32
      child.y = (i / 4) * 32
      var clip = Layer(
        name: "Clip",
        content: .raster(
          try Surface(width: 28, height: 28, fill: Pixel(0.2, 0.4, 0.9, i & 4 == 0 ? 1 : 0.8))))
      clip.clipped = true
      clip.blendMode = i & 8 == 0 ? .normal : .multiply
      clip.x = child.x
      clip.y = child.y
      d.layers += [child, group, clip]
    }
    d.activeLayerID = d.layers.last!.id
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try PSDCodec.writeRasterLayers(d).write(
      to: root.appendingPathComponent("artifacts/native-group-matrix2.psd"))
  }
  func testExportAdvancedClippingFixture() throws {
    var d = try fixture()
    var group = Layer(name: "Pass Through clipping base", content: .group(GroupContent()))
    group.opacity = 0.7
    var screen = Layer(
      name: "Screen child",
      content: .raster(try Surface(width: 35, height: 35, fill: Pixel(0.8, 0.4, 0.1, 0.6))))
    screen.x = 4
    screen.y = 4
    screen.blendMode = .screen
    screen.parentID = group.id
    var clip = Layer(
      name: "Multiply clipped to folder",
      content: .raster(try Surface(width: 28, height: 42, fill: Pixel(0.2, 0.4, 0.9, 0.8))))
    clip.x = 12
    clip.y = 3
    clip.blendMode = .multiply
    clip.clipped = true
    var base = Layer(
      name: "Ungrouped blending base",
      content: .raster(try Surface(width: 40, height: 40, fill: Pixel(0.7, 0.1, 0.3, 0.5))))
    base.x = 48
    base.y = 12
    base.blendMode = .multiply
    base.opacity = 0.6
    base.blendClippedAsGroup = false
    var second = Layer(
      name: "Screen clipped independently",
      content: .raster(try Surface(width: 24, height: 24, fill: Pixel(0.2, 0.7, 0.9, 0.7))))
    second.x = 52
    second.y = 19
    second.blendMode = .screen
    second.opacity = 0.8
    second.clipped = true
    d.layers = [d.layers[0], screen, group, clip, base, second]
    d.activeLayerID = second.id
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try PSDCodec.writeRasterLayers(d).write(
      to: root.appendingPathComponent("artifacts/native-groups-advanced.psd"))
  }
  func testPhotoshopClippingMatrix2() throws {
    try comparePhotoshop("photoshop-group-matrix2", groups: 16)
  }
  func testPhotoshopClippingMatrix() throws {
    try comparePhotoshop("photoshop-group-matrix", groups: 16)
  }
  func testPhotoshopSavedAdvancedClippingMatchesMergedImage() throws {
    try comparePhotoshop("photoshop-groups-advanced", groups: 1)
  }
  func testPhotoshopSavedGroupFixtureMatchesMergedImage() throws {
    try comparePhotoshop("photoshop-groups-8", groups: 2)
  }
  func comparePhotoshop(_ name: String, groups: Int) throws {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "psd", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let d = try PSDCodec.read(data)
    let result = try Renderer.composite(d)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let reference = try RasterIO.surface(image, depth: .u8)
    var maximum: Float = 0
    for y in 0..<d.height {
      for x in 0..<d.width {
        let a = result.pixel(x: x, y: y)
        let b = reference.pixel(x: x, y: y)
        maximum = max(maximum, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
      }
    }
    XCTAssertEqual(d.layers.filter(\.isGroup).count, groups)
    XCTAssertTrue(d.layers.contains(where: \.isClipped))
    XCTAssertLessThanOrEqual(maximum, 3.0 / 255)
  }
}
