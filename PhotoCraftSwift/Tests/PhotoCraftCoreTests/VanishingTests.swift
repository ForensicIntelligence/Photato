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
  func testIndependentCameraMetricAndConnectedPlane() throws {
    var settings=cameraPlane();let s=try VanishingScene(settings,width:800,height:600)
    XCTAssertEqual(s.focal,500,accuracy:1e-6);XCTAssertEqual(s.frames[0].width/s.frames[0].height,2,accuracy:1e-6)
    settings.planes.append(.init(parent:0,edge:.top));let linked=try VanishingScene(settings,width:800,height:600)
    let a=linked.frames[0],b=linked.frames[1];XCTAssertEqual(b.corners[3].x,a.corners[0].x,accuracy:1e-6);XCTAssertEqual(b.corners[2].y,a.corners[1].y,accuracy:1e-6)
    let n1=VanishingScene.unit(VanishingScene.cross(a.points[1]-a.points[0],a.points[3]-a.points[0])),n2=VanishingScene.unit(VanishingScene.cross(b.points[1]-b.points[0],b.points[3]-b.points[0]))
    XCTAssertLessThan(abs(VanishingScene.dot(n1,n2)),0.02)
    let p=PathPoint(0.3,0.8),back=a.uv(a.point(p));XCTAssertEqual(back.x,p.x,accuracy:1e-9);XCTAssertEqual(back.y,p.y,accuracy:1e-9)
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
  func testInvalidPlanesAndMetadataCanvasTransform() throws {
    var focal=plain().settings;focal.focalLength=1;XCTAssertEqual(try VanishingScene(focal,width:64,height:48).focal,1)
    var p=plain();p.settings.planes.append(.init(parent:1,edge:.top));XCTAssertThrowsError(try p.validate())
    p=plain();p.settings.planes[0].corners[2]=p.settings.planes[0].corners[1];XCTAssertThrowsError(try p.validate())
    var d=try CraftDocument(width:64,height:48),settings=plain().settings;settings.center = .init(32,24);settings.focalLength=64;d.vanishingPoint=settings
    try Command.canvasSize(84,68,.center,nil).apply(to:&d);XCTAssertEqual(d.vanishingPoint?.center,.init(42,34));XCTAssertEqual(d.vanishingPoint?.planes[0].corners[0],.init(14,14))
  }
}
