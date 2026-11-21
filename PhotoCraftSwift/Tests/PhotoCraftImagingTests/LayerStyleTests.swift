import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class LayerStyleTests: XCTestCase {
  func testRegionalDropShadowAlphaMatchesIsolatedRasterSamplesAtEveryDepth() throws {
    let region = IntRect(x: 3, y: 1, width: 134, height: 100)
    let stride = region.width + 8, start = stride + 3
    for depth in PixelDepth.allCases {
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var document = try CraftDocument(width: 147, height: 113, depth: depth)
      var raster = try Surface(width: 133, height: 94, depth: depth,
        fill: Pixel(0.73, 0.19, 0.84, 0.51), colorEncoding: encoding)
      for x in 62...65 {
        raster.setPixel(x: x, y: 64, Pixel(0.22, 0.48, 0.16, Float(x - 62) / 7))
      }
      var layer = Layer(name: "Coverage", content: .raster(raster))
      layer.x = -2
      layer.y = 7
      var mask = try Surface(width: document.width, height: document.height, fill: .white)
      try mask.mapPixels(in: IntRect(x: 58, y: 63, width: 16, height: 9)) { x, y, _ in
        let coverage = Float((x + 2 * y) % 13) / 12
        return Pixel(coverage, coverage, coverage)
      }
      var properties = MaskProperties()
      properties.linked = false
      properties.density = 0.61
      properties.feather = 1.5
      properties.transform = .translation(1, 2)
      for applyMask in [false, true] {
        layer.mask = applyMask ? mask : nil
        layer.maskProperties = applyMask ? properties : nil
        document.layers = [layer]
        let cache = GroupRenderCache(region: region, facts: CompositionFacts(document, vectorViewport: region))
        let isolated = try LayerStyleRenderer.styledContent(layer, clips: [], in: document, cache: cache)
        var original = [Float](repeating: 0, count: stride * (region.height + 2))
        var copied = original
        for y in 0..<region.height {
          for x in 0..<region.width {
            original[start + y * stride + x] = isolated.pixel(x: region.x + x, y: region.y + y).a
          }
        }
        try LayerStyleRenderer.copyShadowAlpha(layer, clips: [], in: document, cache: cache,
          region: region, to: &copied, start: start, stride: stride)
        XCTAssertEqual(copied.map(\.bitPattern), original.map(\.bitPattern), "\(depth), mask \(applyMask)")
      }
    }
  }

  func testUniformDropShadowReductionMatchesStreamedFitWithRasterAndMaskEdits() throws {
    let width = 12_000, height = 800
    let region = IntRect(x: 1, y: 1, width: 319, height: 351)
    let request = try RasterPreviewRequest(region: region, width: 73, height: 79)
    for depth in PixelDepth.allCases {
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var document = try CraftDocument(width: width, height: height, depth: depth)
      var source = try Surface(width: width, height: height, depth: depth,
        fill: Pixel(0.42, 0.27, 0.71, 0.77), colorEncoding: encoding)
      source.setPixel(x: 8, y: 9, Pixel(0.8, 0.4, 0.2, 0.2))
      source.setPixel(x: 13, y: 12, .clear)
      var mask = try Surface(width: width, height: height, fill: .white)
      mask.setPixel(x: 11, y: 15, .black)
      document.layers[0].content = .raster(source)
      document.layers[0].mask = mask
      document.layers[0].opacity = 0.82
      document.globalLight = GlobalLight(angle: 139, altitude: 46)
      for advanced in [false, true] {
        var shadow = LayerEffect(.dropShadow)
        shadow.distance = 48.7
        shadow.size = 10.3
        shadow.spread = 24
        if advanced {
          shadow.advanced = LayerEffectAdvanced()
          shadow.advanced?.contour = EffectContour(name: "Custom", points: [[0, 0], [0.48, 0.62], [1, 1]])
          shadow.advanced?.antiAlias = true
          shadow.advanced?.knocksOut = false
        }
        var style = LayerStyle(effects: [shadow])
        style.fillOpacity = 0.68
        document.layers[0].style = style
        let projection = try RasterPreviewProjection(document, channels: depth == .u16
          ? RGBChannelView(preview: .green) : RGBChannelView(), proof: nil)
        let plan = try XCTUnwrap(UniformShadowPreview(document, region: region))
        let optimized = try plan.imageSamples(request, projection: projection)
        let oracle = try PagedCanvasRenderer.reducedPatternPreview(document, request: request,
          projection: projection, reuseUniformShadows: false)
        XCTAssertEqual(try optimized.rgbaData(depth: .f32, colorEncoding: optimized.colorEncoding),
          try oracle.rgbaData(depth: .f32, colorEncoding: oracle.colorEncoding), "\(depth) advanced \(advanced)")
      }
    }
  }

  func testMaximumUniformDropShadowFitKeepsItsInteriorAndShiftedEdge() throws {
    let size = Surface.maxDimension
    var document = try CraftDocument(width: size, height: size)
    document.layers[0].content = .fill(Pixel(0.68, 0.42, 0.6, 0.72))
    var shadow = LayerEffect(.dropShadow)
    shadow.angle = 180
    shadow.useGlobalLight = false
    shadow.distance = 30_000
    shadow.size = 13
    shadow.opacity = 0.9
    shadow.advanced = LayerEffectAdvanced()
    shadow.advanced?.antiAlias = true
    shadow.advanced?.knocksOut = false
    document.layers[0].style = LayerStyle(effects: [shadow])
    let region = IntRect(x: 0, y: 0, width: size, height: size)
    let request = try RasterPreviewRequest(region: region, width: 200, height: 200)
    let preview = try XCTUnwrap(RasterViewportPreview.pagedPatternPreview(document, request: request))
    XCTAssertTrue(preview.streamsSource)
    let result = try preview.imageSamples(request)
    for x in [5, 100, 190] {
      let sourceX = x * 1500 + 750, sourceY = 150_750
      let pixel = try Renderer.composite(document, region: IntRect(x: sourceX, y: sourceY, width: 1, height: 1))
        .pixel(x: sourceX, y: sourceY)
      XCTAssertTrue(result.pixel(x: x, y: 100).hasSameBits(as: pixel))
    }
    XCTAssertNotEqual(result.pixel(x: 5, y: 100), result.pixel(x: 100, y: 100))
    var noisy = document
    noisy.layers[0].style?.effects[0].advanced?.noise = 0.2
    XCTAssertNil(try UniformShadowPreview(noisy, region: region))
  }

  func testRegionalDropShadowsMatchWholeMapsAcrossTileAndDocumentEdges() throws {
    for depth in PixelDepth.allCases {
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var document = try CraftDocument(width: 78, height: 68, depth: depth)
      var pixels = try Surface(width: 46, height: 43, depth: depth, colorEncoding: encoding)
      for y in 0..<pixels.height { for x in 0..<pixels.width {
        let sample = Pixel(0.41, 0.22, 0.53, Float((7*x+29*y)%29) / 28)
        if depth == .f32 { pixels.setLinearPixel(x: x, y: y, sample) }
        else { pixels.setPixel(x: x, y: y, sample) }
      }}
      document.layers[0].content = .raster(pixels)
      document.layers[0].x = -3
      document.layers[0].y = 34
      document.layers[0].opacity = 0.73
      document.globalLight = .init(angle: 137, altitude: 39)
      let backdrop = try Surface(width: document.width, height: document.height, depth: .f32,
        fill: Pixel(0.64, 0.33, 0.47, 0.56), colorEncoding: encoding)
      let full = IntRect(x: 0, y: 0, width: document.width, height: document.height)
      for advanced in [false, true] {
        var shadow = LayerEffect(.dropShadow)
        shadow.distance = 13.4
        shadow.size = 9.3
        shadow.spread = 41
        if advanced {
          shadow.advanced = LayerEffectAdvanced()
          shadow.advanced?.antiAlias = true
          shadow.advanced?.noise = 0.27
          shadow.advanced?.knocksOut = false
          shadow.advanced?.contour = EffectContour(name: "Custom",
            points: [[0, 0], [0.4, 0.68], [1, 1]], smoothPoints: [false, false, false])
        }
        var other = LayerEffect(.dropShadow)
        other.useGlobalLight = false
        other.angle = -26
        other.distance = 8.6
        other.size = 4.7
        var style = LayerStyle(effects: [shadow, other])
        style.fillOpacity = 0.58
        document.layers[0].style = style
        let layer = document.layers[0]
        let oracle = try LayerStyleRenderer.composite(layer, in: document, over: backdrop, region: full)
        XCTAssertEqual(oracle.pixel(x: 66, y: 43).a, backdrop.pixel(x: 66, y: 43).a)
        for rect in [IntRect(x: 0, y: 31, width: 16, height: 17), IntRect(x: 13, y: 45, width: 28, height: 19),
                     IntRect(x: 9, y: 62, width: 42, height: 6), IntRect(x: 60, y: 34, width: 18, height: 34)] {
          let regional = try LayerStyleRenderer.composite(layer, in: document, over: backdrop,
                                                          region: rect, regionalEffects: true)
          let expected = try oracle.cropped(to: rect).rgbaData(depth: .f32, colorEncoding: encoding)
          let actual = try regional.cropped(to: rect).rgbaData(depth: .f32, colorEncoding: encoding)
          XCTAssertEqual(actual, expected,
                         "\(depth) advanced \(advanced) rect \(rect)")
        }
      }
    }
  }

  func testMaximumCanvasDropShadowFindsDistantSourceAndRetainsSparseOutput() throws {
    let size = Surface.maxDimension
    let shadowX = size - 30_080, y = size - 87
    let region = IntRect(x: shadowX - 10, y: y - 10, width: 44, height: 44)
    for advanced in [false, true] {
      var document = try CraftDocument(width: size, height: size)
      document.layers[0].x = shadowX + 30_000
      document.layers[0].y = y
      document.layers[0].content = .raster(try Surface(width: 19, height: 17, fill: Pixel(0.8, 0.4, 0.2, 0.8)))
      var effect = LayerEffect(.dropShadow)
      effect.distance = 30_000
      effect.size = 7
      effect.spread = 12
      effect.useGlobalLight = false
      effect.angle = 0
      if advanced {
        effect.advanced = LayerEffectAdvanced()
        effect.advanced?.antiAlias = true
        effect.advanced?.noise = 0.17
      }
      try Command.layerStyle([document.layers[0].id], LayerStyle(effects: [effect])).apply(to: &document)
      let cropped = try Renderer.composite(document, region: region)
      let retained = try Renderer.composite(document)
      XCTAssertGreaterThan(cropped.pixel(x: shadowX + 5, y: y + 6).a, 0.15)
      XCTAssertEqual(try retained.cropped(to: region).rgbaData(depth: .u8),
                     try cropped.cropped(to: region).rgbaData(depth: .u8))
      XCTAssertEqual(retained.pixel(x: shadowX + 15_000, y: y + 6), .clear)
      XCTAssertLessThan(retained.allocatedBytes, 4 * 1024 * 1024)

      if advanced {
        var shorter = document
        shorter.width = 4096
        shorter.height = 4096
        shorter.layers[0].x = 1002
        shorter.layers[0].y = 56
        shorter.layers[0].style?.effects[0].distance = 1000
        let psb = try PSDCodec.writeRasterLayers(shorter, format: .psb, maximizeCompatibility: false)
        let reopened = try PSDCodec.read(psb)
        let check = IntRect(x: 0, y: 42, width: 48, height: 50)
        XCTAssertEqual(reopened.layers[0].style?.effects.first, shorter.layers[0].style?.effects.first)
        XCTAssertEqual(try Renderer.composite(reopened, region: check), try Renderer.composite(shorter, region: check))
      }
    }
  }

  func testAdvancedDropShadowPSDAndPSBRetainEditableControlsAndPixels() throws {
    var advanced = LayerEffectAdvanced()
    advanced.noise = 0.35
    advanced.antiAlias = true
    advanced.knocksOut = false
    advanced.contour = EffectContour(name: "Custom",
      points: [[0, 0], [0.25, 0.14], [0.5, 0.85], [0.75, 0.64], [1, 1]],
      smoothPoints: [false, true, false, true, false])
    for depth in [PixelDepth.u8, .u16, .f32] {
      var document = try CraftDocument(width: 28, height: 28, depth: depth)
      var samples = try Surface(width: 12, height: 12, depth: depth, colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      for y in 1..<11 { for x in 1..<11 {
        let sample = Pixel(0.6, 0.2, 0.3, Float(x) / 12)
        if depth == .f32 { samples.setLinearPixel(x: x, y: y, sample) }
        else { samples.setPixel(x: x, y: y, sample) }
      }}
      document.layers[0].x = 6
      document.layers[0].y = 7
      document.layers[0].content = .raster(samples)
      document.globalLight = GlobalLight(angle: 147, altitude: 47)
      var shadow = LayerEffect(.dropShadow)
      shadow.size = 7
      shadow.distance = 2
      shadow.angle = -35
      shadow.useGlobalLight = false
      shadow.advanced = advanced
      var style = LayerStyle(effects: [shadow])
      style.fillOpacity = 0
      document.layers[0].style = style
      func composition(_ document: CraftDocument) throws -> Data {
        try Renderer.composite(document).rgbaData(depth: depth, colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      }
      let original = try composition(document)
      for format in [PSDFileFormat.psd, .psb] {
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
        XCTAssertEqual(reopened.layers[0].style?.effects.first, shadow)
        XCTAssertEqual(try composition(reopened), original)
      }
      var quiet = document
      quiet.layers[0].style?.effects[0].advanced?.noise = 0
      XCTAssertNotEqual(try composition(quiet), original)
      var knockedOut = document
      knockedOut.layers[0].style?.effects[0].advanced?.knocksOut = true
      XCTAssertNotEqual(try composition(knockedOut), original)
      var unrepresentable = document
      unrepresentable.layers[0].style?.effects[0].advanced?.jitter = 0.5
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(unrepresentable))
    }
  }

  func testDropShadowContourCornerAndAntiAliasAffectCoverage() throws {
    let points: [[Float]] = [[0, 0], [0.25, 0.2], [0.5, 0.8], [0.75, 0.3], [1, 1]]
    let smooth = EffectContour(name: "Custom", points: points)
    let corner = EffectContour(name: "Custom", points: points, smoothPoints: [true, true, false, true, true])
    var map = SourceEffectMap(16, 1)
    map.v = (0..<16).map { Float($0) / 15 }
    let aliased = try map.contoured(corner)
    XCTAssertNotEqual(aliased.v, try map.contoured(smooth).v)
    let softened = try map.contoured(corner, antiAlias: true)
    XCTAssertNotEqual(softened.v, aliased.v)
    XCTAssertEqual(softened.v.first, aliased.v.first)
    XCTAssertEqual(softened.v.last, aliased.v.last)
    XCTAssertEqual(try map.contoured(EffectContour(), antiAlias: true).v, map.v)
  }

  func testPatternPreparationSharesAssetsAcrossPlacementsAndStaysWithinBudget() throws {
    var pixels = try Surface(width: 8, height: 8, fill: .white)
    pixels.setPixel(x: 0, y: 0, .black)
    pixels.setPixel(x: 1, y: 3, Pixel(0.1, 0.64, 0.72))
    let pattern = try RasterPattern(name: "Owned preparation control", surface: pixels)
    var document = try CraftDocument(width: 73, height: 91)
    document.patterns = [pattern]
    var fill = PatternFill(patternID: pattern.id)
    fill.placement.angle = 31
    var style = LayerStyle(effects: [])
    style.referenceOffset = PathPoint(-4, 3)
    let layer = document.layers[0]
    let capacity = pixels.width * pixels.height * MemoryLayout<SIMD4<Float>>.stride
    let cache = PatternFillSampler.PreparationCache(byteBudget: capacity)

    func sample(_ fill: PatternFill, on document: CraftDocument, cache: PatternFillSampler.PreparationCache?) throws -> [Pixel] {
      let sampler = try PatternFillSampler.overlay(fill, style: style, layer: layer, in: document, preparation: cache)
      return (-5...17).map { sampler.sample(x: Double($0) + 0.5, y: Double($0) + 2.5) }
    }
    let original = try sample(fill, on: document, cache: cache)
    XCTAssertEqual(cache.retainedBytes, capacity)
    XCTAssertEqual(original, try sample(fill, on: document, cache: nil))
    fill.placement.angle = -31
    style.referenceOffset = PathPoint(8, -3)
    XCTAssertNotEqual(original, try sample(fill, on: document, cache: cache))
    XCTAssertEqual(try sample(fill, on: document, cache: cache), try sample(fill, on: document, cache: nil))
    XCTAssertEqual(cache.retainedBytes, capacity)

    var modified = document
    let replacement = try RasterPattern(name: pattern.name,
      surface: Surface(width: 8, height: 8, fill: Pixel(0.9, 0.2, 0.4)), id: pattern.id)
    modified.patterns = [replacement]
    XCTAssertNotEqual(try sample(fill, on: modified, cache: cache), try sample(fill, on: document, cache: cache))
    XCTAssertEqual(try sample(fill, on: modified, cache: cache), try sample(fill, on: modified, cache: nil))
    XCTAssertEqual(cache.retainedBytes, capacity)

    fill.placement.angle = 0
    fill.placement.scale = 25
    let legacy = PatternFillSampler.PreparationCache()
    XCTAssertEqual(try sample(fill, on: document, cache: legacy), try sample(fill, on: document, cache: nil))
    let legacyBytes = legacy.retainedBytes
    XCTAssertGreaterThan(legacyBytes, 0)
    fill.placement.scale = 22.5
    fill.placement.phaseY = -0.375
    XCTAssertEqual(try sample(fill, on: document, cache: legacy), try sample(fill, on: document, cache: nil))
    XCTAssertEqual(legacy.retainedBytes, legacyBytes)
    XCTAssertEqual(try sample(fill, on: document, cache: cache), try sample(fill, on: document, cache: nil))
    XCTAssertEqual(cache.retainedBytes, capacity)
    fill.placement.scale = 37.5
    XCTAssertEqual(try sample(fill, on: document, cache: legacy), try sample(fill, on: document, cache: nil))
    XCTAssertGreaterThan(legacy.retainedBytes, legacyBytes)
  }

  func testPagedObliquePatternReductionMatchesStoredTilesAndFractionalEdges() throws {
    let size = Surface.maxDimension
    let region = IntRect(x: size - 3_083, y: size - 208, width: 2_149, height: 137)
    let request = try RasterPreviewRequest(region: region, width: 73, height: 43)
    var tile = try Surface(width: 3, height: 5, fill: .white)
    tile.setPixel(x: 0, y: 0, .black)
    tile.setPixel(x: 2, y: 3, Pixel(0.1, 0.5, 0.8, 0.6))
    let pattern = try RasterPattern(name: "Owned oblique reduction control", surface: tile)
    for depth in PixelDepth.allCases {
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var document = try CraftDocument(width: size, height: size, depth: depth)
      var raster = try Surface(width: size, height: size, depth: depth, fill: Pixel(0.6, 0.3, 0.9, 0.85),
        colorEncoding: encoding)
      raster.setPixel(x: region.x + 2_047, y: region.y + 64, Pixel(0.1, 0.6, 0.3, 0.4))
      document.layers[0].content = .raster(raster)
      document.patterns = [pattern]
      var effect = LayerEffect(.patternOverlay)
      effect.pattern = PatternFill(patternID: pattern.id)
      effect.pattern?.placement.angle = 31
      effect.pattern?.placement.scale = 56
      effect.pattern?.placement.phaseY = -0.375
      effect.opacity = 0.7
      var style = LayerStyle(effects: [effect])
      style.referenceOffset = PathPoint(-3, 6)
      try Command.layerStyle([document.layers[0].id], style).apply(to: &document)
      let retained = try PagedCanvasRenderer.composite(document, region: region)
      var proof = ProofSettings()
      proof.enabled = true
      for (channels, settings) in [(RGBChannelView(), nil), (RGBChannelView(preview: .green), nil), (.init(), proof)] {
        let projection = try RasterPreviewProjection(document, channels: channels, proof: settings)
        let control = try request.reducing(projection.apply(retained))
        let reduced = try PagedCanvasRenderer.reducedPatternPreview(document, request: request, projection: projection)
        XCTAssertEqual(reduced, control, "\(depth), \(channels), proof \(settings != nil)")
      }
    }
  }

  func testPagedPatternProofPreservesImplicitBackdropAtMaximumExtent() throws {
    let size = Surface.maxDimension
    var document = try CraftDocument(width: size, height: size)
    document.layers[0].content = .fill(Pixel(0.65, 0.23, 0.11, 0.9))
    var source = Layer(name: "Owned oblique layer", content: .raster(try Surface(width: 15, height: 17, fill: .white)))
    source.x = size - 21
    source.y = size - 25
    var tile = try Surface(width: 2, height: 3, fill: .white)
    tile.setPixel(x: 0, y: 0, .black)
    let pattern = try RasterPattern(name: "Owned sparse pattern", surface: tile)
    document.patterns = [pattern]
    var overlay = LayerEffect(.patternOverlay)
    overlay.pattern = PatternFill(patternID: pattern.id)
    overlay.pattern?.placement.angle = 31
    overlay.pattern?.placement.scale = 56
    document.layers.append(source)
    try Command.layerStyle([source.id], LayerStyle(effects: [overlay])).apply(to: &document)
    let request = try RasterPreviewRequest.overview(width: size, height: size, maximumSide: 41)
    let preview = try XCTUnwrap(RasterViewportPreview.pagedPatternPreview(document, request: request))
    XCTAssertTrue(preview.streamsSource)
    let retained = try Renderer.composite(document)
    XCTAssertEqual(try preview.pixel(x: source.x + 5, y: source.y + 7), retained.pixel(x: source.x + 5, y: source.y + 7))
    XCTAssertEqual(try preview.imageSamples(request), try request.reducing(retained))
    var proof = ProofSettings()
    proof.enabled = true
    let proofControl = try request.reducing(SoftProof.surface(document, composite: retained, settings: proof))
    XCTAssertEqual(try preview.imageSamples(request, proof: proof), proofControl)
  }

  func testQuarterTurnPatternFitPreservesOrdinaryRenderAcrossMaximumCanvas() throws {
    let size = Surface.maxDimension
    let canvas = IntRect(x: 0, y: 0, width: size, height: size)
    var pixels = try Surface(width: 3, height: 5, fill: .white)
    pixels.setPixel(x: 0, y: 0, .black)
    pixels.setPixel(x: 2, y: 3, Pixel(0.1, 0.5, 0.8, 0.6))
    let pattern = try RasterPattern(name: "Owned asymmetric quarter-turn control", surface: pixels)

    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: size, height: size, depth: depth)
      document.layers[0].content = .raster(try Surface(width: size, height: size, depth: depth, fill: .white,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB))
      document.patterns = [pattern]
      var overlay = LayerEffect(.patternOverlay)
      var fill = PatternFill(patternID: pattern.id)
      var style = LayerStyle(effects: [overlay])
      style.referenceOffset = PathPoint(17, -11)
      let layerID = document.layers[0].id
      for (angle, scale, phaseX, phaseY, swapsAxes) in [
        (90, 200, 0, 0, true), (-90, 200, 0, 0, true), (180, 200, 0, 0, false),
        (360, 200, 0, 0, false), (90, 100, 0.125, -0.375, true), (180, 100, 0.125, -0.375, false),
      ] as [(Float, Float, Float, Float, Bool)] {
        fill.placement.scale = scale
        fill.placement.angle = angle
        fill.placement.phaseX = phaseX
        fill.placement.phaseY = phaseY
        overlay.pattern = fill
        style.effects = [overlay]
        try Command.layerStyle([layerID], style).apply(to: &document)
        let repeatCount = Int(scale / 100)
        let cellWidth = repeatCount * (swapsAxes ? pixels.height : pixels.width)
        let cellHeight = repeatCount * (swapsAxes ? pixels.width : pixels.height)
        let preview = try XCTUnwrap(PatternCanvasPreview(document), "\(depth), \(angle)°, \(scale)%")
        for (x, y) in [(0, 0), (size - 31, size - 29), (size - 37, 47), (53, size - 43)] {
          let rect = IntRect(x: x, y: y, width: cellWidth * 2, height: cellHeight * 2)
          let request = try RasterPreviewRequest(region: rect, width: rect.width, height: rect.height)
          let control = try Renderer.composite(document, region: rect).cropped(to: rect)
          XCTAssertEqual(try preview.imageSamples(request).rgbaData(depth: depth),
            try control.rgbaData(depth: depth), "\(depth), \(angle)°, \(scale)%, \(x), \(y)")
        }
        let cell = IntRect(x: 0, y: 0, width: cellWidth, height: cellHeight)
        let reference = try Renderer.composite(document, region: cell)
        let fit = try RasterPreviewRequest(region: canvas, width: 1, height: 1)
        let average = try reference.reducedPreview(in: cell, width: 1, height: 1)
        XCTAssertEqual(try preview.imageSamples(fit).rgbaData(depth: depth), try average.rgbaData(depth: depth))
      }

      // At integral phase and 100%, libm's nonzero cross-axis term can change
      // an ordinary Float32 interpolation. Oblique angles and non-dyadic
      // scales also lack this proof and must keep the regional renderer.
      fill.placement.phaseX = 0
      fill.placement.phaseY = 0
      for (angle, scale) in [(90, 100), (31, 200), (90, 56)] as [(Float, Float)] {
        fill.placement.angle = angle
        fill.placement.scale = scale
        overlay.pattern = fill
        style.effects = [overlay]
        try Command.layerStyle([layerID], style).apply(to: &document)
        XCTAssertNil(try PatternCanvasPreview(document))
      }
    }
  }

  func testRotatedPatternViewportPreservesExactPanOverlapAndResampling() throws {
    let size = Surface.maxDimension
    let left = IntRect(x: size - 800, y: size - 600, width: 232, height: 140)
    let right = IntRect(x: size - 700, y: size - 565, width: 228, height: 168)
    let overlap = IntRect(x: right.x, y: right.y, width: 132, height: 105)
    var tile = try Surface(width: 4, height: 4, fill: .white)
    tile.setPixel(x: 0, y: 0, .black)
    tile.setPixel(x: 2, y: 1, Pixel(0.2, 0.7, 0.3, 0.4))
    let asset = try RasterPattern(name: "Owned viewport tile", surface: tile)
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: size, height: size, depth: depth)
      var base = try Surface(width: size, height: size, depth: depth, fill: .white,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      base.setPixel(x: overlap.x + 3, y: overlap.y + 6, Pixel(0.3, 0.2, 0.7, 0.6))
      document.layers[0].content = .raster(base)
      var mask = try Surface(width: size, height: size, fill: .white)
      mask.setPixel(x: overlap.x + 2, y: overlap.y + 4, .black)
      document.layers[0].mask = mask
      document.patterns = [asset]
      var overlay = LayerEffect(.patternOverlay)
      overlay.pattern = PatternFill(patternID: asset.id)
      overlay.pattern?.placement.scale = 56
      overlay.pattern?.placement.angle = 31
      overlay.pattern?.placement.phaseX = 4.25
      overlay.opacity = 0.5
      var style = LayerStyle(effects: [overlay])
      style.referenceOffset = PathPoint(-2, 5)
      try Command.layerStyle([document.layers[0].id], style).apply(to: &document)
      XCTAssertNil(try PatternCanvasPreview(document))
      func source(_ region: IntRect) throws -> Surface {
        let request = try RasterPreviewRequest(region: region, width: region.width, height: region.height)
        let view = try RasterViewportPreview(document, request: request)
        XCTAssertNil(try view.pixel(x: region.x - 1, y: region.y))
        let original = try Renderer.composite(document, region: region)
        XCTAssertEqual(try view.pixel(x: overlap.x + 3, y: overlap.y + 6),
          original.pixel(x: overlap.x + 3, y: overlap.y + 6))
        XCTAssertEqual(try view.imageSamples(request).rgbaData(depth: depth),
          try original.cropped(to: region).rgbaData(depth: depth))
        return try view.imageSamples(request).cropped(to: IntRect(x: overlap.x - region.x,
          y: overlap.y - region.y, width: overlap.width, height: overlap.height))
      }
      XCTAssertEqual(try source(left).rgbaData(depth: depth), try source(right).rgbaData(depth: depth))
      let reduced = try RasterPreviewRequest(region: overlap, width: 67, height: 49)
      let channels = RGBChannelView(preview: .green)
      let reference = try channels.applying(to: Renderer.composite(document, region: overlap))
      XCTAssertEqual(try RasterViewportPreview(document, request: reduced).imageSamples(reduced, channels: channels)
        .rgbaData(depth: .u8), try reduced.reducing(reference).rgbaData(depth: .u8))
    }
  }

  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 24, height: 24, depth: depth)
    var s = try Surface(width: 24, height: 24, depth: depth, colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    for y in 8..<16 { for x in 8..<16 { s.setPixel(x:x,y:y,Pixel(0.4,0.6,0.8)) } }
    d.layers[0].content = .raster(s)
    var tile = try Surface(width: 2,height:2,fill:.white);tile.setPixel(x:0,y:0,.black);tile.setPixel(x:1,y:1,.black)
    d.patterns = [try RasterPattern(name:"Checker",surface:tile,id:"style-checker")]
    return d
  }
  func effect(_ kind: LayerEffect.Kind) -> LayerEffect {
    var effect=LayerEffect(kind)
    if kind == .gradientOverlay { effect.gradient=GradientFill(gradient:.blackToWhite) }
    if kind == .patternOverlay { effect.pattern=PatternFill(patternID:"style-checker") }
    return effect
  }

  func testMaximumPatternOverlayMatchesSmallControlAcrossPagedTiles() throws {
    let maximum = Surface.maxDimension
    let bigX = maximum - 34, bigY = maximum - 36
    let controlX = 14, controlY = 12
    let region = IntRect(x: bigX - 4, y: bigY - 4, width: 30, height: 30)
    let control = IntRect(x: controlX - 4, y: controlY - 4, width: 30, height: 30)
    var tile = try Surface(width: 4, height: 4, fill: .white)
    tile.setPixel(x: 0, y: 0, .black)
    let pattern = try RasterPattern(name: "Owned pattern", surface: tile)
    for depth in PixelDepth.allCases {
      var raster = try Surface(width: 24, height: 24, depth: depth, fill: .white,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      raster.setPixel(x: 1, y: 1, Pixel(1, 1, 1, 128.0 / 255))
      var mask = try Surface(width: 24, height: 24, depth: depth, fill: .white)
      mask.setPixel(x: 2, y: 1, Pixel(0.4, 0.4, 0.4))
      for linkedOrigin in [false, true] {
        var overlay = LayerEffect(.patternOverlay)
        overlay.pattern = PatternFill(patternID: pattern.id)
        overlay.pattern?.placement.scale = 200
        overlay.opacity = 0.5
        var style = LayerStyle(effects: [overlay])
        if linkedOrigin { style.referenceOffset = PathPoint(0, 0) }

        func document(_ size: Int, x: Int, y: Int, background: Bool) throws -> CraftDocument {
          var doc = try CraftDocument(width: size, height: size, depth: depth)
          doc.patterns = [pattern]
          doc.layers[0].content = .raster(raster)
          doc.layers[0].x = x
          doc.layers[0].y = y
          if background { doc.layers[0].mask = mask }
          let id = doc.layers[0].id
          try Command.layerStyle([id], style).apply(to: &doc)
          if background { doc.layers.insert(Layer(name: "Backdrop", content: .fill(Pixel(0.2, 0.4, 0.7, 0.8))), at: 0) }
          return doc
        }

        let small = try document(64, x: controlX, y: controlY, background: true)
        let large = try document(maximum, x: bigX, y: bigY, background: true)
        let expected = try Renderer.composite(small).cropped(to: control).rgbaData(depth: depth)
        let regional = try Renderer.composite(large, region: region).cropped(to: region)
        XCTAssertEqual(try regional.rgbaData(depth: depth), expected, "\(depth) linked origin \(linkedOrigin)")
        let full = try Renderer.composite(large)
        XCTAssertEqual(try full.cropped(to: region).rgbaData(depth: depth), expected)
        XCTAssertEqual(full.pixel(x: 0, y: 0), full.pixel(x: maximum - 1, y: maximum - 1))
        XCTAssertLessThan(full.allocatedBytes, 4 * 1024 * 1024)

        if depth == .u8 && linkedOrigin {
          let standalone = try document(4096, x: controlX, y: controlY, background: false)
          let psb = try PSDCodec.writeRasterLayers(standalone, format: .psb, maximizeCompatibility: false)
          XCTAssertLessThan(psb.count, 1024 * 1024)
          let reopened = try PSDCodec.read(psb)
          XCTAssertEqual(reopened.width, standalone.width)
          XCTAssertEqual(reopened.height, standalone.height)
          XCTAssertEqual(reopened.layers[0].style?.effects[0].kind, .patternOverlay)
          let authored = try Renderer.composite(standalone, region: control).cropped(to: control)
          XCTAssertEqual(try Renderer.composite(reopened, region: control).cropped(to: control).rgbaData(depth: .u8),
            try authored.rgbaData(depth: .u8))
          let sample = (4 * control.width + 4) * 4
          XCTAssertEqual(Array(try authored.rgbaData(depth: .u8)[sample..<(sample + 4)]), [127, 127, 127, 255])
        }
      }
    }
  }

  func testOpaquePatternPreviewMatchesFullCompositeWithSparseEditsAndMasks() throws {
    let maximum = Surface.maxDimension, offset = 299_520
    var repeatPixels = try Surface(width: 4, height: 4, fill: .white)
    repeatPixels.setPixel(x: 0, y: 0, .black)
    repeatPixels.setPixel(x: 1, y: 2, Pixel(0.2, 0.6, 0.4))
    let pattern = try RasterPattern(name: "Owned repeating control", surface: repeatPixels)
    var overlay = LayerEffect(.patternOverlay)
    overlay.pattern = PatternFill(patternID: pattern.id)
    overlay.pattern?.placement.scale = 200
    overlay.opacity = 0.63
    var style = LayerStyle(effects: [overlay])
    style.referenceOffset = PathPoint(3, -2)
    style.fillOpacity = 0.89

    for depth in PixelDepth.allCases {
      func fixture(width: Int, height: Int, origin: Int) throws -> CraftDocument {
        var document = try CraftDocument(width: width, height: height, depth: depth)
        document.patterns = [pattern]
        var raster = try Surface(width: width, height: height, depth: depth, fill: Pixel(0.7, 0.5, 0.3),
          colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
        raster.setPixel(x: origin + 64, y: origin + 63, Pixel(0.2, 0.7, 0.9, 0.5))
        var mask = try Surface(width: width, height: height, depth: .u8, fill: .white)
        mask.setPixel(x: origin + 7, y: origin + 10, .black)
        document.layers[0].content = .raster(raster)
        document.layers[0].mask = mask
        try Command.layerStyle([document.layers[0].id], style).apply(to: &document)
        let foreground = try Surface(width: 7, height: 6, depth: depth, fill: Pixel(0.1, 0.3, 0.7, 0.6),
          colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
        var detail = Layer(name: "Local edit", content: .raster(foreground))
        detail.x = origin + 120
        detail.y = origin + 60
        document.layers.append(detail)
        return document
      }
      let large = try fixture(width: maximum, height: maximum, origin: offset)
      let small = try fixture(width: 192, height: 176, origin: 0)
      let repeating = try XCTUnwrap(PatternCanvasPreview(large))
      let reference = try Renderer.composite(small)
      let region = IntRect(x: 3, y: 2, width: 137, height: 107)
      let translated = IntRect(x: offset + region.x, y: offset + region.y, width: region.width, height: region.height)
      let units = try RasterPreviewRequest(region: translated, width: region.width, height: region.height)
      XCTAssertEqual(try repeating.imageSamples(units).rgbaData(depth: depth),
        try reference.cropped(to: region).rgbaData(depth: depth), "\(depth) unit view")
      XCTAssertEqual(try repeating.pixel(x: offset + 64, y: offset + 63), reference.pixel(x: 64, y: 63))
      XCTAssertEqual(try repeating.pixel(x: offset + 77, y: offset + 78), reference.pixel(x: 77, y: 78))

      let reduced = try RasterPreviewRequest(region: translated, width: 23, height: 19)
      let referenceRequest = try RasterPreviewRequest(region: region, width: 23, height: 19)
      XCTAssertEqual(try repeating.imageSamples(reduced).rgbaData(depth: .u8),
        try referenceRequest.reducing(reference).rgbaData(depth: .u8), "\(depth) reduced view")
      let channel = RGBChannelView(preview: .green)
      let original = try Renderer.composite(large, region: translated)
      let channelReference = try reduced.reducing(channel.applying(to: original))
      XCTAssertEqual(try repeating.imageSamples(reduced, channels: channel).rgbaData(depth: .u8),
        try channelReference.rgbaData(depth: .u8), "\(depth) isolated channel")
      var proof = ProofSettings()
      proof.enabled = true
      let proofReference = try referenceRequest.reducing(SoftProof.surface(small, composite: reference, settings: proof))
      XCTAssertEqual(try repeating.imageSamples(reduced, proof: proof).rgbaData(depth: .u8),
        try proofReference.rgbaData(depth: .u8), "\(depth) soft proof")
    }
  }

  func testOpaquePatternOverviewIntegratesWholeRepeatAtMaximumSize() throws {
    let size = Surface.maxDimension
    var document = try CraftDocument(width: size, height: size)
    document.layers[0].content = .raster(try Surface(width: size, height: size, fill: .white))
    var samples = try Surface(width: 4, height: 4, fill: .white)
    samples.setPixel(x: 0, y: 0, .black)
    let asset = try RasterPattern(name: "Area integration control", surface: samples)
    document.patterns = [asset]
    var overlay = LayerEffect(.patternOverlay)
    overlay.pattern = PatternFill(patternID: asset.id)
    overlay.pattern?.placement.scale = 200
    overlay.opacity = 0.5
    var style = LayerStyle(effects: [overlay])
    style.referenceOffset = PathPoint(0, 0)
    try Command.layerStyle([document.layers[0].id], style).apply(to: &document)
    let request = try RasterPreviewRequest.overview(width: size, height: size, maximumSide: 25)
    let repeating = try XCTUnwrap(PatternCanvasPreview(document))
    let result = try repeating.imageSamples(request)
    // Every 12,000-pixel footprint contains a whole number of repeats.
    // Black contributes one texel in sixteen at byte opacity 128/255.
    let sample: [UInt8] = [247, 247, 247, 255]
    XCTAssertEqual(try result.rgbaData(depth: .u8), Data(Array(repeating: sample, count: 25 * 25).joined()))
    let region = IntRect(x: size - 81, y: size - 100, width: 47, height: 83)
    let crop = try RasterPreviewRequest(region: region, width: region.width, height: region.height)
    for scale: Float in [75, 150, 300] {
      document.layers[0].style?.effects[0].pattern?.placement.scale = scale
      document.layers[0].style?.effects[0].pattern?.placement.phaseX = 0.25
      let samples = try XCTUnwrap(PatternCanvasPreview(document)).imageSamples(crop)
      XCTAssertEqual(try samples.rgbaData(depth: .u8),
        try Renderer.composite(document, region: region).cropped(to: region).rgbaData(depth: .u8), "\(scale)% repeat")
    }
    document.layers[0].style?.effects[0].pattern?.placement.angle = 30
    XCTAssertNil(try PatternCanvasPreview(document))
  }
  func testAllTenEffectsAtAllDepthsRenderHistoryAndNativeArchives() throws {
    for depth in PixelDepth.allCases { for kind in LayerEffect.Kind.allCases {
      let original=try fixture(depth), baseline=try Renderer.composite(original)
      var session=EditorSession(document:original)
      try session.execute(.layerStyle([original.layers[0].id],LayerStyle(effects:[effect(kind)])))
      let changed=session.document
      XCTAssertNotEqual(try Renderer.composite(changed).rgbaData(depth:.u16),try baseline.rgbaData(depth:.u16),"\(kind) \(depth)")
      for bytes in [try NativeArchive.encode(changed),try NativeArchive.encodeChunked(changed)] {
        XCTAssertEqual(try NativeArchive.decode(bytes),changed)
      }
      try session.undo();XCTAssertEqual(session.document,original)
      try session.redo();XCTAssertEqual(session.document,changed)
    } }
  }
  func testSolidOverlayAndFillOpacityHaveKnownPixels() throws {
    var d=try fixture(),overlay=LayerEffect(.colorOverlay)
    overlay.color=Pixel(1,0,0);overlay.opacity=1
    var style=LayerStyle(effects:[overlay]);style.fillOpacity=0
    try Command.layerStyle([d.layers[0].id],style).apply(to:&d)
    let output=try Renderer.composite(d)
    XCTAssertEqual(output.pixel(x:10,y:10),Pixel(1,0,0))
    XCTAssertEqual(output.pixel(x:0,y:0).a,0)
    style.enabled=false;d.layers[0].style=style
    XCTAssertEqual(try Renderer.composite(d).pixel(x:10,y:10).a,0)
  }
  func testShadowPlacementAndOpacityArePredictable() throws {
    var d=try fixture(),shadow=LayerEffect(.dropShadow)
    shadow.size=0;shadow.distance=5;shadow.angle=180;shadow.useGlobalLight=false;shadow.opacity=1;shadow.blendMode = .normal
    d.layers[0].style=LayerStyle(effects:[shadow])
    XCTAssertEqual(try Renderer.composite(d).pixel(x:19,y:10),.black)
    XCTAssertEqual(try Renderer.composite(d).pixel(x:3,y:10).a,0)
    d.layers[0].opacity=0
    XCTAssertEqual(try Renderer.composite(d).pixel(x:19,y:10).a,0)
  }
  func testEditingPixelsAndIncrementalRenderingRefreshEffects() throws {
    var d=try fixture();d.layers[0].style=LayerStyle(effects:[effect(.stroke)])
    let before=try Renderer.render(d)
    try Command.move(d.layers[0].id,4,0).apply(to:&d)
    let after=try Renderer.render(d,reusing:before)
    XCTAssertEqual(try after.surface.rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8))
    XCTAssertNotEqual(try before.surface.rgbaData(depth:.u8),try after.surface.rgbaData(depth:.u8))
  }
  func testPSDAndPSBRepresentedEffectsRemainEditable() throws {
    for kind in PSDLayerStyles.kinds.map(\.2) { for format in PSDFileFormat.allCases {
      var d=try fixture();d.layers[0].style=LayerStyle(effects:[effect(kind)])
      let read=try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
      XCTAssertEqual(read.layers[0].style?.effects.first?.kind,kind)
      XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8),"\(kind)")
    } }
    var d=try fixture();d.layers[0].style=LayerStyle(effects:[effect(.bevelEmboss)])
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
  }
  func testPhotoshopGradientOverlaysStayEditableWithOriginalRecords() throws {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PSDGradientOverlay")
    let cases: [(name: String, angle: Float, scale: Float, offsetX: Float, offsetY: Float, reversed: Bool)] = [
      ("shape--90-odd", -90, 1, 0, 0, false),
      ("shape--90-scale150-shift", -90, 1.5, 0.5, 0.25, true),
      ("shape-90-alpha-color", 90, 1, 0.25, -0.25, false),
    ]
    // Independent samples extracted from the stored Photoshop composite at x=60.
    let referenceRows: [[(y: Int, rgba: [UInt8])]] = [
      [(21, [0, 0, 0, 255]), (29, [120, 120, 120, 255]), (37, [240, 240, 240, 255])],
      [(48, [255, 255, 255, 255]), (56, [212, 212, 212, 255]), (72, [128, 128, 128, 255])],
      [(48, [123, 107, 52, 255]), (50, [107, 95, 57, 255]), (56, [66, 64, 64, 255]),
       (58, [54, 54, 64, 255])],
    ]
    let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map { URL(fileURLWithPath: $0) }
    for (entry, rows) in zip(cases, referenceRows) {
      let input = try Data(contentsOf: folder.appendingPathComponent(entry.name + ".psd"))
      let document = try PSDCodec.read(input)
      let layer = try XCTUnwrap(document.layers.first)
      let style = try XCTUnwrap(layer.style)
      XCTAssertEqual(style.effects.map(\.kind), [.gradientOverlay])
      let fill = try XCTUnwrap(style.effects.first?.gradient)
      XCTAssertEqual(fill.placement.angle, entry.angle)
      XCTAssertEqual(fill.placement.scale, entry.scale)
      XCTAssertEqual(fill.placement.offsetX, entry.offsetX)
      XCTAssertEqual(fill.placement.offsetY, entry.offsetY)
      XCTAssertEqual(fill.placement.reverse, entry.reversed)
      XCTAssertTrue(fill.aligned)
      XCTAssertFalse(fill.dither)
      XCTAssertEqual(fill.gradient.opacity.map(\.opacity), entry.angle == 90 ? [0.2, 230.0 / 255] : [1, 1])
      let composite = try Renderer.composite(document)
      for row in rows {
        let pixel = composite.pixel(x: 60, y: row.y)
        XCTAssertEqual([pixel.r, pixel.g, pixel.b, pixel.a].map { UInt8((unit($0) * 255).rounded()) }, row.rgba,
          "\(entry.name) row \(row.y)")
      }
      var activeLegacy = try XCTUnwrap(layer.sourceTags?["lrFX"])
      let shadow = try XCTUnwrap(activeLegacy.range(of: Data("8BIMdsdw".utf8)))
      activeLegacy[shadow.upperBound + 4 + 38] = 1
      XCTAssertThrowsError(try PSDLayerStyles.validateInactiveLegacy(activeLegacy))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
      for format in PSDFileFormat.allCases {
        let bytes = try PSDCodec.writeRasterLayers(document, compression: .raw, format: format)
        let read = try PSDCodec.read(bytes)
        XCTAssertEqual(read.layers.first?.style, style)
        XCTAssertEqual(read.layers.first?.sourceTags?["lfx2"], layer.sourceTags?["lfx2"])
        XCTAssertEqual(read.layers.first?.sourceTags?["lrFX"], layer.sourceTags?["lrFX"])
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth: .u8),
          try composite.rgbaData(depth: .u8))
        if let capture {
          try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
          try bytes.write(to: capture.appendingPathComponent(entry.name + (format == .psd ? ".psd" : ".psb")))
        }
        var edited = style
        edited.effects[0].gradient?.placement.angle = 45
        var session = EditorSession(document: document)
        try session.execute(.layerStyle([layer.id], edited))
        let update = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
        XCTAssertEqual(update.layers.first?.style?.effects.first?.gradient, edited.effects[0].gradient)
        XCTAssertNotEqual(update.layers.first?.sourceTags?["lfx2"], layer.sourceTags?["lfx2"])
        try session.undo()
        XCTAssertEqual(session.document, document)
      }
    }
  }
  func testPhotoshopPatternOverlaysStayEditableWithOriginalReferences() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/reference-patterns.psd")
    let document = try PSDCodec.read(fixture)
    let overlays = document.layers.filter { $0.style?.effects.first?.kind == .patternOverlay }
    XCTAssertEqual(overlays.count, 6)
    XCTAssertEqual(document.layers.count, 13)
    for layer in overlays {
      let style = try XCTUnwrap(layer.style), effect = try XCTUnwrap(style.effects.first)
      let pattern = try XCTUnwrap(effect.pattern)
      XCTAssertEqual(effect.opacity, 0.5)
      XCTAssertEqual(pattern.placement.scale, 200)
      XCTAssertTrue(pattern.linked)
      XCTAssertNotNil(document.pattern(pattern.patternID))
      let rawPoint = try PSDPatternFill.referencePoint(XCTUnwrap(layer.sourceTags?["fxrp"]))
      XCTAssertEqual(style.patternReference(in: layer), rawPoint)
    }
    let composite = try Renderer.composite(document)
    // Values sampled directly from the saved RGB planes of reference-patterns.psd.
    let reference: [(Int, Int, [UInt8])] = [
      (22, 142, [177, 177, 177]), (23, 143, [176, 176, 176]), (26, 148, [233, 233, 233]),
      (81, 142, [105, 105, 105]), (82, 143, [169, 169, 169]), (85, 148, [233, 233, 233]),
      (140, 142, [233, 233, 233]), (141, 143, [233, 233, 233]), (144, 148, [169, 169, 169]),
      (199, 142, [233, 233, 233]), (200, 143, [233, 233, 233]), (203, 148, [233, 233, 233]),
      (22, 201, [125, 105, 157]), (23, 202, [122, 105, 150]), (26, 207, [132, 125, 197]),
      (81, 201, [199, 197, 106]), (82, 202, [196, 193, 106]), (85, 207, [198, 195, 127]),
    ]
    let crop = IntRect(x: 12, y: 125, width: 210, height: 96)
    let viewport = try RasterViewportPreview(document,
      request: RasterPreviewRequest(region: crop, width: crop.width, height: crop.height))
    for (x, y, rgb) in reference {
      let p = try XCTUnwrap(viewport.pixel(x: x, y: y))
      XCTAssertEqual(p, composite.pixel(x: x, y: y))
      XCTAssertEqual([p.r, p.g, p.b].map { UInt8((unit($0) * 255).rounded()) }, rgb, "At \(x),\(y)")
    }
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
    let active = try XCTUnwrap(overlays.last)
    var style = try XCTUnwrap(active.style)
    style.effects[0].pattern?.placement.phaseX = 3.5
    style.effects[0].pattern?.placement.angle = 20
    var session = EditorSession(document: document)
    try session.execute(.layerStyle([active.id], style))
    for format in PSDFileFormat.allCases {
      let pristine = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      XCTAssertEqual(try Renderer.composite(pristine), composite)
      for layer in overlays {
        let restored = try XCTUnwrap(pristine.layers.first { $0.name == layer.name })
        XCTAssertEqual(restored.sourceTags?["fxrp"], layer.sourceTags?["fxrp"])
        XCTAssertEqual(restored.sourceTags?["lfx2"], layer.sourceTags?["lfx2"])
        XCTAssertEqual(restored.style, layer.style)
      }
      let edited = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
      let editedLayer = try XCTUnwrap(edited.layers.first { $0.name == active.name })
      XCTAssertEqual(editedLayer.style, style)
      XCTAssertEqual(try Renderer.composite(edited), try Renderer.composite(session.document))
    }
    try session.undo()
    XCTAssertEqual(session.document, document)
  }

  func testStrictValidationLocksAndMergePreventSilentLoss() throws {
    for json in [#"{"bogus":1}"#, #"{"effects":[{"kind":"unknown"}]}"#, #"{"effects":[{"kind":"dropShadow","size":true}]}"#,
      #"{"effects":[{"kind":"gradientOverlay"}]}"#, #"{"effects":[{"kind":"stroke","size":251}]}"#] {
      XCTAssertThrowsError(try LayerStyle.decodeJSON(Data(json.utf8)))
    }
    var d=try fixture();d.layers[0].locked=true;let before=d
    XCTAssertThrowsError(try Command.layerStyle([d.layers[0].id],LayerStyle()).apply(to:&d));XCTAssertEqual(d,before)
    d.layers[0].locked=false;d.layers[0].style=LayerStyle(effects:[effect(.dropShadow)])
    let second=Layer(name:"Second",content:.raster(try Surface(width:24,height:24)))
    d.layers.append(second);d.activeLayerID=second.id
    XCTAssertThrowsError(try Command.mergeLayers(Set(d.layers.map(\.id)),.selected).apply(to:&d))
  }
  func testEffectsOnTextShapesGroupsAndMaskedContent() throws {
    var d = try fixture()
    for content: LayerContent in [.text(TextContent(text: "A", size: 16)), .shape(ShapeContent(kind: .ellipse, width: 12, height: 12, color: .white))] {
      d.layers[0].content = content; d.layers[0].style = nil
      let plain = try Renderer.composite(d)
      d.layers[0].style = LayerStyle(effects: [effect(.colorOverlay)])
      XCTAssertNotEqual(try Renderer.composite(d).rgbaData(depth: .u8), try plain.rgbaData(depth: .u8))
    }
    d = try fixture()
    let group = Layer(name: "Group", content: .group(GroupContent()))
    d.layers[0].parentID = group.id; d.layers.append(group)
    d.layers[1].style = LayerStyle(effects: [effect(.stroke)])
    XCTAssertGreaterThan(try Renderer.composite(d).pixel(x: 7, y: 10).a, 0)
    d.layers[1].mask = try Surface(width: 24, height: 24, fill: .black)
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 7, y: 10).a, 0)
  }
  func testMultiplePSDShadowsAndUnsupportedContourGuard() throws {
    var first=effect(.dropShadow),second=effect(.dropShadow);first.distance=3;second.distance=8
    let bytes=try PSDLayerStyles.write(LayerStyle(effects:[first,second]))
    XCTAssertEqual(try PSDLayerStyles.read(bytes).effects.count,2)
    var descriptor=try PSDDescriptor.read(Data(bytes.dropFirst(4)))
    descriptor.items.append(.init("ebbl",.object(PSDDescriptor("ebbl"))))
    XCTAssertThrowsError(try PSDLayerStyles.read(Data(repeating:0,count:4)+descriptor.encoded()))
  }
}
