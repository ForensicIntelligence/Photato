import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class RegionalRenderTests: XCTestCase {
  func equalBits(_ a: Surface, _ b: Surface, file: StaticString = #filePath, line: UInt = #line)
    throws
  {
    XCTAssertEqual(a.width, b.width, file: file, line: line)
    XCTAssertEqual(a.height, b.height, file: file, line: line)
    XCTAssertEqual(try a.rgbaData(depth: .f32), try b.rgbaData(depth: .f32), file: file, line: line)
  }

  func paint(_ d: inout CraftDocument, at index: Int = 0, x: Int, y: Int, mask: Bool = false)
    throws
  {
    if mask {
      d.layers[index].mask?.setPixel(x: x, y: y, .black)
    } else if case .raster(var s) = d.layers[index].content {
      s.setPixel(x: x, y: y, Pixel(0.9, 0.08, 0.27, 0.7))
      d.layers[index].content = .raster(s)
    } else {
      XCTFail("Expected a raster layer")
    }
  }

  func testRegionalFlatRenderEveryBlendAndDepthKeepsDissolveCoordinates() throws {
    for depth in PixelDepth.allCases {
      for mode in BlendMode.allCases {
        var d = try CraftDocument(width: 71, height: 67, depth: depth)
        d.layers[0].content = .fill(Pixel(0.21, 0.43, 0.79, 0.73))
        var top = Layer(
          name: "Source",
          content: .raster(
            try Surface(
              width: 71, height: 67, depth: depth,
              fill: Pixel(0.72, 0.16, 0.53, 0.63))))
        top.blendMode = mode
        top.opacity = 0.67
        d.layers.append(top)
        let full = try Renderer.composite(d)
        let region = IntRect(x: 61, y: 62, width: 8, height: 4)
        let partial = try Renderer.composite(d, region: region)
        var expected = try Surface(width: 71, height: 67, depth: .f32)
        try expected.mapPixels(in: region) { x, y, _ in full.pixel(x: x, y: y) }
        try equalBits(partial, expected)
        XCTAssertEqual(partial.tileCount, 4)
      }
    }
  }

  func testNestedGroupsClippedPassThroughAndAdjustmentBasesMatchFullBits() throws {
    for depth in PixelDepth.allCases {
      for passThrough in [false, true] {
        for grouped in [false, true] {
          var d = try GroupRenderTests().fixture(depth: depth)
          d.layers[5].content = .group(GroupContent(passThrough: passThrough))
          d.layers[5].blendClippedAsGroup = grouped
          var clip = Layer(name: "Clip onto outer group", content: .fill(Pixel(0.8, 0.1, 0.3, 0.6)))
          clip.clipped = true
          clip.blendMode = .dissolve
          d.layers.append(clip)
          var adjustment = Layer(name: "Adjustment base", content: .adjustment(.invert))
          adjustment.opacity = 0.45
          adjustment.mask = try Surface(width: 96, height: 64, fill: Pixel(0.4, 0.4, 0.4))
          d.layers.append(adjustment)
          clip.id = UUID()
          clip.blendMode = .overlay
          d.layers.append(clip)
          let before = try Renderer.render(d)
          try paint(&d, at: 1, x: 20, y: 14)
          let after = try Renderer.render(d, reusing: before)
          guard case .region = after.update else { return XCTFail("Expected a regional render") }
          try equalBits(after.surface, Renderer.composite(d))
          let undone = try Renderer.render(before.document, reusing: after)
          try equalBits(undone.surface, before.surface)
          let redone = try Renderer.render(d, reusing: undone)
          try equalBits(redone.surface, after.surface)
        }
      }
    }
  }

  func testAffinePixelsPixelAndVectorFeatherKeepOriginalCanvasBounds() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 180, height: 140, depth: depth)
      var mask = try Surface(width: 180, height: 140, depth: depth, fill: .white)
      mask.setPixel(x: 63, y: 64, .black)
      d.layers[0].mask = mask
      var properties = MaskProperties()
      properties.feather = 2.3
      properties.density = 0.77
      d.layers[0].maskProperties = properties
      var v = VectorMask(path: VectorPath(components: [VectorRenderTests().rect(0, 0, 175, 135)]))
      v.feather = 1.7
      d.layers[0].vectorMask = v
      let before = try Renderer.render(d)
      try paint(&d, x: 0, y: 0, mask: true)
      try paint(&d, x: 179, y: 139, mask: true)
      let masked = try Renderer.render(d, reusing: before)
      try equalBits(masked.surface, Renderer.composite(d))

      d.layers[0].x = -35
      d.layers[0].y = -12
      d.layers[0].affine = .rotation(17) * .scale(1.1, 0.83)
      d.layers[0].maskProperties?.transform = .translation(12.2, -3.7) * .scale(0.9, 1.2)
      let transformed = try Renderer.render(d)
      try paint(&d, x: 65, y: 70)
      try paint(&d, x: 64, y: 63, mask: true)
      let edited = try Renderer.render(d, reusing: transformed)
      guard case .region(let r) = edited.update else { return XCTFail("Expected regional damage") }
      XCTAssertLessThan(r.width * r.height, d.width * d.height)
      try equalBits(edited.surface, Renderer.composite(d))
    }
  }

  func testEveryCurrentAdjustmentPropagatesLocalDamage() throws {
    let adjustments: [Adjustment] = [
      .levels(.init()), .curves(.init()), .hueSaturation(.init()), .colorBalance(.init()),
      .tonalSteps(.init(kind: .posterize)), .exposure(0.3), .brightnessContrast(0.1, 1.2),
      .saturation(0.4), .invert, .grayscale,
    ]
    for depth in PixelDepth.allCases {
      for adjustment in adjustments {
        var d = try CraftDocument(width: 130, height: 71, depth: depth)
        d.layers.append(Layer(name: "Adjustment", content: .adjustment(adjustment)))
        let before = try Renderer.render(d)
        try paint(&d, x: 64, y: 65)
        let after = try Renderer.render(d, reusing: before)
        XCTAssertEqual(after.update, .region(IntRect(x: 64, y: 64, width: 64, height: 7)))
        try equalBits(after.surface, Renderer.composite(d))
      }
    }
  }

  func testUnchangedSelectionOffCanvasEditsAndFullFallbacks() throws {
    var d = try CraftDocument(width: 140, height: 100)
    let before = try Renderer.render(d)
    d.name = "Renamed"
    d.selection = IntRect(x: 10, y: 10, width: 30, height: 20)
    let selected = try Renderer.render(d, reusing: before)
    XCTAssertEqual(selected.update, .unchanged)
    XCTAssertEqual(selected.document.selection, d.selection)
    try equalBits(selected.surface, before.surface)
    for variant in 0..<7 {
      var changed = d
      switch variant {
      case 0: changed.layers[0].opacity = 0.5
      case 1: changed.layers[0].visible = false
      case 2: changed.layers[0].x = 2
      case 3: changed.layers[0].content = .fill(.black)
      case 4: changed.depth = .f32
      case 5: changed.id = UUID()
      default: changed.layers[0].mask = try Surface(width: 140, height: 100, fill: .black)
      }
      let result = try Renderer.render(changed, reusing: selected)
      XCTAssertEqual(result.update, .full)
      try equalBits(result.surface, Renderer.composite(changed))
    }
    d.layers[0].x = 200
    let outside = try Renderer.render(d)
    try paint(&d, x: 1, y: 1)
    let edited = try Renderer.render(d, reusing: outside)
    XCTAssertEqual(edited.update, .unchanged)
    try equalBits(edited.surface, Renderer.composite(d))
  }

  func testSignedZeroMetadataInvalidatesEvenThoughSwiftEqualityMatches() throws {
    var d = try CraftDocument(width: 3, height: 3, depth: .f32)
    d.layers[0].content = .fill(Pixel(0, 0.4, 1))
    let before = try Renderer.render(d)
    d.layers[0].content = .fill(Pixel(-0.0, 0.4, 1))
    XCTAssertEqual(d, before.document)
    let after = try Renderer.render(d, reusing: before)
    XCTAssertEqual(after.update, .full)
    try equalBits(after.surface, Renderer.composite(d))
  }

  func testRegionalAllocationBoundsAndInvalidDocumentsStillReject() throws {
    var d = try CraftDocument(width: 32768, height: 1)
    let base = d.layers[0]
    d.layers = []
    var child = base
    for _ in 0..<24 {
      let group = Layer(name: "Nested", content: .group(GroupContent()))
      child.parentID = group.id
      d.layers.append(child)
      child = group
    }
    d.layers.append(child)
    d.activeLayerID = child.id
    let canvas = IntRect(x: 0, y: 0, width: d.width, height: d.height)
    XCTAssertTrue(Renderer.groupCompositionExceedsBudget(d, region: canvas))
    XCTAssertThrowsError(try Renderer.compositePrepared(d, region: canvas))
    let bounded = try Renderer.composite(d)
    for x in 0..<d.width { XCTAssertTrue(bounded.pixel(x: x, y: 0).hasSameBits(as: .white)) }
    let tiny = try Renderer.composite(d, region: IntRect(x: 63, y: 0, width: 2, height: 1))
    XCTAssertEqual(tiny.tileCount, 2)
    XCTAssertEqual(tiny.pixel(x: 63, y: 0), .white)
    XCTAssertEqual(tiny.pixel(x: 62, y: 0), .clear)
    let empty = try Renderer.composite(
      d, region: IntRect(x: Int.max, y: 0, width: Int.max, height: 1))
    XCTAssertEqual(empty.tileCount, 0)
    var invalid = d
    invalid.layers[0].opacity = .nan
    XCTAssertThrowsError(
      try Renderer.composite(invalid, region: IntRect(x: 0, y: 0, width: 0, height: 0)))
    XCTAssertThrowsError(try Renderer.render(invalid))
  }
}
