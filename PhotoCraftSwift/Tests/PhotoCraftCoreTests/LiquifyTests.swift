import XCTest
@testable import PhotoCraftCore

final class LiquifyTests: XCTestCase {
  func testIdentityFilterPreservesHiddenRGBAndHasNoHistoryAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width:2,height:1,depth:depth)
      var s = try Surface(width:2,height:1,depth:depth,colorEncoding:depth == .f32 ? .linearRGB : .sRGB)
      for (x,p) in [Pixel(0.8,0.3,depth == .f32 ? 2:0.4,0),Pixel(0.25,0.5,1,0.3)].enumerated() {
        if depth == .f32 { s.setLinearPixel(x:x,y:0,p) } else { s.setPixel(x:x,y:0,p) }
      }
      d.layers[0].content = .raster(s)
      for strokes in [[],[LiquifyStroke(tool:.freezeAll)]] {
        var f = RasterFilter(.liquify); f.liquify?.strokes = strokes
        var session = EditorSession(document:d); try session.execute(.applyFilter(d.layers[0].id,f))
        XCTAssertEqual(session.document,d); XCTAssertTrue(session.undoStack.isEmpty)
      }
    }
  }
  func warp() -> LiquifyStroke { LiquifyStroke(size:40,points:[[40,32],[52,32]]) }
  func testWarpDirectionReconstructionAndDeterministicReplay() throws {
    let value = LiquifySettings(width:96,height:64,strokes:[warp()])
    var a = try value.field(targetWidth:96,targetHeight:64), b = try value.field(targetWidth:96,targetHeight:64)
    XCTAssertEqual(a,b); XCTAssertLessThan(a.sample(x:52,y:32).x,-4)
    XCTAssertEqual(a.sample(x:52,y:32).y,0,accuracy:0.5)
    var reconstruct = LiquifyStroke(tool:.reconstructAll); reconstruct.amount = 100
    try a.apply(reconstruct); XCTAssertTrue(a.isIdentity)
    XCTAssertEqual(try LiquifyMeshFile.decode(LiquifyMeshFile.encode(value)),value)
    XCTAssertEqual(try LiquifySettings.decodeJSON(Data(#"{"strokes":[{"size":40,"points":[[40,32],[52,32]]}],"width":96,"height":64}"#.utf8)),value)
  }
  func testFreezeThawLassoAndGlobalProtection() throws {
    var f = try LiquifyField(width:96,height:64)
    var freeze = LiquifyStroke(tool:.freeze,size:60,points:[[40,32]]); freeze.density = 0
    try f.apply(freeze); XCTAssertGreaterThan(f.frozen(x:40,y:32),0.99)
    try f.apply(warp()); XCTAssertEqual(f.sample(x:40,y:32).x,0,accuracy:0.001)
    freeze.tool = .thaw; try f.apply(freeze); XCTAssertLessThan(f.frozen(x:40,y:32),0.01)
    try f.apply(.init(tool:.freezeAll)); XCTAssertTrue(f.freeze.allSatisfy { $0 == 1 })
    try f.apply(.init(tool:.invertFreeze)); XCTAssertTrue(f.freeze.allSatisfy { $0 == 0 })
    try f.apply(.init(tool:.lassoMask,points:[[10,10],[50,10],[50,50],[10,50]]))
    XCTAssertEqual(f.frozen(x:30,y:30),1); XCTAssertEqual(f.frozen(x:5,y:5),0)
    try f.apply(.init(tool:.thawAll)); XCTAssertTrue(f.freeze.allSatisfy { $0 == 0 })
  }
  func testToolsHaveCorrectSenseAndSmoothRelaxes() throws {
    for (tool,axis,sign) in [(LiquifyTool.pucker,0,1.0),(.bloat,0,-1),(.twirlCw,1,-1),(.twirlCcw,1,1)] {
      let stroke = LiquifyStroke(tool:tool,size:40,points:Array(repeating:[48,32],count:10))
      let field = try LiquifySettings(width:96,height:64,strokes:[stroke]).field(targetWidth:96,targetHeight:64)
      XCTAssertGreaterThan(field.sample(x:58,y:32)[axis]*sign,0.1)
    }
    var field = try LiquifySettings(width:96,height:64,strokes:[LiquifyStroke(size:12,points:[[40,32],[50,32]])]).field(targetWidth:96,targetHeight:64)
    let before = field.maximumDisplacement
    try field.apply(.init(tool:.smooth,size:60,points:Array(repeating:[45,32],count:20)))
    XCTAssertLessThan(field.maximumDisplacement,before)
    let push = try LiquifySettings(width:96,height:64,strokes:[.init(tool:.pushLeft,size:40,points:[[48,44],[48,20]])]).field(targetWidth:96,targetHeight:64)
    XCTAssertGreaterThan(push.sample(x:48,y:32).x,0.5)
  }
  func testResamplingIdentityAndOpaqueMarkerMotion() throws {
    let w = 96, h = 64
    let input = (0..<(w*h)).map { i in SIMD4<Double>(i%w == 40 && (28..<36).contains(i/w) ? 1 : 0,0,0,1) }
    let identity = try LiquifyField(width:w,height:h)
    XCTAssertEqual(try identity.resample(input,width:w,height:h),input)
    let field = try LiquifySettings(width:w,height:h,strokes:[warp()]).field(targetWidth:w,targetHeight:h)
    let result = try field.resample(input,width:w,height:h)
    let peak = try XCTUnwrap((30..<70).max { result[32*w+$0].x < result[32*w+$1].x })
    XCTAssertGreaterThan(peak,44); XCTAssertTrue(result.allSatisfy { abs($0.w-1) < 1e-12 })
  }
  func testFaceControlsAndFreezeShareTheField() throws {
    let geometry = LiquifyFaceGeometry(bounds:[0.2,0.1,0.6,0.8],leftEye:[0.3,0.3,0.1,0.06],rightEye:[0.6,0.3,0.1,0.06],nose:[0.44,0.4,0.12,0.2],mouth:[0.35,0.65,0.3,0.1])
    var face = LiquifyFaceAdjustment(geometry:geometry)
    var settings = LiquifySettings(width:96,height:64); settings.faces = [face]
    XCTAssertTrue(try settings.field(targetWidth:96,targetHeight:64).isIdentity)
    face[.leftEyeSize] = 80; face[.smile] = 45; settings.faces = [face]
    XCTAssertFalse(try settings.field(targetWidth:96,targetHeight:64).isIdentity)
    settings.strokes = [.init(tool:.freezeAll)]
    XCTAssertTrue(try settings.field(targetWidth:96,targetHeight:64).isIdentity)
    XCTAssertEqual(try LiquifyMeshFile.decode(LiquifyMeshFile.encode(settings)),settings)
    face.parameters["unknown"] = 0; XCTAssertThrowsError(try face.validate())
  }
  func testMalformedProgramsAndPublicSegmentsReject() throws {
    for json in [#"{"width":-1}"#,#"{"meshSize":0.5}"#,#"{"strokes":[{"size":0}]}"#,#"{"strokes":[{"tool":"bad"}]}"#,#"{"strokes":[{"pressure":101}]}"#,#"{"strokes":[{"points":[[1,2,3]]}]}"#,#"{"unknown":1}"#,#"{"strokes":[{"size":true}]}"#] {
      XCTAssertThrowsError(try LiquifySettings.decodeJSON(Data(json.utf8)),json)
    }
    var field = try LiquifyField(width:10,height:10)
    XCTAssertThrowsError(try field.segment(warp(),from:[.nan,0],to:[0,1]))
    XCTAssertEqual(field.cubicSample(x:.nan,y:0),.zero)
    XCTAssertThrowsError(try LiquifyField(width:65536,height:65536))
    XCTAssertThrowsError(try LiquifyMeshFile.decode(Data(#"{"format":"other","version":1,"settings":{"width":0,"height":0,"meshSize":0,"strokes":[]}}"#.utf8)))
  }
}
