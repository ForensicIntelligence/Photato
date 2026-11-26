import XCTest
@testable import PhotoCraftCore

final class VanishingTests:XCTestCase {
  func cameraPlane()->VanishingSettings {
    let rx=0.6,ry=0.4
    let corners=[SIMD3<Double>(-1,-0.5,0),.init(1,-0.5,0),.init(1,0.5,0),.init(-1,0.5,0)].map { p in
      let q=SIMD3<Double>(p.x,cos(rx)*p.y-sin(rx)*p.z,sin(rx)*p.y+cos(rx)*p.z),r=SIMD3<Double>(cos(ry)*q.x+sin(ry)*q.z,q.y,-sin(ry)*q.x+cos(ry)*q.z)+SIMD3(0,0,4)
      return PathPoint(400+500*r.x/r.z,300+500*r.y/r.z)
    }
    var s=VanishingSettings();s.planes=[.init(corners:corners)];return s
  }
  func plain()->VanishingProgram { var p=VanishingProgram();p.settings.planes=[.init(corners:[.init(4,4),.init(60,4),.init(60,44),.init(4,44)])];return p }
  func testMarqueeRectifiesSquaresConstrainsMovesAndTransfersScale() throws {
    var settings = cameraPlane()
    settings.planes.append(.init(corners:[.init(520,320),.init(740,320),.init(740,510),.init(520,510)]))
    let scene = try VanishingScene(settings,width:800,height:600)
    let frame = scene.frames[0]
    let start = frame.point(.init(0.2,0.3))
    let end = frame.point(.init(0.4,0.6))
    let square = try XCTUnwrap(scene.marquee(plane:0,from:start,to:end,square:true))
    XCTAssertEqual(square.width*frame.width,square.height*frame.height,accuracy:1e-10)
    XCTAssertTrue(square.contains(start.interpolated(to:end,at:0.5),in:scene))
    let moved = try XCTUnwrap(square.moved(from:start,to:frame.point(.init(0.35,0.33)),plane:0,
      scene:scene,constrained:true))
    XCTAssertEqual(moved.lower.y,square.lower.y,accuracy:1e-10)
    XCTAssertEqual(moved.lower.x-square.lower.x,0.15,accuracy:1e-10)
    let target = scene.frames[1].point(.init(0.5,0.5))
    let across = try XCTUnwrap(square.moved(from:start,to:target,plane:1,scene:scene))
    XCTAssertEqual(across.lower.x,0.5,accuracy:1e-10)
    XCTAssertEqual(across.width*scene.measurementMetric(for:1).x,
      square.width*scene.measurementMetric(for:0).x,accuracy:1e-8)
  }

  func testMarqueePatchSamplesAlignedPixelsAndHonorsOuterSelection() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width:64,height:48,depth:depth)
      var sample = try Surface(width:64,height:48,depth:depth,fill:Pixel(0.1,0.2,0.3))
      for y in 8..<16 { for x in 8..<16 { sample.setPixel(x:x,y:y,Pixel(Float(x)/32,Float(y)/24,0.85)) } }
      document.layers[0].content = .raster(sample)
      document.selection = .init(x:35,y:25,width:5,height:8)
      var program = VanishingProgram()
      program.settings.planes = [.init(corners:[.init(0,0),.init(64,0),.init(64,48),.init(0,48)])]
      let source = VanishingMarquee(plane:0,lower:.init(8.0/64,8.0/48),upper:.init(16.0/64,16.0/48))
      let destination = VanishingMarquee(plane:0,lower:.init(32.0/64,24.0/48),upper:.init(40.0/64,32.0/48))
      var operation = VanishingOperation(.marquee)
      operation.marquee = .init(source:source,destination:destination,feather:0)
      program.operations = [operation]
      program.newLayer = true
      let edit = try VanishingEdit.prepare(document,layerID:document.layers[0].id,program:program,sample:sample)
      XCTAssertEqual(edit.result.layers[0],document.layers[0])
      guard case .raster(let overlay) = edit.result.layers[1].content else { return XCTFail("Missing patch layer.") }
      let expected = sample.pixel(x:12,y:11)
      let actual = overlay.pixel(x:36,y:27)
      XCTAssertEqual(actual.r,expected.r,accuracy:1e-5)
      XCTAssertEqual(actual.g,expected.g,accuracy:1e-5)
      XCTAssertEqual(actual.b,expected.b,accuracy:1e-5)
      XCTAssertEqual(actual.a,1)
      XCTAssertEqual(overlay.pixel(x:33,y:27).a,0)
      XCTAssertEqual(overlay.pixel(x:12,y:11).a,0)
      program.operations[0].marquee?.feather = 2
      let feathered = try VanishingEngine.render(program,sample:sample)
      XCTAssertLessThan(feathered.pixel(x:32,y:26).a,0.5)
      XCTAssertEqual(feathered.pixel(x:35,y:27).a,1)
    }
  }

  func testFloatingMarqueeUsesCubicDonorSamplesBetweenPixelCenters() throws {
    var sample = try Surface(width:64,height:48,depth:.u8,fill:Pixel(96.0/255,0.25,0.5))
    for y in 8..<16 { sample.setPixel(x:10,y:y,Pixel(160.0/255,0.25,0.5)) }

    var program = VanishingProgram()
    program.settings.planes = [.init(corners:[.init(0,0),.init(64,0),.init(64,48),.init(0,48)])]
    let source = VanishingMarquee(plane:0,lower:.init(8.0/64,8.0/48),upper:.init(16.0/64,16.0/48))
    let destination = VanishingMarquee(plane:0,lower:.init(32.5/64,24.0/48),upper:.init(40.5/64,32.0/48))
    var patch = VanishingOperation(.marquee)
    patch.marquee = .init(source:source,destination:destination,feather:0)
    program.operations = [patch]
    let output = try VanishingEngine.render(program,sample:sample)
    // A half-pixel shift gives weights −1/16, 9/16, 9/16 and −1/16 around the impulse.
    let red = (33...36).map { Int((output.pixel(x:$0,y:28).r*255).rounded()) }
    XCTAssertEqual(red,[92,132,132,92])
    XCTAssertEqual(output.pixel(x:34,y:28).a,1)
    XCTAssertEqual(output.pixel(x:31,y:28).a,0)
  }

  func testLinkedMarqueeFollowsBothPlanesInEitherDragDirection() throws {
    var settings = VanishingSettings()
    settings.center = .init(60,45)
    settings.focalLength = 90
    let top = PathPoint(63.17647058823529,19.85294117647059),bottom = PathPoint(top.x,70.14705882352941)
    settings.planes = [.init(corners:[.init(28.04081632653,27.55102040816),top,bottom,.init(28.04081632653,62.44897959184)])]
    var scene = try VanishingScene(settings,width:120,height:90)
    let child = try scene.calibratedPlane(parent:0,edge:.right,
      corners:[top,.init(87.71863117871,28.74524714829),.init(87.71863117871,61.25475285171),bottom])
    settings.planes.append(child)
    scene = try VanishingScene(settings,width:120,height:90)
    let start = scene.frames[0].point(.init(0.65,0.20)),end = scene.frames[1].point(.init(0.50,0.75))
    let forward = try XCTUnwrap(scene.marquee(plane:0,from:start,to:end,square:false,wrap:true))
    let reverse = try XCTUnwrap(scene.marquee(plane:1,from:end,to:start,square:false,wrap:true))
    let layout = scene.marqueeLayout
    XCTAssertEqual(layout[0].point(forward.lower).x,layout[1].point(reverse.lower).x,accuracy:1e-10)
    XCTAssertEqual(layout[0].point(forward.upper).x,layout[1].point(reverse.upper).x,accuracy:1e-10)
    for plane in 0...1 {
      let local = scene.frames[plane].point(.init(plane == 0 ? 0.85 : 0.20,0.5))
      XCTAssertTrue(forward.contains(local,in:scene,clip:true))
      XCTAssertTrue(reverse.contains(local,in:scene,clip:true))
    }
    let outline = try XCTUnwrap(forward.outlineSegments(in:scene,angle:0,clip:true))
    XCTAssertEqual(outline.count,6)
    XCTAssertFalse(outline.contains { $0.allSatisfy { abs($0.x-top.x) < 1e-8 } })

    let square = try XCTUnwrap(scene.marquee(plane:0,from:start,to:end,square:true,wrap:true))
    XCTAssertEqual(square.width*layout[0].size.x,square.height*layout[0].size.y,accuracy:1e-10)
    let moved = try XCTUnwrap(forward.moved(from:end,to:scene.frames[1].point(.init(0.65,0.77)),plane:1,
      scene:scene,constrained:true))
    XCTAssertEqual(moved.plane,0)
    XCTAssertEqual(moved.lower.y,forward.lower.y,accuracy:1e-10)
    XCTAssertGreaterThan(moved.lower.x,forward.lower.x)
    XCTAssertEqual(moved.width,forward.width,accuracy:1e-10)
  }

  func testWrappedPatchCopiesAcrossHingeWithoutFeatheringOrCompositingTwice() throws {
    var program = VanishingProgram()
    program.settings.focalLength = 90
    let top = PathPoint(63.17647058823529,19.85294117647059),bottom = PathPoint(top.x,70.14705882352941)
    program.settings.planes = [.init(corners:[.init(28.04081632653,27.55102040816),top,bottom,.init(28.04081632653,62.44897959184)])]
    let root = try VanishingScene(program.settings,width:120,height:90)
    program.settings.planes.append(try root.calibratedPlane(parent:0,edge:.right,
      corners:[top,.init(87.71863117871,28.74524714829),.init(87.71863117871,61.25475285171),bottom]))
    let source = VanishingMarquee(plane:0,lower:.init(0.55,0.2),upper:.init(0.95,0.8))
    let destination = VanishingMarquee(plane:0,lower:.init(0.72,0.2),upper:.init(1.30,0.8),wrap:true)
    var operation = VanishingOperation(.marquee)
    operation.marquee = .init(source:source,destination:destination,feather:3)
    operation.opacity = 50
    program.operations = [operation]
    let sample = try Surface(width:120,height:90,depth:.f32,fill:Pixel(0.1,0.3,0.8))
    let overlay = try VanishingEngine.render(program,sample:sample)
    for x in 61...65 {
      let ink = overlay.pixel(x:x,y:45)
      XCTAssertEqual(ink.a,0.5,accuracy:1e-5,"Feather or overlap at the hinge, column \(x)")
      XCTAssertEqual(ink.b,0.8,accuracy:1e-5)
    }
    XCTAssertEqual(overlay.pixel(x:80,y:45).a,0)
    XCTAssertEqual(overlay.pixel(x:63,y:29).a,0)
    program.operations[0].marquee?.destination.wrap = nil
    let old = try VanishingEngine.render(program,sample:sample)
    XCTAssertEqual(old.pixel(x:64,y:45).a,0)

    // Outside both bounded faces, disabling Clip permits the anchor extension.
    program.operations[0].marquee?.destination = .init(plane:0,lower:.init(0.72,-0.20),upper:.init(1.30,0.8),wrap:true)
    let clipped = try VanishingEngine.render(program,sample:sample)
    XCTAssertEqual(clipped.pixel(x:60,y:18).a,0)
    program.operations[0].clip = false
    let extended = try VanishingEngine.render(program,sample:sample)
    XCTAssertGreaterThan(extended.pixel(x:60,y:18).a,0.1)
  }
  func testLinkedBrushCoversBothFacesAndDepositsOnceAtTheHinge() throws {
    var program = VanishingProgram()
    program.settings.planes = [.init(corners:[.init(10,10),.init(36.5,10),.init(36.5,50),.init(10,50)]),
      .init(parent:0,edge:.right,angle:180)]
    var dab = VanishingOperation(.brush)
    dab.color = Pixel(1,0,0)
    dab.diameter = 6
    dab.opacity = 50
    dab.hardness = 100
    dab.points = [.init(36.5,27.5)]
    dab.wrap = true
    program.operations = [dab]
    let canvas = try Surface(width:80,height:64,depth:.f32)
    let hinge = try VanishingEngine.render(program,sample:canvas)
    for x in 35...37 { XCTAssertEqual(hinge.linearPixel(x:x,y:27).a,0.5,accuracy:1e-5) }
    program.operations[0].diameter = 1
    let narrow = try VanishingEngine.render(program,sample:canvas)
    let coverage = narrow.linearPixel(x:36,y:27).a
    XCTAssertGreaterThan(coverage,0.37)
    XCTAssertLessThan(coverage,0.40)
    program.operations[0].diameter = dab.diameter

    program.operations[0].points = [.init(20.5,27.5),.init(69.5,27.5)]
    let clipped = try VanishingEngine.render(program,sample:canvas)
    XCTAssertGreaterThan(clipped.linearPixel(x:48,y:27).a,0.5)
    XCTAssertEqual(clipped.linearPixel(x:67,y:27).a,0)
    program.operations[0].clip = false
    let extended = try VanishingEngine.render(program,sample:canvas)
    XCTAssertGreaterThan(extended.linearPixel(x:67,y:27).a,0.5)
    program.operations[0].wrap = nil
    program.operations[0].clip = true
    let legacy = try VanishingEngine.render(program,sample:canvas)
    XCTAssertEqual(legacy.linearPixel(x:48,y:27).a,0)
  }

  func testLinkedStrokesExtendTheLastFaceWithClippingDisabled() throws {
    var program = VanishingProgram()
    program.settings.center = .init(561,437)
    program.settings.focalLength = 850
    program.settings.planes = [.init(corners:[
      .init(318.10643163755816,273.3813946169246),.init(542.4545454545455,243.8181818181818),
      .init(575.7802140457254,611.6086432104469),.init(359.2816629989663,586.3958041384441)
    ]),.init(parent:0,edge:.right,depth:1.6)]
    program.settings.planes[1].rotationSign = -1
    let canvas = try Surface(width:1200,height:900,depth:.f32)
    var source = canvas
    for y in 320..<490 { for x in 230..<850 {
      source.setLinearPixel(x:x,y:y,Pixel(Float(x)/1000,0.2,0.4))
    } }
    let scene = try VanishingScene(program.settings,width:canvas.width,height:canvas.height)
    for plane in [0,1] {
      var stroke = VanishingOperation(.brush)
      let end = scene.frames[1-plane].point(.init(plane == 0 ? 1.24 : -0.24,0.48))
      XCTAssertNil(scene.plane(at:end))
      stroke.plane = plane
      stroke.points = [scene.frames[plane].point(.init(0.58,0.48)),end]
      stroke.wrap = true
      stroke.diameter = 14
      stroke.hardness = 100
      program.operations = [stroke]
      let pixel = (x:Int(end.x),y:Int(end.y))
      let clipped = try VanishingEngine.render(program,sample:canvas)
      XCTAssertEqual(clipped.linearPixel(x:pixel.x,y:pixel.y).a,0)
      program.operations[0].clip = false
      let extended = try VanishingEngine.render(program,sample:canvas)
      XCTAssertGreaterThan(extended.linearPixel(x:pixel.x,y:pixel.y).a,0.9)

      // A zero-displacement Stamp reads the same position in the extension.
      program.operations[0].kind = .clone
      program.operations[0].sourcePoint = stroke.points.first
      let sampled = try VanishingEngine.render(program,sample:source).linearPixel(x:pixel.x,y:pixel.y)
      let expected = source.linearPixel(x:pixel.x,y:pixel.y)
      XCTAssertEqual(sampled.a,1,accuracy:1e-5)
      XCTAssertEqual(sampled.r,expected.r,accuracy:1e-5)
    }
  }

  func testStraightPerspectiveStrokesUseOnlyTheirEndpoints() throws {
    var program = VanishingProgram()
    program.settings.planes = [.init(corners:[.init(8,10),.init(69,4),.init(64,56),.init(13,49)])]
    let sample = try Surface(width:80,height:64,depth:.f32,fill:Pixel(0.3,0.6,0.9))
    let start = PathPoint(22.5,25.5), end = PathPoint(55.5,25.5)
    let corner = PathPoint(40.5,42.5)
    for kind: VanishingOperation.Kind in [.brush,.clone] {
      var stroke = VanishingOperation(kind)
      stroke.sourcePoint = kind == .clone ? .init(22.5,17.5) : nil
      stroke.diameter = 3
      stroke.hardness = 100
      stroke.points = [start,corner,end]
      program.operations = [stroke]
      XCTAssertGreaterThan(try VanishingEngine.render(program,sample:sample).linearPixel(x:40,y:42).a,0.95)

      stroke.straightStroke = true
      program.operations = [stroke]
      let straight = try VanishingEngine.render(program,sample:sample)
      XCTAssertGreaterThan(straight.linearPixel(x:40,y:25).a,0.95)
      XCTAssertEqual(straight.linearPixel(x:40,y:42).a,0)
      stroke.points = [start,end]
      stroke.straightStroke = nil
      program.operations = [stroke]
      XCTAssertEqual(straight,try VanishingEngine.render(program,sample:sample))
    }
  }

  func testMarqueeConstrainsBrushAndStampAcrossTheHinge() throws {
    var program = VanishingProgram()
    program.settings.planes = [.init(corners:[.init(10,10),.init(36.5,10),.init(36.5,50),.init(10,50)]),
      .init(parent:0,edge:.right,angle:180)]
    var sample = try Surface(width:80,height:64,depth:.f32,fill:Pixel(0.8,0.3,0.1))
    for y in 15...17 {
      for x in 0..<sample.width { sample.setLinearPixel(x:x,y:y,Pixel(0.2,0.6,0.9)) }
    }
    let selection = VanishingMarquee(plane:0,lower:.init(0.65,0.3),upper:.init(1.40,0.65),wrap:true)
    var stroke = VanishingOperation(.brush)
    stroke.color = Pixel(1,0,0)
    stroke.diameter = 6
    stroke.hardness = 100
    stroke.points = [.init(20.5,27.5),.init(54.5,27.5)]
    stroke.wrap = true
    stroke.strokeSelection = selection
    for kind: VanishingOperation.Kind in [.brush,.clone] {
      stroke.kind = kind
      // The Stamp reads a donor row outside the selection.
      stroke.sourcePoint = kind == .clone ? .init(20.5,16.5) : nil
      program.operations = [stroke]
      let result = try VanishingEngine.render(program,sample:sample)
      for x in [22,52] { XCTAssertEqual(result.linearPixel(x:x,y:27).a,0) }
      for x in [30,36,42] {
        let pixel = result.linearPixel(x:x,y:27)
        XCTAssertEqual(pixel.a,1,accuracy:1e-5)
        XCTAssertEqual(pixel.r,kind == .clone ? 0.2 : 1,accuracy:1e-5)
      }
    }

    stroke.kind = .brush
    stroke.sourcePoint = nil
    stroke.diameter = 1
    stroke.points = [.init(36.5,27.5)]
    stroke.strokeSelection = .init(plane:0,lower:.init(1,0.3),upper:.init(1.4,0.65),wrap:true)
    program.operations = [stroke]
    let halfDab = try VanishingEngine.render(program,sample:sample).linearPixel(x:36,y:27).a
    XCTAssertEqual(halfDab,.pi/8,accuracy:0.012)
    stroke.strokeSelection = nil
    program.operations = [stroke]
    let fullDab = try VanishingEngine.render(program,sample:sample).linearPixel(x:36,y:27).a
    XCTAssertEqual(fullDab,2*halfDab,accuracy:1e-5)
  }

  func testLinkedStampSamplesEarlierMarksAcrossTheDonorHinge() throws {
    var program = VanishingProgram()
    program.settings.planes = [.init(corners:[.init(10,10),.init(36.5,10),.init(36.5,50),.init(10,50)]),
      .init(parent:0,edge:.right,angle:180)]
    var source = try Surface(width:80,height:64,depth:.f32,fill:Pixel(0,0,1))
    for y in 0..<64 { for x in 37..<80 { source.setLinearPixel(x:x,y:y,Pixel(1,0,0)) } }
    var mark = VanishingOperation(.brush)
    mark.plane = 1
    mark.points = [.init(52.5,19.5)]
    mark.diameter = 8
    mark.hardness = 100
    mark.color = Pixel(0,1,0)
    var stamp = VanishingOperation(.clone)
    stamp.sourcePoint = .init(21.5,19.5)
    stamp.points = [.init(21.5,34.5),.init(59.5,34.5)]
    stamp.diameter = 4
    stamp.hardness = 100
    stamp.wrap = true
    program.operations = [mark,stamp]
    let output = try VanishingEngine.render(program,sample:source)
    XCTAssertEqual(output.linearPixel(x:29,y:34).b,1,accuracy:1e-5)
    XCTAssertEqual(output.linearPixel(x:52,y:34).g,1,accuracy:1e-5)
    XCTAssertEqual(output.linearPixel(x:59,y:34).r,1,accuracy:1e-5)
    XCTAssertEqual(output.linearPixel(x:65,y:34).a,0)
    let persisted = try JSONDecoder().decode(VanishingProgram.self,from:JSONEncoder().encode(program))
    XCTAssertEqual(persisted,program)
    var legacy = program
    legacy.operations[1].wrap = nil
    XCTAssertNil(try JSONDecoder().decode(VanishingProgram.self,from:JSONEncoder().encode(legacy)).operations[1].wrap)
  }

  func testIndependentCameraMetricAndConnectedPlane() throws {
    var settings=cameraPlane();let s=try VanishingScene(settings,width:800,height:600)
    XCTAssertEqual(s.focal,500,accuracy:1e-6);XCTAssertEqual(s.frames[0].width/s.frames[0].height,2,accuracy:1e-6)
    settings.planes.append(.init(parent:0,edge:.top));let linked=try VanishingScene(settings,width:800,height:600)
    let a=linked.frames[0],b=linked.frames[1];XCTAssertEqual(b.corners[3].x,a.corners[0].x,accuracy:1e-6);XCTAssertEqual(b.corners[2].y,a.corners[1].y,accuracy:1e-6)
    let n1=VanishingScene.unit(VanishingScene.cross(a.points[1]-a.points[0],a.points[3]-a.points[0])),n2=VanishingScene.unit(VanishingScene.cross(b.points[1]-b.points[0],b.points[3]-b.points[0]))
    XCTAssertLessThan(abs(VanishingScene.dot(n1,n2)),0.02)
    let p=PathPoint(0.3,0.8),back=a.uv(a.point(p));XCTAssertEqual(back.x,p.x,accuracy:1e-9);XCTAssertEqual(back.y,p.y,accuracy:1e-9)
  }

  func testRightAngleHingeRecoversCameraWhenItsSharedAxisIsParallel() throws {
    var settings = VanishingSettings()
    settings.focalLength = 980
    let hingeTop = PathPoint(580.4,185.4), hingeBottom = PathPoint(580.4,714.6)
    settings.planes = [.init(corners:[.init(299.493246750069,222.756390617123),
      hingeTop,hingeBottom,.init(299.493246750069,677.243609382877)])]
    let parent = try VanishingScene(settings,width:1200,height:900)
    let child = try parent.calibratedPlane(parent:0,edge:.right,corners:[hingeTop,
      .init(780.755988301344,291.944504055102),.init(780.755988301344,608.055495944898),hingeBottom],
      angleFromCoplanar:90)
    settings.planes.append(child)
    settings.focalLength = 0
    let inferred = try VanishingScene(settings,width:1200,height:900)
    XCTAssertEqual(inferred.focal,980,accuracy:1e-7)
    let a = inferred.measurementMetric(for:0), b = inferred.measurementMetric(for:1)
    XCTAssertEqual(b.x/a.x,2,accuracy:1e-8)
    XCTAssertEqual(b.y,a.y,accuracy:1e-8)

    settings.focalLength = 1100
    let pinned = try VanishingScene(settings,width:1200,height:900)
    XCTAssertEqual(pinned.focal,1100)
    XCTAssertNotEqual(pinned.measurementMetric(for:1),b)
  }
  func testMeasurementCalibrationAcrossHingeAndIndependentRoot() throws {
    var settings = cameraPlane()
    settings.planes.append(.init(parent:0,edge:.top))
    settings.planes.append(.init(corners:[.init(10,10),.init(210,10),.init(210,110),.init(10,110)]))
    let scene = try VanishingScene(settings,width:800,height:600)
    let hingeOnParent = VanishingMeasurement(plane:0,start:.init(0,0),end:.init(1,0))
    let hingeOnChild = VanishingMeasurement(plane:1,start:.init(0,1),end:.init(1,1))
    let independent = VanishingMeasurement(plane:2,start:.init(0,0),end:.init(1,0))
    settings.measurements = [hingeOnParent,hingeOnChild,independent]
    let calibration = try scene.measurementScale(calibrating:0,to:6,settings:settings)
    settings.setMeasurementScale(calibration)
    XCTAssertEqual(try XCTUnwrap(scene.measurementLength(hingeOnChild,settings:settings)),6,accuracy:1e-8)
    XCTAssertEqual(try XCTUnwrap(scene.measurementLength(independent,settings:settings)),2,accuracy:1e-8)
    XCTAssertEqual(scene.measurementRoot(for:1),0)
    XCTAssertEqual(scene.measurementRoot(for:2),2)

    var linked = calibration
    linked.linkedToGrid = true
    settings.setMeasurementScale(linked)
    for line in [hingeOnParent,hingeOnChild] {
      XCTAssertEqual(scene.frames[line.plane].width/scene.gridIntervals(for:line.plane,settings:settings).x,6,accuracy:1e-8)
    }
    let frame = scene.frames[0]
    let outside = try XCTUnwrap(scene.measurement(plane:0,from:frame.point(.init(0,0)),to:frame.point(.init(-0.25,0))))
    XCTAssertEqual(try XCTUnwrap(scene.measurementLength(outside,settings:settings)),1.5,accuracy:1e-8)
    XCTAssertThrowsError(try scene.measurementScale(calibrating:0,to:0,settings:settings))
    settings.measurementScales?.append(.init(root:1,pixelsPerUnit:100))
    XCTAssertThrowsError(try settings.validate())
  }

  func testIndependentPhotoshopPlaneDoesNotInheritAnExtremeCamera() throws {
    // Corners and lengths come from the owned Photoshop two-plane reference.
    var settings = VanishingSettings()
    settings.planes = [
      .init(corners:[.init(160.000054,200.028665),.init(1480,199.75),.init(1480,1000),.init(160,1000)]),
      .init(corners:[.init(329,46),.init(1228.999999,46),.init(1229.249999,153.999722),.init(329,155)])]
    settings.setMeasurementScale(.init(root:1,pixelsPerUnit:21.8189))
    let scene = try VanishingScene(settings,width:1600,height:1200)
    XCTAssertGreaterThan(scene.focal,2_000_000)
    let probes: [(Int,PathPoint,PathPoint,Double,Double)] = [
      (0,.init(1480,1000),.init(1480,199.75),8,0.02),
      (0,.init(1480,1000),.init(160,1000),16.4,0.02),
      (1,.init(329,155),.init(329,46),5,0.02),
      (1,.init(329,155),.init(1229.25,154),41.07,0.30)]
    for (index,start,end,reference,tolerance) in probes {
      let line = try XCTUnwrap(scene.measurement(plane:index,from:start,to:end))
      XCTAssertEqual(try XCTUnwrap(scene.measurementLength(line,settings:settings)),reference,accuracy:tolerance)
    }
  }

  func testMeasurementAnglesAndRasterSelectionAcrossDepths() throws {
    for depth in PixelDepth.allCases {
      var source = try CraftDocument(width:192,height:128,depth:depth)
      source.selection = .init(x:0,y:42,width:94,height:34)
      let empty = try Surface(width:192,height:128,depth:depth,fill:.clear)
      source.layers[0].content = .raster(empty)
      var program = VanishingProgram()
      program.settings.planes = [.init(corners:[.init(0,0),.init(192,0),.init(192,128),.init(0,128)])]
      let horizontal = VanishingMeasurement(plane:0,start:.init(0.125,0.5),end:.init(0.875,0.5))
      let vertical = VanishingMeasurement(plane:0,start:horizontal.start,end:.init(0.125,0.25))
      let diagonal = VanishingMeasurement(plane:0,start:.init(0.25,0.25),end:.init(0.5,0.625))
      let reversed = VanishingMeasurement(plane:0,start:horizontal.end,end:horizontal.start)
      program.settings.measurements = [horizontal,vertical]
      let scene = try VanishingScene(program.settings,width:192,height:128)
      XCTAssertEqual(try XCTUnwrap(scene.measurementAngle(horizontal,settings:program.settings)),90,accuracy:1e-8)
      XCTAssertEqual(try XCTUnwrap(scene.measurementAngle(vertical,settings:program.settings)),90,accuracy:1e-8)
      XCTAssertEqual(try XCTUnwrap(scene.measurementAngle(diagonal,settings:.init())),45,accuracy:1e-8)
      XCTAssertEqual(try XCTUnwrap(scene.measurementAngle(reversed,settings:.init())),0,accuracy:1e-8)
      let layerID = source.layers[0].id
      let unrendered = try VanishingEdit.prepare(source,layerID:layerID,program:program,sample:empty)
      XCTAssertEqual(unrendered.result.layers,source.layers)
      program.renderMeasurements = true
      let edit = try VanishingEdit.prepare(source,layerID:layerID,program:program,sample:empty)
      XCTAssertEqual(edit.result.vanishingPoint?.measurements,[horizontal,vertical])
      XCTAssertEqual(edit.result.layers[0].id,layerID)
      guard case .raster(let marks) = edit.result.layers[0].content else { return XCTFail() }
      XCTAssertGreaterThan(marks.pixel(x:65,y:63).a,0.8)
      XCTAssertGreaterThan(marks.pixel(x:23,y:49).a,0.8)
      XCTAssertEqual(marks.pixel(x:140,y:63).a,0)
      XCTAssertEqual(marks.pixel(x:23,y:35).a,0)
      XCTAssertEqual(marks.pixel(x:65,y:110).a,0)
      XCTAssertThrowsError(try edit.updatingDisplayMetadata(program.settings))

      var session = EditorSession(document:source)
      try session.execute(.vanishingPoint(edit))
      try session.undo()
      XCTAssertEqual(session.document,source)

      program.newLayer = true
      let onNew = try VanishingEdit.prepare(source,layerID:layerID,program:program,sample:empty)
      XCTAssertEqual(onNew.result.layers.count,2)
      XCTAssertEqual(onNew.result.layers[0],source.layers[0])
      guard case .raster(let placed) = onNew.result.layers[1].content else { return XCTFail() }
      XCTAssertGreaterThan(placed.pixel(x:65,y:63).a,0.8)
      XCTAssertEqual(placed.pixel(x:140,y:63).a,0)
    }
  }

  func testRasterMeasurementsUseSparseDiagonalTiles() throws {
    let side = 16_384
    let input = try Surface(width:side,height:side,fill:.clear)
    var program = VanishingProgram()
    program.settings.planes = [.init(corners:[.init(0,0),.init(Double(side),0),
      .init(Double(side),Double(side)),.init(0,Double(side))])]
    program.settings.measurements = [.init(plane:0,start:.init(0.01,0.01),end:.init(0.99,0.99))]
    program.renderMeasurements = true
    let raster = try VanishingEngine.render(program,sample:input)
    XCTAssertGreaterThan(raster.pixel(x:4096,y:4096).a,0.8)
    XCTAssertGreaterThan(raster.pixel(x:8192,y:8192).a,0.8)
    XCTAssertEqual(raster.pixel(x:2000,y:13000).a,0)
    XCTAssertLessThan(raster.storedTileKeys.reduce(0) { count,_ in count+1 },800)
  }

  func testSceneExportWeldsHingeAndReprojectsAllCorners() throws {
    var settings = cameraPlane()
    settings.planes.append(.init(parent:0,edge:.top,angle:90,depth:0.25))
    let scene = try VanishingScene(settings,width:800,height:600)
    let asset = try scene.exportGeometry(settings:settings,canvasWidth:800)
    XCTAssertEqual(asset.planes.count,2)
    XCTAssertEqual(asset.planes[0][0],asset.planes[1][3])
    XCTAssertEqual(asset.planes[0][1],asset.planes[1][2])
    let view = VanishingScene.unit(asset.target-asset.camera)
    let vertical = SIMD3<Double>(0,-1,0)
    let up0 = VanishingScene.unit(vertical-view*VanishingScene.dot(vertical,view))
    let radians = asset.rollDegrees * .pi / 180
    let up = up0*cos(radians)+VanishingScene.cross(view,up0)*sin(radians)
    let right = VanishingScene.cross(view,up)
    let focal = 400/tan(asset.horizontalAngleOfView * .pi / 360)
    for (mesh,frame) in zip(asset.planes,scene.frames) {
      for (point,source) in zip(mesh,frame.corners) {
        let ray = point-asset.camera, depth = VanishingScene.dot(ray,view)
        XCTAssertGreaterThan(depth,0)
        XCTAssertEqual(400+focal*VanishingScene.dot(ray,right)/depth,source.x,accuracy:1e-7)
        XCTAssertEqual(300-focal*VanishingScene.dot(ray,up)/depth,source.y,accuracy:1e-7)
      }
    }
    let firstNormal = VanishingScene.unit(VanishingScene.cross(asset.planes[0][1]-asset.planes[0][0],
      asset.planes[0][3]-asset.planes[0][0]))
    let secondNormal = VanishingScene.unit(VanishingScene.cross(asset.planes[1][1]-asset.planes[1][0],
      asset.planes[1][3]-asset.planes[1][0]))
    XCTAssertEqual(VanishingScene.dot(firstNormal,secondNormal),0,accuracy:0.02)
  }

  func testPerspectivePasteBrushCloneAndClippingAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var sample=try Surface(width:64,height:48,depth:depth,fill:Pixel(0.2,0.2,0.2)),program=plain(),paste=VanishingOperation(.paste)
      paste.source=try Surface(width:10,height:5,depth:depth,fill:Pixel(1,0,0));paste.width=0.5;program.operations=[paste]
      var result=try VanishingEngine.render(program,sample:sample)
      XCTAssertGreaterThan(result.pixel(x:30,y:20).r,0.9);XCTAssertGreaterThan(result.pixel(x:30,y:20).a,0.9);XCTAssertEqual(result.pixel(x:5,y:5).a,0)
      var brush=VanishingOperation(.brush);brush.points=[.init(10,10),.init(54,36)];brush.diameter=8;brush.color=Pixel(0,1,0);brush.hardness=100;program.operations=[brush]
      result=try VanishingEngine.render(program,sample:sample);XCTAssertGreaterThan(result.pixel(x:32,y:23).g,0.9);XCTAssertEqual(result.pixel(x:1,y:1).a,0)
      for y in 7..<15 { for x in 7..<15 { sample.setPixel(x:x,y:y,Pixel(1,0,0)) } }
      var clone=VanishingOperation(.clone);clone.sourcePoint = .init(11,11);clone.points=[.init(40,30)];clone.diameter=6;clone.hardness=100;program.operations=[clone]
      result=try VanishingEngine.render(program,sample:sample);XCTAssertGreaterThan(result.pixel(x:40,y:30).r,0.9);XCTAssertLessThan(result.pixel(x:40,y:30).g,0.01)
      clone.points=[.init(5,5)];clone.diameter=20;program.operations=[clone];result=try VanishingEngine.render(program,sample:sample);XCTAssertEqual(result.pixel(x:2,y:5).a,0)
    }
  }
  func testHistorySelectionLocksNative32AndAtomicInvalidEdits() throws {
    for depth in PixelDepth.allCases {
      let d=try CraftDocument(width:64,height:48,depth:depth),id=d.layers[0].id,sample=try Surface(width:64,height:48,depth:depth,fill:.white)
      var program=plain(),brush=VanishingOperation(.brush);brush.color=Pixel(1,0,0);brush.points=[.init(32,24)];brush.diameter=20;program.operations=[brush]
      let edit=try VanishingEdit.prepare(d,layerID:id,program:program,sample:sample);var session=EditorSession(document:d);try session.execute(.vanishingPoint(edit));let changed=session.document
      XCTAssertNotEqual(changed.layers[0].content,d.layers[0].content);XCTAssertEqual(changed.minimumArchiveVersion,32)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(changed)),changed);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(changed)),changed)
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,changed)
      var selected=d;selected.selection = .init(x:30,y:20,width:4,height:4);let selection=try VanishingEdit.prepare(selected,layerID:id,program:program,sample:sample)
      if case .raster(let pixels)=selection.result.layers[0].content { XCTAssertEqual(pixels.pixel(x:25,y:24),.white);XCTAssertGreaterThan(pixels.pixel(x:31,y:22).r,0.9);XCTAssertLessThan(pixels.pixel(x:31,y:22).g,0.1) }
      var locked=d;locked.layers[0].protection=[.image];XCTAssertThrowsError(try VanishingEdit.prepare(locked,layerID:id,program:program,sample:sample));program.newLayer=true
      let onNew=try VanishingEdit.prepare(locked,layerID:id,program:program,sample:sample);XCTAssertEqual(onNew.result.layers.count,2);XCTAssertEqual(onNew.result.layers[0],locked.layers[0])
      var invalid=program;invalid.operations[0].diameter = .nan;XCTAssertThrowsError(try VanishingEdit.prepare(d,layerID:id,program:invalid,sample:sample))
      XCTAssertThrowsError(try edit.applied(to:changed));XCTAssertEqual(d.layers.count,1)
    }
  }
  func testNarrowClonePreservesPartialPixelCoverageAndSelection() throws {
    for depth in PixelDepth.allCases {
      var source = try CraftDocument(width: 8_000, height: 6_000, depth: depth)
      let sample = try Surface(width: source.width, height: source.height, depth: depth, fill: Pixel(0.1, 0.5, 0.8))
      source.layers[0].content = .raster(sample)
      var program = VanishingProgram()
      program.newLayer = true
      program.settings.planes = [.init(corners: [.init(80, 80), .init(280, 80), .init(260, 220), .init(95, 220)])]
      var stamp = VanishingOperation(.clone)
      stamp.sourcePoint = .init(120, 120)
      stamp.points = [.init(192, 141)]
      stamp.diameter = 10
      stamp.hardness = 95
      program.operations = [stamp]
      let full = try VanishingEngine.render(program, sample: sample)
      // Independent 512 × 512 midpoint integration per image pixel.
      let expectedOpacity = 6.049914649656903
      var alpha = 0.0, covered = 0
      for y in 139..<143 {
        for x in 185..<200 {
          let pixel = full.pixel(x: x, y: y)
          alpha += Double(pixel.a)
          if pixel.a > 0 {
            covered += 1
            XCTAssertEqual(pixel.b, sample.defaultPixel.b, accuracy: 0.004)
          }
        }
      }
      XCTAssertEqual(covered, 20)
      XCTAssertEqual(alpha, expectedOpacity, accuracy: 0.04)
      XCTAssertEqual(full.pixel(x: 192, y: 140).a, 0.39251, accuracy: 0.013)
      source.selection = IntRect(x: 189, y: 140, width: 5, height: 1)
      let edit = try VanishingEdit.prepare(source, layerID: source.layers[0].id, program: program, sample: sample)
      XCTAssertEqual(edit.result.layers.first, source.layers.first)
      guard case .raster(let repair) = edit.result.layers.last?.content else { return XCTFail("Missing correction pixels") }
      XCTAssertEqual(try repair.contentBounds(), source.selection)
      XCTAssertEqual(repair.pixel(x: 192, y: 140), full.pixel(x: 192, y: 140))
      XCTAssertEqual(repair.pixel(x: 192, y: 141).a, 0)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)), edit.result)
    }
  }

  func testNarrowBrushIntegratesRotatedAndPartiallyClippedPixels() throws {
    let side = 64
    let sample = try Surface(width: side, height: side, depth: .f32, fill: .white)
    let angle = 37.0 * .pi / 180
    func screen(_ x: Double, _ y: Double) -> PathPoint {
      .init(24.1 + x * cos(angle) - y * sin(angle), 24.3 + x * sin(angle) + y * cos(angle))
    }
    var program = VanishingProgram()
    program.settings.planes = [.init(corners: [screen(0, 0), screen(24, 0), screen(24, 16), screen(0, 16)])]
    let frame = try XCTUnwrap(VanishingScene(program.settings, width: side, height: side).frames.first)
    var brush = VanishingOperation(.brush)
    brush.color = Pixel(0.5, 0.1, 0.8)
    brush.points = [screen(0.15, 6)]
    brush.diameter = 1
    brush.hardness = 40
    brush.opacity = 75
    let origin = frame.metric(brush.points[0])
    let offset = frame.metric(.init(brush.points[0].x + 0.5, brush.points[0].y))
    let radius = hypot(origin.x - offset.x, origin.y - offset.y)
    var areas = [Double]()
    for clip in [false, true] {
      brush.clip = clip
      program.operations = [brush]
      let rendered = try VanishingEngine.render(program, sample: sample)
      var area = 0.0
      for y in 27..<32 {
        for x in 18..<24 {
          var expected = 0.0
          for row in 0..<96 {
            for column in 0..<96 {
              let point = PathPoint(Double(x) + (Double(column) + 0.5) / 96,
                                    Double(y) + (Double(row) + 0.5) / 96)
              if clip && !frame.contains(point) { continue }
              let p = frame.metric(point)
              let distance = hypot(p.x - origin.x, p.y - origin.y) / radius
              guard distance < 1 else { continue }
              let weight = min(1.0, (1 - distance) / 0.6)
              expected += 0.75 * weight * weight * (3 - 2 * weight) / (96 * 96)
            }
          }
          let actual = Double(rendered.pixel(x: x, y: y).a)
          XCTAssertEqual(actual, expected, accuracy: 0.002)
          area += actual
        }
      }
      areas.append(area)
      brush.clip = clip
      program.operations = [brush, brush]
      let twice = try VanishingEngine.render(program, sample: sample)
      let bounds = try XCTUnwrap(rendered.contentBounds())
      for y in bounds.y..<(bounds.y + bounds.height) {
        for x in bounds.x..<(bounds.x + bounds.width) {
          let a = rendered.pixel(x: x, y: y).a
          XCTAssertEqual(twice.pixel(x: x, y: y).a, a + a * (1 - a), accuracy: 0.00001)
        }
      }
    }
    XCTAssertGreaterThan(areas[1], 0.1)
    XCTAssertLessThan(areas[1], areas[0])
  }

  func testLargePerspectiveStrokeTouchesOnlyTheSelectedTiles() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 6_000, height: 4_000, depth: depth)
      var sample = try Surface(width: document.width, height: document.height, depth: depth, fill: .white)
      for y in 3_924..<3_934 {
        for x in 5_911..<5_921 { sample.setPixel(x: x, y: y, Pixel(1, 0.1, 0.2)) }
      }
      document.layers[0].content = .raster(sample)
      document.selection = IntRect(x: 5_944, y: 3_942, width: 9, height: 7)
      let id = document.layers[0].id
      var program = plain()
      program.settings.focalLength = 150
      program.settings.center = .init(5_935, 3_940)
      program.settings.planes[0].corners = program.settings.planes[0].corners.map {
        .init($0.x + 5_905, $0.y + 3_920)
      }
      var clone = VanishingOperation(.clone)
      clone.sourcePoint = .init(5_916, 3_929)
      clone.points = [.init(5_949, 3_945)]
      clone.diameter = 18
      clone.hardness = 100
      program.operations = [clone]
      let edited = try VanishingEdit.prepare(document, layerID: id, program: program, sample: sample)
      guard case .raster(let raster) = edited.result.layers[0].content else { return XCTFail("Missing edited raster") }
      XCTAssertLessThan(raster.pixel(x: 5_948, y: 3_945).g, 0.2)
      XCTAssertEqual(raster.pixel(x: 5_943, y: 3_945), .white)
      XCTAssertEqual(raster.pixel(x: 0, y: 0), sample.pixel(x: 0, y: 0))
      XCTAssertLessThan(raster.tileCount, 10)

      program.newLayer = true
      let correction = try VanishingEdit.prepare(document, layerID: id, program: program, sample: sample)
      XCTAssertEqual(correction.result.layers[0], document.layers[0])
      let newLayer = try XCTUnwrap(correction.result.layers.last)
      guard case .raster(let repair) = newLayer.content else { return XCTFail("Missing correction layer") }
      XCTAssertGreaterThan(repair.pixel(x: 5_948, y: 3_945).a, 0.9)
      XCTAssertEqual(repair.pixel(x: 5_943, y: 3_945).a, 0)
      XCTAssertLessThan(repair.tileCount, 10)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(correction.result)), correction.result)
    }
  }

  func testOffAxisPlaneKeepsAllCornersInFrontOfTheCamera() throws {
    let corners = [PathPoint(80, 80), .init(280, 80), .init(260, 220), .init(95, 220)]
    var settings = VanishingSettings()
    settings.planes = [.init(corners: corners)]
    let scene = try VanishingScene(settings, width: 6_000, height: 4_000)
    let frame = try XCTUnwrap(scene.frames.first)
    XCTAssertEqual(frame.corners, corners)
    XCTAssertTrue(frame.points.allSatisfy { $0.z > 0 })
    let origin = frame.point(.init(0, 0))
    XCTAssertEqual(origin.x, corners[0].x, accuracy: 1e-9)
    XCTAssertEqual(origin.y, corners[0].y, accuracy: 1e-9)
  }

  func testCancellationDoesNotPublishPixelsOrPlaneMetadata() async throws {
    let d=try CraftDocument(width:64,height:48),id=d.layers[0].id,p=plain(),sample=try Surface(width:64,height:48,fill:.white)
    let task=Task.detached { withUnsafeCurrentTask { $0?.cancel() };return try VanishingEdit.prepare(d,layerID:id,program:p,sample:sample) }
    do { _=try await task.value;XCTFail("Cancelled preparation succeeded") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertNil(d.vanishingPoint)
  }
  func testPerspectiveHealSeparatesLightingAndColorAtAllDepths() throws {
    let width = 256, height = 128
    let sourceColor = SIMD3<Float>(48, 86, 142) / 255
    let destinationColor = SIMD3<Float>(110, 96, 63) / 255
    var program = VanishingProgram()
    program.settings.planes = [.init(corners: [.init(8, 8), .init(248, 8), .init(248, 120), .init(8, 120)])]
    var clone = VanishingOperation(.clone)
    clone.sourcePoint = .init(52, 64)
    clone.points = [.init(180, 64)]
    clone.diameter = 32
    clone.hardness = 100
    let defect = IntRect(x: 175, y: 59, width: 10, height: 10)
    func light(_ p: SIMD3<Float>) -> Float { 0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z }
    for depth in PixelDepth.allCases {
      var clean = try Surface(width: width, height: height, depth: depth,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      for y in 44..<84 {
        for x in 32..<202 where x < 76 || x >= 158 {
          let detail = Float((x % 8) - (y % 8)) / 255
          let rgb = (x < 76 ? sourceColor : destinationColor) + SIMD3(repeating: detail)
          VanishingEngine.write(&clean, x, y, Pixel(rgb.x, rgb.y, rgb.z))
        }
      }
      var damaged = clean
      for y in defect.y..<(defect.y + defect.height) {
        for x in defect.x..<(defect.x + defect.width) {
          VanishingEngine.write(&damaged, x, y, Pixel(0.75, 0.45, 0.1))
        }
      }
      clone.heal = nil
      program.operations = [clone]
      let direct = try VanishingEngine.render(program, sample: damaged)
      let encoded = try JSONEncoder().encode(program)
      let legacy = try JSONDecoder().decode(VanishingProgram.self, from: encoded)
      XCTAssertNil(legacy.operations[0].heal)
      clone.heal = .off
      program.operations = [clone]
      XCTAssertEqual(try VanishingEngine.render(program, sample: damaged), direct)
      program.operations[0].heal = .luminance
      let lit = try VanishingEngine.render(program, sample: damaged)
      program.operations[0].heal = .on
      let repaired = try VanishingEngine.render(program, sample: damaged)
      XCTAssertEqual(try repaired.contentBounds(), try direct.contentBounds())
      XCTAssertEqual(try lit.contentBounds(), try direct.contentBounds())
      let tolerance: Float = depth == .u8 ? 0.004 : 0.00003
      for y in defect.y..<(defect.y + defect.height) {
        for x in defect.x..<(defect.x + defect.width) {
          let raw = VanishingEngine.read(direct, x, y), lightOnly = VanishingEngine.read(lit, x, y)
          let full = VanishingEngine.read(repaired, x, y), expected = VanishingEngine.read(clean, x, y)
          XCTAssertEqual(full.a, raw.a)
          XCTAssertEqual(lightOnly.a, raw.a)
          XCTAssertEqual(full.r, expected.r, accuracy: tolerance)
          XCTAssertEqual(full.g, expected.g, accuracy: tolerance)
          XCTAssertEqual(full.b, expected.b, accuracy: tolerance)
          XCTAssertEqual(light(lightOnly.rgb), light(expected.rgb), accuracy: tolerance)
          XCTAssertEqual(lightOnly.r - lightOnly.g, raw.r - raw.g, accuracy: 2 * tolerance)
          XCTAssertEqual(lightOnly.g - lightOnly.b, raw.g - raw.b, accuracy: 2 * tolerance)
        }
      }
    }
  }

  func testPerspectiveHealsPastedCutoutWithTransparentBoundaryAndSelection() throws {
    let depth = PixelDepth.f32
    var sample = try Surface(width: 128, height: 128, depth: depth, colorEncoding: .linearRGB)
    var paste = try Surface(width: 48, height: 48, depth: depth, colorEncoding: .linearRGB)
    for y in 6..<42 {
      for x in 6..<42 {
        let texture = Float((x % 8) - (y % 8)) / 256
        paste.setLinearPixel(x: x, y: y, Pixel(0.19 + texture, 0.28 + texture, 0.49 + texture))
        if (7..<41).contains(x), (8..<41).contains(y) {
          sample.setLinearPixel(x: 48 + x, y: 36 + y, Pixel(0.41 + texture, 0.32 + texture, 0.38 + texture))
        }
      }
    }
    let clean = sample
    for y in 56..<64 { for x in 68..<76 { sample.setLinearPixel(x: x, y: y, Pixel(0.75, 0.42, 0.12)) } }
    var program = VanishingProgram()
    program.settings.planes = [.init(corners: [.init(8, 8), .init(120, 8), .init(120, 120), .init(8, 120)])]
    let frame = try XCTUnwrap(VanishingScene(program.settings, width: 128, height: 128).frames.first)
    var op = VanishingOperation(.paste)
    op.source = paste
    op.at = frame.uv(.init(48, 36))
    op.width = 48.0 / 112
    op.opacity = 60
    program.operations = [op]
    let direct = try VanishingEngine.render(program, sample: sample)
    program.operations[0].heal = .on
    let healed = try VanishingEngine.render(program, sample: sample)
    program.operations[0].heal = .luminance
    let lit = try VanishingEngine.render(program, sample: sample)
    XCTAssertEqual(try healed.contentBounds(), try direct.contentBounds())
    for y in 56..<64 {
      for x in 68..<76 {
        let actual = healed.linearPixel(x: x, y: y), wanted = clean.linearPixel(x: x, y: y)
        let raw = direct.linearPixel(x: x, y: y), light = lit.linearPixel(x: x, y: y)
        XCTAssertEqual(actual.r, wanted.r, accuracy: 0.00004)
        XCTAssertEqual(actual.g, wanted.g, accuracy: 0.00004)
        XCTAssertEqual(actual.b, wanted.b, accuracy: 0.00004)
        XCTAssertEqual(actual.a, raw.a)
        XCTAssertEqual(light.a, raw.a)
        XCTAssertEqual(light.r - light.g, raw.r - raw.g, accuracy: 0.00001)
      }
    }
    var document = try CraftDocument(width: 128, height: 128, depth: depth)
    document.layers[0].content = .raster(sample)
    document.selection = IntRect(x: 70, y: 58, width: 4, height: 4)
    program.operations[0].heal = .on
    program.newLayer = true
    let edit = try VanishingEdit.prepare(document, layerID: document.layers[0].id, program: program, sample: sample)
    XCTAssertEqual(edit.result.layers.first, document.layers.first)
    guard case .raster(let repair) = edit.result.layers.last?.content else { return XCTFail("Missing correction") }
    XCTAssertEqual(try repair.contentBounds(), document.selection)
    XCTAssertEqual(repair.linearPixel(x: 71, y: 60), healed.linearPixel(x: 71, y: 60))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)), edit.result)
  }

  func testPerspectiveHealBrushAndOversizedRepairBoundary() throws {
    var program = plain()
    var brush = VanishingOperation(.brush)
    brush.points = [.init(32, 24)]
    brush.diameter = 12
    brush.color = Pixel(0.2, 0.4, 0.6)
    brush.heal = .on
    program.operations = [brush]
    let background = Pixel(0.45, 0.6, 0.25)
    let sample = try Surface(width: 64, height: 48, depth: .u16, fill: background)
    let healed = try VanishingEngine.render(program, sample: sample)
    let center = healed.pixel(x: 32, y: 24)
    XCTAssertEqual(center.r, sample.defaultPixel.r, accuracy: 0.00003)
    XCTAssertEqual(center.g, sample.defaultPixel.g, accuracy: 0.00003)
    XCTAssertEqual(center.b, sample.defaultPixel.b, accuracy: 0.00003)
    XCTAssertEqual(healed.pixel(x: 0, y: 0), .clear)

    // A narrow stroke whose endpoints make the local solve too large.
    let wide = try Surface(width: 5_000, height: 5_000, fill: .white)
    program.settings.planes = [.init(corners: [.init(10, 10), .init(4_990, 10), .init(4_990, 4_990), .init(10, 4_990)])]
    program.operations[0].diameter = 10
    program.operations[0].points = [.init(100, 100), .init(3_000, 3_000)]
    XCTAssertThrowsError(try VanishingEngine.render(program, sample: wide)) {
      XCTAssertTrue($0.localizedDescription.contains("local repair budget"))
    }
  }

  func testVanishingPointGrowsBlankLayerThroughFeatheredSelection() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 64, height: 48, depth: depth)
      let layer = Layer(name: "Repair", content: .raster(try Surface(width: 1, height: 1, depth: depth)))
      document.layers.append(layer)
      document.activeLayerID = layer.id
      var coverage = [UInt8](repeating: 0, count: 64 * 48)
      coverage[24 * 64 + 29] = 128
      coverage[24 * 64 + 30] = 255
      document.setCoverageSelection(try SelectionMask(width: 64, height: 48, bytes: coverage))

      var program = plain()
      var brush = VanishingOperation(.brush)
      brush.points = [.init(30.5, 24.5)]
      brush.color = Pixel(0.25, 0.5, 0.75)
      brush.diameter = 12
      brush.hardness = 100
      program.operations = [brush]
      let sample = try Surface(width: 64, height: 48, depth: depth, fill: .white)
      let result = try VanishingEdit.prepare(document, layerID: layer.id, program: program, sample: sample).result
      XCTAssertEqual(result.layers.map(\.id), document.layers.map(\.id))
      XCTAssertEqual(result.layers.first, document.layers.first)
      XCTAssertEqual(result.activeLayerID, layer.id)
      guard case .raster(let repair) = result.layers[1].content else { return XCTFail("Missing repair raster") }
      XCTAssertEqual(try repair.contentBounds(), document.selection)
      XCTAssertEqual(repair.pixel(x: 29, y: 24).a, 128.0 / 255.0, accuracy: 0.00002)
      XCTAssertGreaterThan(repair.pixel(x: 29, y: 24).b, 0.73)
      XCTAssertEqual(repair.pixel(x: 30, y: 24).a, 1)
      XCTAssertEqual(repair.pixel(x: 28, y: 24), .clear)
      XCTAssertEqual(repair.pixel(x: 30, y: 23), .clear)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)

      var locked = document
      locked.layers[1].protection = [.transparency]
      let guarded = try VanishingEdit.prepare(locked, layerID: layer.id, program: program, sample: sample)
      XCTAssertEqual(guarded.result.layers, locked.layers)
    }
  }

  func testVanishingPointReframesCroppedAffineLayerWithoutMovingItsMask() throws {
    for depth in PixelDepth.allCases {
      for linked in [false, true] {
        var document = try CraftDocument(width: 64, height: 48, depth: depth)
        let original = try Surface(width: 10, height: 7, depth: depth, fill: Pixel(0.2, 0.65, 0.31))
        var target = Layer(name: "Cropped with a mask", content: .raster(original))
        target.x = 43
        target.y = 29
        target.affine = .init(a: 1, b: 0.125, c: -0.0625, d: 1, tx: 0.25, ty: -0.125)
        target.mask = try Surface(width: 6, height: 4, depth: depth, fill: Pixel(0.2, 0.2, 0.2))
        var mask = MaskProperties()
        mask.linked = linked
        mask.outside = 1
        mask.transform = .translation(1, 4)
        target.maskProperties = mask
        document.layers.append(target)
        document.activeLayerID = target.id
        document.selection = .init(x: 19, y: 15, width: 9, height: 8)

        var program = plain()
        var brush = VanishingOperation(.brush)
        brush.points = [.init(24, 20)]
        brush.diameter = 14
        brush.color = Pixel(0.65, 0.21, 0.15)
        brush.hardness = 100
        program.operations = [brush]
        let sample = try Surface(width: 64, height: 48, depth: depth, fill: .white)
        let result = try VanishingEdit.prepare(document, layerID: target.id, program: program, sample: sample).result
        let updated = result.layers[1]
        guard case .raster(let repair) = updated.content else { return XCTFail("Missing grown raster") }
        XCTAssertEqual(updated.id, target.id)
        XCTAssertEqual(updated.mask, target.mask)
        XCTAssertEqual(updated.maskCoordinateTransform, target.maskCoordinateTransform)
        XCTAssertEqual(updated.effectiveMaskProperties.linked, linked)
        XCTAssertGreaterThan(repair.width, original.width)
        XCTAssertGreaterThan(repair.height, original.height)
        let retained = try updated.coordinateTransform.inverted() * target.coordinateTransform
        let start = retained.point(0, 0)
        let ox = Int(start.x.rounded()), oy = Int(start.y.rounded())
        XCTAssertGreaterThan(ox, 0)
        XCTAssertGreaterThan(oy, 0)
        XCTAssertEqual(retained.a, 1, accuracy: 0.000001)
        XCTAssertEqual(retained.d, 1, accuracy: 0.000001)
        XCTAssertTrue((0..<original.height).allSatisfy { y in
          (0..<original.width).allSatisfy { x in
            VanishingEngine.read(original, x, y).hasSameBits(as: VanishingEngine.read(repair, x + ox, y + oy))
          }
        })
        let painted = try updated.coordinateTransform.inverted().point(23.5, 20.5)
        XCTAssertGreaterThan(repair.pixel(x: Int(floor(painted.x)), y: Int(floor(painted.y))).a, 0.9)
      }
    }
  }

  func testDefaultCameraPinsAndReopensAtSupportedCanvasLimit() throws {
    let limit = Surface.maxDimension
    for (width, height) in [(100_000, 500), (100_001, 500), (500, limit), (limit, limit)] {
      var original = try CraftDocument(width: width, height: height)
      let sample = try Surface(width: width, height: height, fill: .white)
      original.layers[0].content = .raster(sample)
      let id = original.layers[0].id
      var program = VanishingProgram()
      program.newLayer = true
      program.settings.planes = [.init(corners: [.init(80, 80), .init(280, 80), .init(280, 220), .init(80, 220)])]
      var brush = VanishingOperation(.brush)
      brush.points = [.init(185, 140)]
      brush.diameter = 10
      brush.color = Pixel(0.2, 0.5, 0.8)
      program.operations = [brush]
      let edit = try VanishingEdit.prepare(original, layerID: id, program: program, sample: sample)
      let camera = try XCTUnwrap(edit.result.vanishingPoint)
      XCTAssertEqual(camera.focalLength, Double(max(width, height)))
      XCTAssertEqual(camera.center, PathPoint(Double(width) / 2, Double(height) / 2))
      XCTAssertEqual(edit.result.layers.first, original.layers.first)
      guard case .raster(let repair) = edit.result.layers.last?.content else { return XCTFail("Missing correction") }
      XCTAssertEqual(repair.tileCount, 1)
      XCTAssertGreaterThan(repair.pixel(x: 185, y: 140).a, 0.9)
      XCTAssertEqual(repair.pixel(x: width - 1, y: height - 1), .clear)
      let reopened = try NativeArchive.decode(NativeArchive.encodeChunked(edit.result))
      XCTAssertEqual(reopened, edit.result)
      program.settings = try XCTUnwrap(reopened.vanishingPoint)
      let replay = try VanishingEdit.prepare(original, layerID: id, program: program, sample: sample)
      XCTAssertEqual(replay.result.layers.last?.content, edit.result.layers.last?.content)
      XCTAssertEqual(replay.result.vanishingPoint, camera)
      var session = EditorSession(document: original)
      try session.execute(.vanishingPoint(edit))
      try session.undo()
      XCTAssertEqual(session.document, original)
    }
  }

  func testCalibratedCameraBeyondCanvasExtentSurvivesPreparation() throws {
    let size = Surface.maxDimension
    let center = PathPoint(Double(size) / 2, Double(size) / 2)
    var automatic = cameraPlane()
    automatic.center = center
    automatic.planes[0].corners = automatic.planes[0].corners.map {
      .init(center.x + ($0.x - 400) * 1_000, center.y + ($0.y - 300) * 1_000)
    }
    let scene = try VanishingScene(automatic, width: size, height: size)
    XCTAssertEqual(scene.focal, 500_000, accuracy: 0.00001)
    let original = try CraftDocument(width: size, height: size)
    let sample = try Surface(width: size, height: size, fill: .white)
    var program = VanishingProgram()
    program.settings = automatic
    let id = original.layers[0].id
    let edited = try VanishingEdit.prepare(original, layerID: id, program: program, sample: sample)
    let reopened = try NativeArchive.decode(NativeArchive.encodeChunked(edited.result))
    program.settings = try XCTUnwrap(reopened.vanishingPoint)
    XCTAssertEqual(program.settings.focalLength, scene.focal)
    let pinned = try VanishingScene(program.settings, width: size, height: size)
    XCTAssertEqual(pinned.frames[0].points, scene.frames[0].points)

    for invalid in [-1.0, .infinity, .nan] {
      program.settings.focalLength = invalid
      XCTAssertThrowsError(try program.settings.validate())
    }
    program.settings.focalLength = .greatestFiniteMagnitude
    XCTAssertThrowsError(try VanishingScene(program.settings, width: size, height: size))
  }

  func testInvalidPlanesAndMetadataCanvasTransform() throws {
    var focal=plain().settings;focal.focalLength=1;XCTAssertEqual(try VanishingScene(focal,width:64,height:48).focal,1)
    var p=plain();p.settings.planes.append(.init(parent:1,edge:.top));XCTAssertThrowsError(try p.validate())
    p=plain();p.settings.planes[0].corners[2]=p.settings.planes[0].corners[1];XCTAssertThrowsError(try p.validate())
    var d=try CraftDocument(width:64,height:48),settings=plain().settings;settings.center = .init(32,24);settings.focalLength=64;d.vanishingPoint=settings
    try Command.canvasSize(84,68,.center,nil).apply(to:&d);XCTAssertEqual(d.vanishingPoint?.center,.init(42,34));XCTAssertEqual(d.vanishingPoint?.planes[0].corners[0],.init(14,14))
  }
}
