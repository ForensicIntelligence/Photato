import XCTest
@testable import PhotoCraftCore

final class SelectionMattingTests: XCTestCase {
  func testFilterPrimitivesAgainstIndependentSmallReferences() throws {
    let input: [Float] = [0,1,2,3,4,5,6,7,8,9,10,11]
    let box = try MattingFilters.box(input,4,3,1)
    for y in 0..<3 { for x in 0..<4 {
      let values = (max(0,y-1)...min(2,y+1)).flatMap { yy in (max(0,x-1)...min(3,x+1)).map { input[yy*4+$0] } }
      XCTAssertEqual(box[y*4+x],values.reduce(0,+)/Float(values.count),accuracy:1e-6)
    } }
    let d = try MattingFilters.distance((0..<12).map { $0 == 5 },4,3)
    for y in 0..<3 { for x in 0..<4 { XCTAssertEqual(d[y*4+x],Float(hypot(Double(x-1),Double(y-1))),accuracy:1e-6) } }
    let blur = try MattingFilters.gaussian(Array(repeating:0.4,count:12),4,3,2)
    XCTAssertTrue(blur.allSatisfy { abs($0-0.4)<1e-6 })
    let maxed = try MattingFilters.extreme(input,4,3,1,maximum:true)
    XCTAssertEqual(maxed[0],5); XCTAssertEqual(maxed[5],10); XCTAssertEqual(maxed[11],11)
    XCTAssertEqual(try MattingFilters.distance([true],1,1),[0])
  }
  func testIdentitySoftEdgesContrastShiftAndConstantMasks() throws {
    let mask = try SelectionMask.make(.rectangle(.init(x:8,y:4,width:16,height:16)),width:32,height:24,antiAlias:false)
    let guide = try Surface(width:32,height:24,fill:Pixel(0.3,0.5,0.2))
    var p = SelectionRefinement()
    XCTAssertEqual(try SelectionMatting.refine(mask,guide:guide,settings:p),mask)
    p.feather = 3
    let feather = try SelectionMatting.refine(mask,guide:guide,settings:p)
    XCTAssertTrue(feather.bytes.contains { $0 > 0 && $0 < 255 }); XCTAssertGreaterThan(feather.bytes[12*32+7],0)
    p.contrast = 100
    let contrast = try SelectionMatting.refine(mask,guide:guide,settings:p)
    XCTAssertLessThan(contrast.bytes.filter { $0 > 0 && $0 < 255 }.count,feather.bytes.filter { $0 > 0 && $0 < 255 }.count)
    p = .init(); p.shiftEdge = 100
    let grown = try SelectionMatting.refine(mask,guide:guide,settings:p)
    XCTAssertGreaterThan(grown.bytes.filter { $0>0 }.count,mask.bytes.filter { $0>0 }.count)
    p.shiftEdge = -100
    XCTAssertLessThan(try SelectionMatting.refine(mask,guide:guide,settings:p).bytes.filter { $0>0 }.count,mask.bytes.filter { $0>0 }.count)
    p.radius = 3; p.smartRadius = true; p.smooth = 25
    for byte: UInt8 in [0,255] {
      let constant = try SelectionMask(width:32,height:24,bytes:Array(repeating:byte,count:32*24))
      XCTAssertEqual(try SelectionMatting.refine(constant,guide:guide,settings:p),constant)
    }
  }
  func testTiledGuidedRefinementHasNoSeamAndRespectsProtectedEdges() throws {
    let w = 520,h = 12
    var guide = try Surface(width:w,height:h), bytes = [UInt8](repeating:0,count:w*h)
    for y in 0..<h { for x in 0..<w { let a: Float = y<6 ? 0.15:0.9; guide.setPixel(x:x,y:y,Pixel(a,a,a)); bytes[y*w+x] = y<5 ? 0:255 } }
    let mask = try SelectionMask(width:w,height:h,bytes:bytes)
    var p = SelectionRefinement(); p.radius = 4
    let result = try SelectionMatting.refine(mask,guide:guide,settings:p)
    XCTAssertNotEqual(result,mask)
    for y in 0..<h { for x in [250,255,256,257,511,512] { XCTAssertEqual(result.bytes[y*w+x],result.bytes[y*w+200]) } }
    let excluded = try SelectionMask(width:w,height:h,bytes:Array(repeating:255,count:w*h))
    XCTAssertEqual(try SelectionMatting.refine(mask,guide:guide,settings:p,excluded:excluded),mask)
  }
  func testDecontaminationPreservesAlphaHDRAndOriginalPixels() throws {
    var source = try Surface(width:9,height:1,depth:.f32,colorEncoding:.linearRGB)
    for x in 0..<9 { source.setLinearPixel(x:x,y:0,x<5 ? Pixel(2,0,0,0.75):Pixel(0,1,0,0.75)) }
    let mask = try SelectionMask(width:9,height:1,bytes:[255,255,255,255,255,128,64,0,0])
    var p = SelectionRefinement(); p.decontaminate = true
    let result = try SelectionMatting.decontaminate(source,mask:mask,settings:p)
    XCTAssertGreaterThan(result.linearPixel(x:5,y:0).r,1)
    XCTAssertEqual(result.linearPixel(x:5,y:0).a,source.linearPixel(x:5,y:0).a)
    XCTAssertEqual(result.linearPixel(x:0,y:0),source.linearPixel(x:0,y:0))
    XCTAssertEqual(result.linearPixel(x:8,y:0),source.linearPixel(x:8,y:0))
    p.amount = 0; XCTAssertEqual(try SelectionMatting.decontaminate(source,mask:mask,settings:p),source)
  }
  func testAllOutputModesHistoryPersistenceAndEmptyMaskAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width:8,height:6,depth:depth); d.resolution = 300
      d.layers[0].x = 1; d.layers[0].affine = .scale(0.8,0.8)
      let mask = try SelectionMask.make(.rectangle(.init(x:2,y:2,width:3,height:2)),width:8,height:6,antiAlias:false)
      for output in SelectionRefinementOutput.allCases {
        let edit = SelectionRefinementEdit(layerID:d.layers[0].id,output:output,mask:mask)
        if output.createsDocument {
          let made = try edit.applied(to:d); XCTAssertNotEqual(made.id,d.id); XCTAssertEqual(made.layers.count,1); XCTAssertEqual(made.pixelsPerInch,300)
          XCTAssertThrowsError(try Command.selectionRefinement(edit).apply(to:&d)); continue
        }
        var session = EditorSession(document:d); try session.execute(.selectionRefinement(edit)); let result = session.document
        XCTAssertEqual(session.undoStack.count,1); XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
        if output == .selection { XCTAssertEqual(result.selectionMask,mask) }
        else {
          let layer = try XCTUnwrap(result.layers.last)
          XCTAssertEqual(result.layers[0].content,d.layers[0].content)
          if output == .layerMask || output == .newLayerWithMask { XCTAssertNotNil(layer.mask); XCTAssertEqual(layer.maskProperties?.transform,try layer.coordinateTransform.inverted()) }
          else { XCTAssertNil(layer.mask) }
        }
        try session.undo(); XCTAssertEqual(session.document,d); try session.redo(); XCTAssertEqual(session.document,result)
      }
      let empty = try SelectionMask(width:8,height:6,bytes:Array(repeating:0,count:48))
      let blank = try SelectionRefinementEdit(layerID:d.layers[0].id,output:.layerMask,mask:empty).applied(to:d)
      XCTAssertEqual(blank.layers[0].mask?.pixel(x:3,y:3).r,0)
    }
  }
  func testValidationAndCancellation() async throws {
    for raw in [#"{"radius":-1}"#,#"{"feather":1001}"#,#"{"smartRadius":1}"#,#"{"radius":true}"#,#"{"unknown":0}"#] {
      XCTAssertThrowsError(try SelectionRefinement.decodeJSON(Data(raw.utf8)))
    }
    XCTAssertThrowsError(try SelectionMatting.checkSize(32768,32768))
    let worker = Task {
      try await Task.sleep(for:.milliseconds(50))
      return try SelectionMatting.refine(SelectionMask(width:1,height:1,bytes:[255]),guide:Surface(width:1,height:1),settings:.init())
    }
    worker.cancel(); do { _ = try await worker.value; XCTFail() } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error") }
  }
}
