import XCTest
@testable import PhotoCraftCore

final class BrushDynamicsTests:XCTestCase {
  func testWideSoftTailMatchesScalarAndRetainedPathsAtAllDepths() throws {
    var brush = Brush()
    brush.size = 41
    brush.hardness = 0
    brush.color = .white
    brush.settings = .init()
    brush.settings?.roundTipProfile = .wideSoft
    let points = [StrokePoint(x: 64.25, y: 52.75), StrokePoint(x: 74, y: 57)]
    let translated = points.map { StrokePoint(x: $0.x + 16, y: $0.y - 8) }
    let bounds = try XCTUnwrap(BrushPainter.strokeBounds(points: points, brush: brush))
    XCTAssertTrue(bounds.contains(92, 52))
    for depth in PixelDepth.allCases {
      let source = try Surface(width: 128, height: 111, depth: depth, fill: .clear)
      var wide = source, scalar = source, compact = source
      try BrushPainter.stroke(surface: &wide, points: points, brush: brush)
      try BrushPainter.stroke(surface: &scalar, points: translated, brush: brush,
        transform: .translation(16, -8))
      var legacy = brush
      legacy.settings?.roundTipProfile = nil
      try BrushPainter.stroke(surface: &compact, points: points, brush: legacy)
      let retained = try BrushStrokeSession(surface: source, brush: brush, selection: nil,
        selectionMask: nil, transform: .identity, preserveTransparency: false)
      _ = try retained.append([points[0]], includingReleaseTail: false)
      let final = try retained.append([points[1]], includingReleaseTail: true)
      let expected = try wide.rgbaData(depth: depth)
      XCTAssertEqual(try scalar.rgbaData(depth: depth), expected)
      XCTAssertEqual(try final.rgbaData(depth: depth), expected)
      XCTAssertGreaterThan(wide.pixel(x: 37, y: 52).a, 0)
      XCTAssertEqual(compact.pixel(x: 37, y: 52).a, 0)
      XCTAssertEqual(wide.pixel(x: 29, y: 52).a, 0)
    }
  }

  func testWideSoftMaximumDiameterSchedulesBandsBeyondOldBounds() throws {
    var brush = Brush()
    brush.size = 5_000
    brush.hardness = 0
    brush.color = .white
    brush.settings = .init()
    brush.settings?.roundTipProfile = .wideSoft
    let point = StrokePoint(x: 1.5, y: 1.5)
    var wide = try Surface(width: 4_500, height: 4, fill: .clear)
    var legacy = wide
    let bounds = try XCTUnwrap(BrushPainter.strokeBounds(points: [point], brush: brush))
    try BrushPainter.stroke(surface: &wide, points: [point], brush: brush)
    brush.settings?.roundTipProfile = nil
    try BrushPainter.stroke(surface: &legacy, points: [point], brush: brush)
    for x in [2_501, 3_075, 4_100] {
      XCTAssertTrue(bounds.contains(x, 1))
      XCTAssertGreaterThan(wide.pixel(x: x, y: 1).a, 0)
      XCTAssertEqual(legacy.pixel(x: x, y: 1).a, 0)
    }
    XCTAssertEqual(wide.pixel(x: 4_200, y: 1).a, 0)
  }

  func testParallelBrushOutputRestoresAbsentTailTilesAcrossBatches() throws {
    let width = 1_013, height = 1_107
    let columns = (width + 63) / 64, rows = (height + 63) / 64
    let weights: [Float] = (0..<4096).map { $0 % 7 == 0 ? 0.63 : 0 }
    let blend: @Sendable (Float, Pixel) -> Pixel = { coverage, before in
      BlendMode.normal.composite(backdrop: before, source: Pixel(0.32, 0.75, 0.83, coverage))
    }
    for depth in [PixelDepth.u8, .f32] {
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var original = try Surface(width: width, height: height, depth: depth,
        fill: Pixel(0.14, 0.31, 0.61, 0.47), colorEncoding: encoding)
      for key in stride(from: 0, to: columns * rows, by: 9) {
        let x = key % columns * 64, y = key / columns * 64
        if depth == .f32 { original.setLinearPixel(x: x + 3, y: y + 3, Pixel(-0.0, 1.8, -0.21, 0)) }
        else { original.setPixel(x: x + 3, y: y + 3, Pixel(0.31, 0.41, 0.83, 0)) }
      }
      original = try original.spillingTiles(to: RasterTileStore())
      var preview = original
      for key in 0..<columns * rows {
        preview.setPixel(x: key % columns * 64, y: key / columns * 64, .white)
      }
      let inputs: [Surface.BrushTileInput] = (0..<columns * rows).map {
        .init(key: $0, coverage: $0 % 3 == 0 ? [] : weights, colors: [])
      }
      var expected = preview, actual = preview
      for input in inputs {
        expected.updateBrushTile(input.key, coverage: input.coverage, rebuildingFrom: original) { _, _, _, coverage, before in
          blend(coverage, before)
        }
      }
      try actual.updateBrushTiles(inputs, rebuildingFrom: original) { _, _, _, coverage, before, _ in
        blend(coverage, before)
      }
      XCTAssertEqual(try actual.rgbaData(depth: .f32, colorEncoding: encoding),
        try expected.rgbaData(depth: .f32, colorEncoding: encoding))
      XCTAssertEqual(actual.pixel(x: 0, y: 0), original.pixel(x: 0, y: 0))
      XCTAssertEqual(actual.tileCount, expected.tileCount)
      XCTAssertFalse(try actual.isOpaque())
    }
  }

  func testParallelDabCoverageMatchesSerialClippedStrips() throws {
    let width = 673, height = 449
    var source = try Surface(width: width, height: height, depth: .f32,
      fill: Pixel(0.41, 0.24, 0.58, 0.76), colorEncoding: .linearRGB)
    source.setLinearPixel(x: 493, y: 148, Pixel(-0.0, 1.7, -0.2, 0))
    let points: [StrokePoint] = [
      .init(x: -30.125, y: 179.125, time: 0),
      .init(x: 650.7, y: 235.4, time: 24),
    ]

    for textured in [false, true] {
      var brush = Brush()
      brush.size = 2_500
      brush.hardness = 0.21
      brush.color = Pixel(0.73, 0.29, 0.8, 0.58)
      brush.opacity = 0.63
      brush.settings = .init()
      brush.settings!.flow = 0.61
      brush.settings!.spacing = 0.25
      brush.settings!.smoothing.amount = 0
      if textured {
        brush.settings!.mode = .multiply
        brush.settings!.angle = 29
        brush.settings!.roundness = 0.72
        brush.settings!.noise = true
        brush.settings!.wetEdges = true
        brush.settings!.texture.enabled = true
        brush.settings!.texture.eachTip = true
        brush.settings!.texture.pattern = .canvas
        brush.settings!.texture.depth = 0.57
      }

      // Each strip clips wide-dab preparation below the parallel threshold.
      // The strips share the original coordinate space and cover every pixel once.
      var serial = source
      for x in stride(from: 0, to: width, by: 224) {
        let strip = IntRect(x: x, y: 0, width: min(224, width - x), height: height)
        try BrushPainter.stroke(surface: &serial, points: points, brush: brush, selection: strip)
      }
      var complete = source
      try BrushPainter.stroke(surface: &complete, points: points, brush: brush)
      let retained = try BrushStrokeSession(surface: source, brush: brush,
        selection: nil, selectionMask: nil, transform: .identity,
        preserveTransparency: false, allowingWideRaster: true)
      _ = try retained.append([points[0]], includingReleaseTail: false)
      let held = try retained.append([points[1]], includingReleaseTail: false)
      let expected = try serial.rgbaData(depth: .f32, colorEncoding: .linearRGB)
      XCTAssertNotEqual(expected, try source.rgbaData(depth: .f32, colorEncoding: .linearRGB))
      XCTAssertEqual(try complete.rgbaData(depth: .f32, colorEncoding: .linearRGB), expected)
      XCTAssertEqual(try held.rgbaData(depth: .f32, colorEncoding: .linearRGB), expected)
    }
  }

  func testNormalRasterTilePathMatchesFullCoverageMaskAcrossStorageDepths() throws {
    let width = 193, height = 129
    let fullSelection = try SelectionMask(width: width, height: height,
      bytes: [UInt8](repeating: 255, count: width * height))
    let points: [StrokePoint] = [
      .init(x: -200.25, y: 40.5, time: 0),
      .init(x: -166.75, y: 99.25, time: 17),
      .init(x: 650.5, y: 59.75, time: 49),
    ]
    for depth in PixelDepth.allCases {
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var source = try Surface(width: width, height: height, depth: depth,
        fill: Pixel(0.3, 0.52, 0.22, 0.71), colorEncoding: encoding)
      source.setLinearPixel(x: 72, y: 92, Pixel(-0.0, 1.51, -0.13, 0))
      source.setLinearPixel(x: 129, y: 121, Pixel(2.6, -0.04, 0.18, 0.52))
      source = try source.spillingTiles(to: RasterTileStore())
      for texture in [false, true] {
        var brush = Brush()
        brush.size = 2_500
        brush.hardness = 0.14
        brush.opacity = 0.54
        brush.color = Pixel(-0.0, 0.24, 0.82, 0.68)
        brush.settings = .init()
        brush.settings!.flow = 0.67
        brush.settings!.spacing = 0.25
        brush.settings!.texture.enabled = texture
        brush.settings!.texture.eachTip = false
        brush.settings!.texture.depth = 0.48
        let retained = try BrushStrokeSession(surface: source, brush: brush,
          selection: nil, selectionMask: nil, transform: .identity,
          preserveTransparency: false, allowingWideRaster: true)
        for index in points.indices {
          let prefix = Array(points.prefix(index + 1))
          var expected = source
          try BrushPainter.stroke(surface: &expected, points: prefix, brush: brush,
            selectionMask: fullSelection)
          var actual = source
          try BrushPainter.stroke(surface: &actual, points: prefix, brush: brush)
          let retainedPixels = try retained.append([points[index]], includingReleaseTail: false)
          let reference = try expected.rgbaData(depth: .f32, colorEncoding: encoding)
          XCTAssertEqual(try actual.rgbaData(depth: .f32, colorEncoding: encoding), reference)
          XCTAssertEqual(try retainedPixels.rgbaData(depth: .f32, colorEncoding: encoding), reference)
        }
      }
    }
  }

  func brush()->Brush { var b=Brush();b.size=10;b.hardness=1;b.color=Pixel(1,0,0);b.settings=BrushSettings();return b }
  func testPreparedRoundTileMatchesScalarWeightsAtClippedAndFractionalEdges() {
    let cases: [(x: Double, y: Double, radius: Double, isAliased: Bool, hardness: Double)] = [
      (32.5, 32.5, 40, false, 0.4),
      (31.999, 33.125, 47.5, true, 1),
      (31.375, 32.5, 40, false, 1),
      (32.5, 32.5, 500, false, 0.2),
      (180.25, 36.75, 63, false, 0.8),
      (58.5, 58.5, 500, true, 1),
    ]
    var weights = [Float](repeating: -1, count: 4096)
    for (index, item) in cases.enumerated() {
      let dab = BrushDab(x: item.x, y: item.y, radius: item.radius, angle: 0, roundness: 1,
        flipX: index % 2 == 0, flipY: true, flow: 0.67, opacity: 0.8, color: .black, depth: 1)
      let sampler = BrushPainter.TipSampler(dab, bitmap: nil, hardness: item.hardness, aliased: item.isAliased)
      XCTAssertTrue(sampler.isAxisAlignedRound)
      for (tileX, tileY) in [(0, 0), (64, 0), (64, 64), (384, 128), (512, 0)] {
        let xs = 5..<61, ys = 3..<57
        let hasCoverage = weights.withUnsafeMutableBufferPointer {
          sampler.roundTile($0, x: xs, y: ys, tileX: tileX, tileY: tileY, flow: dab.flow)
        }
        var expectedAny = false
        for row in ys {
          for column in xs {
            let point = (x: Double(tileX + column) + 0.5, y: Double(tileY + row) + 0.5)
            let expected = Float(sampler.sample(point).0 * dab.flow)
            expectedAny = expectedAny || expected > 0
            if hasCoverage { XCTAssertEqual(weights[row * 64 + column].bitPattern, expected.bitPattern) }
          }
        }
        XCTAssertEqual(hasCoverage, expectedAny)
      }
    }
  }

  func testCompositeTilesMatchIndividualSettersAcrossPartialBounds() throws {
    let bounds = IntRect(x: 60, y: 61, width: 40, height: 90)
    let backing = try RasterTileStore()
    let formats: [(PixelDepth, SurfaceColorEncoding)] = [(.u8, .sRGB), (.u16, .sRGB), (.f32, .sRGB), (.f32, .linearRGB)]
    for (depth, encoding) in formats {
      var original = try Surface(width: 77, height: 129, depth: depth,
        fill: Pixel(0.18, 0.96, 0.31), colorEncoding: encoding)
      original.setLinearPixel(x: 64, y: 64, Pixel(-0.0, 0.34, 2.7, 0))
      original.setLinearPixel(x: 65, y: 65, Pixel(-0.0, 0.534_101, 2.5, 1))
      original = try original.spillingTiles(to: backing)
      func edit(_ x: Int, _ y: Int, _ p: Pixel) -> Pixel? {
        guard (x + y) % 4 != 0 else { return nil }
        return Pixel(p.r, Float(y)/128, p.b, 0.4)
      }
      var expected = original
      for y in 61..<129 {
        for x in 60..<77 {
          if let p = edit(x, y, original.pixel(x: x, y: y)) { expected.setPixel(x: x, y: y, p) }
        }
      }
      let actual = try original.compositingPixels(in: bounds, edit)
      XCTAssertEqual(try actual.rgbaData(depth: depth, colorEncoding: encoding),
        try expected.rgbaData(depth: depth, colorEncoding: encoding))
      XCTAssertFalse(try actual.isOpaque())
    }
  }
  func testBrushTilePublicationMatchesIndividualSettersInOwnedAndPagedStorage() throws {
    let scratch = try RasterTileStore()
    let formats: [(PixelDepth,SurfaceColorEncoding)] = [
      (.u8,.sRGB),(.u16,.sRGB),(.f32,.sRGB),(.f32,.linearRGB)
    ]
    for (depth,encoding) in formats {
      var original = try Surface(width:70,height:72,depth:depth,colorEncoding:encoding)
      original.setLinearPixel(x:67,y:66,Pixel(-0.0,0.187_331,2.6,0))
      original.setLinearPixel(x:66,y:67,Pixel(0.713_337,-0.0,1.42,1))
      let implicit = try Surface(width:70,height:72,depth:depth,fill:Pixel(0.31,0.74,0.02,0.43),colorEncoding:encoding)
      let inputs = try [original,original.spillingTiles(to:scratch),implicit]
      for source in inputs {
        var expected = source, actual = source
        let storedView = source.pixel(x:67,y:66)
        let first = Pixel(storedView.r,0.4,storedView.b,0.81)
        let second = Pixel(0.1,0.23,0.334,1)
        expected.setPixel(x:67,y:66,first)
        expected.setPixel(x:69,y:70,second)
        var coverage = [Float](repeating:0,count:4096)
        coverage[2*64+3] = 1
        coverage[6*64+5] = 0.2
        // Weight on padding must be ignored.
        coverage[63*64+63] = 1
        actual.updateBrushTile(3,coverage:coverage) { x,y,_,weight,encoded in
          XCTAssertTrue(encoded.hasSameBits(as:source.pixel(x:x,y:y)))
          return weight == 1 ? first : second
        }
        XCTAssertTrue(actual == expected)
        XCTAssertTrue(actual.linearPixel(x:66,y:67).hasSameBits(as:source.linearPixel(x:66,y:67)))
        XCTAssertTrue(actual.linearPixel(x:67,y:66).hasSameBits(as:expected.linearPixel(x:67,y:66)))
        XCTAssertEqual(actual.tileCount,expected.tileCount)
        XCTAssertEqual(actual.mappedTileCount,expected.mappedTileCount)
      }
    }
  }
  func testMaximumDiameterPaintsFullColorCoverageAcrossBands() throws {
    var value = brush()
    value.size = 5_000
    value.settings!.colorDynamics.enabled = true
    var surface = try Surface(width:5_408,height:5_408,fill:.clear)
    try Painter.stroke(surface:&surface,points:[.init(x:2700.5,y:2700.5)],brush:value)

    for boundary in [1024,2048,3072,4096] {
      for offset in [-1,0,1] {
        XCTAssertEqual(surface.pixel(x:boundary+offset,y:2700),value.color)
        XCTAssertEqual(surface.pixel(x:2700,y:boundary+offset),value.color)
      }
    }
    XCTAssertEqual(surface.pixel(x:199,y:2700),.clear)
    XCTAssertEqual(surface.pixel(x:200,y:2700).a,128/255,accuracy:1/255)
    XCTAssertEqual(surface.pixel(x:5200,y:2700).a,128/255,accuracy:1/255)
    XCTAssertEqual(surface.pixel(x:5201,y:2700),.clear)
    XCTAssertEqual(surface.pixel(x:300,y:300),.clear)
    XCTAssertGreaterThan(surface.tileCount * 4096 * 20,128*1024*1024)
  }

  func testWideBrushMatchesUnbandedScaledCoverageAndKeepsWorkAtomic() throws {
    var wide = brush()
    wide.size = 5_000
    wide.opacity = 0.73
    wide.settings!.aliased = true
    wide.settings!.spacing = 0.2
    wide.settings!.flow = 0.42
    wide.settings!.colorDynamics.enabled = true
    wide.settings!.colorDynamics.brightness = 0.2
    var small = wide
    small.size /= 4
    let points = [StrokePoint(x:760,y:52),.init(x:1890,y:52)]
    let scaled = points.map { StrokePoint(x:$0.x*4,y:$0.y*4) }
    let selected = IntRect(x:650,y:28,width:1670,height:48)
    let selectedScaled = IntRect(x:selected.x*4,y:selected.y*4,width:selected.width*4,height:selected.height*4)
    var source = try Surface(width:2560,height:112,fill:.clear)
    var expected = source
    try Painter.stroke(surface:&expected,points:points,brush:small,selection:selected)
    try Painter.stroke(surface:&source,points:scaled,brush:wide,selection:selectedScaled,transform:.scale(4,4))
    XCTAssertTrue(source == expected)

    let original = try Surface(width:80_000,height:20_000,fill:.clear)
    var rejected = original
    let overBudget = [StrokePoint(x:7000,y:7000),.init(x:43_000,y:7000)]
    XCTAssertThrowsError(try Painter.stroke(surface:&rejected,points:overBudget,brush:wide))
    XCTAssertTrue(rejected == original)
    var legacy = wide
    legacy.settings = nil
    XCTAssertThrowsError(try Painter.stroke(surface:&rejected,points:[.init(x:7000,y:7000)],brush:legacy))
    XCTAssertTrue(rejected == original)
  }

  func testSettingsStaySmallAndSnapshotsKeepValueSemantics()throws {
    XCTAssertLessThan(MemoryLayout<Brush>.size,128)
    var a=brush();a.settings!.texture.enabled=true;a.settings!.texture.seed=UInt64.max
    var b=a;b.settings!.shape.size.jitter=0.6
    XCTAssertEqual(a.settings!.shape.size.jitter,0);XCTAssertEqual(b.settings!.shape.size.jitter,0.6)
    var surface=try Surface(width:24,height:24)
    XCTAssertNoThrow(try Painter.stroke(surface:&surface,points:[.init(x:12,y:12)],brush:a))
    XCTAssertEqual(try JSONDecoder().decode(Brush.self,from:JSONEncoder().encode(a)),a)
  }
  func testSpacingDirectionAndInputChunking() throws {
    var b=brush();b.settings!.spacing=1;b.settings!.shape.enabled=true;b.settings!.shape.angle.control = .direction
    let points:[StrokePoint]=[.init(x:5,y:20),.init(x:25,y:20),.init(x:25,y:40)]
    var g=BrushDabGenerator(b);var all=try g.push(points).0;all += try g.finish().0
    XCTAssertEqual(all.count,5);XCTAssertEqual(all.map(\.x),[5,15,25,25,25]);XCTAssertEqual(all.map(\.y),[20,20,20,30,40]);XCTAssertEqual(all.last!.angle,-Double.pi/2,accuracy:1e-10)
    b.settings!.scattering.enabled=true;b.settings!.scattering.amount.jitter=2;b.settings!.scattering.count=3;b.settings!.shape.size.jitter=0.5;b.settings!.colorDynamics.enabled=true;b.settings!.colorDynamics.hue=0.8
    var full=BrushDabGenerator(b),chunked=BrushDabGenerator(b);var expected=try full.push(points).0;expected += try full.finish().0;var actual:[BrushDab]=[]
    for p in points { actual += try chunked.push([p]).0 };actual += try chunked.finish().0
    XCTAssertEqual(actual.count,expected.count)
    for (a,e) in zip(actual,expected) { XCTAssertEqual(a.x,e.x);XCTAssertEqual(a.y,e.y);XCTAssertEqual(a.radius,e.radius);XCTAssertEqual(a.color,e.color) }
    b.settings!.seed=43;var other=BrushDabGenerator(b);XCTAssertNotEqual(try other.push(points).0.map(\.x),expected.map(\.x))
  }
  func testFlowAccumulationOpacityCeilingAndAllDepths() throws {
    for depth in PixelDepth.allCases {
      var b=brush();b.opacity=0.5;b.settings!.flow=0.25;b.settings!.buildUp=true;b.settings!.buildUpRate=20
      var surface=try Surface(width:32,height:32,depth:depth)
      try Painter.stroke(surface:&surface,points:[.init(x:16.5,y:16.5,time:0),.init(x:16.5,y:16.5,time:100)],brush:b)
      XCTAssertEqual(surface.pixel(x:16,y:16).a,Float((1-pow(0.75,3))*0.5),accuracy:depth == .u8 ? 1/255:0.0001)
      try Painter.stroke(surface:&surface,points:[.init(x:16.5,y:16.5,time:0),.init(x:16.5,y:16.5,time:1000)],brush:b)
      XCTAssertGreaterThan(surface.pixel(x:16,y:16).a,0.6)
      b.settings!.flow=1;var one=try Surface(width:32,height:32,depth:depth)
      try Painter.stroke(surface:&one,points:[.init(x:16.5,y:16.5,time:0),.init(x:16.5,y:16.5,time:1000)],brush:b)
      XCTAssertEqual(one.pixel(x:16,y:16).a,0.5,accuracy:1/255)
    }
  }
  func testSampledTipRotationTextureDualAndSymmetry() throws {
    var b=brush();b.size=8;b.settings!.tip=BrushBitmap(width:4,height:2,bytes:Data([255,255,0,0,255,255,0,0]))
    var s=try Surface(width:40,height:32)
    try Painter.stroke(surface:&s,points:[.init(x:10,y:16)],brush:b)
    XCTAssertGreaterThan(s.pixel(x:7,y:16).a,0.9);XCTAssertEqual(s.pixel(x:12,y:16).a,0)
    b.settings!.flipX=true;var flipped=try Surface(width:40,height:32);try Painter.stroke(surface:&flipped,points:[.init(x:10,y:16)],brush:b)
    XCTAssertEqual(flipped.pixel(x:7,y:16).a,0);XCTAssertGreaterThan(flipped.pixel(x:12,y:16).a,0.9)
    b=brush();b.settings!.symmetry.mode = .vertical;b.settings!.symmetry.center = .init(20,16)
    var mirror=try Surface(width:40,height:32);try Painter.stroke(surface:&mirror,points:[.init(x:8,y:16)],brush:b)
    XCTAssertGreaterThan(mirror.pixel(x:8,y:16).a,0.9);XCTAssertGreaterThan(mirror.pixel(x:32,y:16).a,0.9);XCTAssertEqual(mirror.pixel(x:20,y:16).a,0)
    b.settings!.symmetry.mode = .off;b.settings!.dual.enabled=true;b.settings!.dual.size=2
    var dual=try Surface(width:40,height:32);try Painter.stroke(surface:&dual,points:[.init(x:20,y:16)],brush:b)
    XCTAssertEqual(dual.pixel(x:23,y:16).a,0);XCTAssertEqual(dual.pixel(x:20,y:16).a,Float(1.5-sqrt(0.5)),accuracy:1/255)
    b.settings!.dual.enabled=false;b.settings!.texture.enabled=true;b.settings!.texture.bitmap = .init(width:1,height:1,bytes:Data([128]))
    var texture=try Surface(width:40,height:32);try Painter.stroke(surface:&texture,points:[.init(x:20,y:16)],brush:b)
    XCTAssertEqual(texture.pixel(x:20,y:16).a,128/255,accuracy:1/255)
  }
  func testSelectionAffineLocksMaskAndHistory() throws {
    var b=brush();b.size=12;b.settings!.mode = .multiply
    var surface=try Surface(width:32,height:32,fill:Pixel(0.5,0.5,0.5,0.4));let before=surface
    try Painter.stroke(surface:&surface,points:[.init(x:30,y:20)],brush:b,selection:IntRect(x:30,y:0,width:32,height:32),transform:.translation(10,0),preserveTransparency:true)
    XCTAssertEqual(surface.pixel(x:19,y:20),before.pixel(x:19,y:20));XCTAssertEqual(surface.pixel(x:20,y:20).a,before.pixel(x:20,y:20).a);XCTAssertLessThan(surface.pixel(x:20,y:20).g,0.01)
    b.settings!.mode = .normal;b.settings!.colorDynamics.enabled=true;b.settings!.colorDynamics.hue=0.8
    var mask=try Surface(width:32,height:32,fill:.white);try Painter.stroke(surface:&mask,points:[.init(x:16,y:16)],brush:b,grayscaleMask:true)
    let p=mask.pixel(x:16,y:16);XCTAssertEqual(p.r,p.g);XCTAssertEqual(p.g,p.b);XCTAssertEqual(p.a,1)
    let doc=try CraftDocument(width:32,height:32);var session=EditorSession(document:doc)
    try session.execute(.stroke(doc.layers[0].id,[.init(x:16,y:16)],b));let changed=session.document;XCTAssertNotEqual(changed,doc);try session.undo();XCTAssertEqual(session.document,doc);try session.redo();XCTAssertEqual(session.document,changed)
  }
  func testLegacyDecodingInvalidAtomicityAndSettingsRoundtrip() throws {
    let legacy=Data(#"{"size":12,"hardness":1,"opacity":1,"color":{"r":1,"g":0,"b":0,"a":1},"erase":false}"#.utf8)
    let b=try JSONDecoder().decode(Brush.self,from:legacy);XCTAssertNil(b.settings)
    let p=try JSONDecoder().decode(StrokePoint.self,from:Data(#"{"x":3,"y":4,"pressure":0.5}"#.utf8));XCTAssertNil(p.time);XCTAssertNil(p.tiltX)
    var modern=brush();modern.settings!.tip = .init(width:1,height:1,bytes:Data([255]));modern.settings!.pose.enabled=true;modern.settings!.pose.overridePressure=true;modern.settings!.pose.pressure=0.25
    XCTAssertEqual(try JSONDecoder().decode(Brush.self,from:JSONEncoder().encode(modern)),modern)
    var s=try Surface(width:32,height:32);let original=s;modern.settings!.spacing=0
    XCTAssertThrowsError(try Painter.stroke(surface:&s,points:[p],brush:modern));XCTAssertEqual(s,original)
    modern=brush();XCTAssertThrowsError(try Painter.stroke(surface:&s,points:[.init(x:8,y:8,time:20),.init(x:10,y:10,time:10)],brush:modern));XCTAssertEqual(s,original)
    modern.settings!.buildUp=true;modern.settings!.buildUpRate=1000
    XCTAssertThrowsError(try Painter.stroke(surface:&s,points:[.init(x:8,y:8,time:0),.init(x:8,y:8,time:3_600_000)],brush:modern));XCTAssertEqual(s,original)
  }
  func testSmoothingPressureAndLockedPresetSections() throws {
    var b=brush();b.settings!.smoothing.amount=0.5;b.settings!.smoothing.pulledString=true;b.settings!.smoothing.catchUpOnEnd=false;b.settings!.pressureSize=true
    var g=BrushDabGenerator(b);let dabs=try g.push([.init(x:0,y:0),.init(x:20,y:0),.init(x:100,y:0,pressure:0.5)]).0
    XCTAssertLessThanOrEqual(dabs.last!.x,50.0001);XCTAssertEqual(dabs.last!.radius,5*(1-dabs.last!.x/100),accuracy:0.00001)
    var current=BrushSettings(),preset=BrushSettings();current.shape.enabled=true;current.shape.size.jitter=0.7;current.lockedSections=["shape"];current.protectTexture=true;current.texture.scale=2;preset.texture.enabled=true
    let picked=preset.picked(over:current);XCTAssertEqual(picked.shape,current.shape);XCTAssertEqual(picked.texture.scale,2)
  }
}
